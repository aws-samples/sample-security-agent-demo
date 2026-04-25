"""
Lambda function for AI-powered Terraform code generation.

Converts natural language infrastructure requests into Terraform code
using Amazon Bedrock, then creates GitHub pull requests with the output.
"""

import json
import os
import re
import time
import base64
import logging
import urllib.request
import urllib.error

import boto3
from botocore.exceptions import ClientError

# --- Configuration from environment variables ---
CONTEXT_BUCKET = os.environ.get('CONTEXT_BUCKET', '')
CONTEXT_KEY = os.environ.get('CONTEXT_KEY', 'it-operations-tags.json')
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN', '')
GITHUB_OWNER = os.environ.get('GITHUB_OWNER', '')
GITHUB_REPO = os.environ.get('GITHUB_REPO', '')
BEDROCK_MODEL_ID = os.environ['BEDROCK_MODEL_ID']
BEDROCK_MAX_TOKENS = int(os.environ.get('BEDROCK_MAX_TOKENS', '2000'))

# Default path for generated Terraform files
DEFAULT_TARGET_FILE = 'generated/main.tf'
GITHUB_API_BASE = 'https://api.github.com'

# Allowed URL schemes for outbound HTTP requests. Restricting to HTTPS prevents
# urllib from dispatching to file://, ftp://, or other handlers if a URL is
# ever sourced from untrusted input.
_ALLOWED_URL_SCHEMES = ('https://',)


def _safe_urlopen(request_or_url):
    """Open a URL after validating its scheme against an allowlist."""
    url = request_or_url.full_url if isinstance(request_or_url, urllib.request.Request) else request_or_url
    if not url.startswith(_ALLOWED_URL_SCHEMES):
        raise ValueError(f'Disallowed URL scheme: {url!r}')
    return urllib.request.urlopen(request_or_url)  # nosec B310 - scheme validated above

# --- AWS clients ---
bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')

# --- Logging ---
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# --- Resource keyword mapping for request parsing ---
RESOURCE_MAP = {
    'ec2': ['instance', 'server', 'vm', 'compute'],
    'rds': ['database', 'db', 'mysql', 'postgres'],
    'vpc': ['network', 'subnet', 'vpc'],
    's3': ['bucket', 'storage'],
    'elb': ['load balancer', 'alb', 'nlb'],
    'ebs': ['volume', 'disk', 'storage'],
    'iam': ['role', 'policy', 'user', 'permission'],
    'security': ['security group', 'firewall', 'sg'],
}

# Keywords for detecting operation type
UPDATE_KEYWORDS = ['update', 'modify', 'fix', 'change', 'correct', 'adjust', 'revise']
CREATE_KEYWORDS = ['create', 'add', 'new', 'generate', 'build']

# Regex patterns for extracting target file path from requests
FILE_PATH_PATTERNS = [
    r'in\s+([\w/.-]+\.tf)',
    r'to\s+([\w/.-]+\.tf)',
    r'file\s+([\w/.-]+\.tf)',
]

# Terraform attributes to extract when summarizing files
SUMMARY_ATTRIBUTES = ['name', 'instance_type', 'ami', 'vpc_id', 'subnet_id', 'availability_zone']

# Max resources to include in context to stay within token limits
MAX_RESOURCES_PER_FILE = 5
MAX_BLOCKS_FOR_UPDATE = 3


# --- GitHub API helper ---

def _github_request(path, method='GET', data=None):
    """Make an authenticated request to the GitHub API."""
    url = f'{GITHUB_API_BASE}/repos/{GITHUB_OWNER}/{GITHUB_REPO}/{path}'
    headers = {
        'Authorization': f'token {GITHUB_TOKEN}',
        'Content-Type': 'application/json',
    }
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with _safe_urlopen(req) as response:
        return json.loads(response.read())


# --- Handler ---

def lambda_handler(event, context):
    """Entry point for API Gateway requests."""
    try:
        request = json.loads(event['body'])
        infrastructure_request = request.get('request', '')
        logger.info('Processing request: %s', infrastructure_request)

        context_data = get_s3_context()
        terraform_code, target_file, file_sha = generate_terraform_code(
            infrastructure_request, context_data
        )
        pr_url = create_github_pr(terraform_code, target_file, file_sha)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'terraform_code': terraform_code,
                'pr_url': pr_url,
                'status': 'success',
            }),
        }
    except Exception as e:
        logger.error('Request failed: %s', str(e), exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)}),
        }


# --- S3 context ---

def get_s3_context():
    """Fetch organizational tags/context from S3."""
    try:
        response = s3.get_object(Bucket=CONTEXT_BUCKET, Key=CONTEXT_KEY)
        return json.loads(response['Body'].read())
    except ClientError as e:
        logger.warning('Failed to load S3 context: %s', str(e))
        return {}


# --- Request parsing ---

def identify_relevant_resources(request):
    """Extract AWS resource types mentioned in the request."""
    relevant = set()
    request_lower = request.lower()
    for resource_type, keywords in RESOURCE_MAP.items():
        if any(kw in request_lower for kw in keywords):
            relevant.add(resource_type)
    return list(relevant)


def detect_operation_type(request):
    """Detect whether the request is a CREATE or UPDATE operation."""
    request_lower = request.lower()
    if any(kw in request_lower for kw in UPDATE_KEYWORDS):
        return 'UPDATE'
    if any(kw in request_lower for kw in CREATE_KEYWORDS):
        return 'CREATE'
    return 'CREATE'


def extract_target_file_path(request):
    """Extract the target Terraform file path from the request text."""
    for pattern in FILE_PATH_PATTERNS:
        match = re.search(pattern, request, re.IGNORECASE)
        if match:
            return match.group(1)
    return DEFAULT_TARGET_FILE


# --- Terraform file analysis ---

def summarize_terraform_file(content):
    """Create a concise summary of resources in a Terraform file."""
    resources = []
    resource_pattern = r'resource\s+"([^"]+)"\s+"([^"]+)"\s*{'
    matches = re.findall(resource_pattern, content)

    for resource_type, resource_name in matches:
        block_start = content.find(f'resource "{resource_type}" "{resource_name}"')
        if block_start == -1:
            continue

        # Extract key attributes from the first 500 chars of the block
        block_content = content[block_start:block_start + 500]
        attrs = {}
        for attr in SUMMARY_ATTRIBUTES:
            attr_match = re.search(rf'{attr}\s*=\s*"([^"]+)"', block_content)
            if attr_match:
                attrs[attr] = attr_match.group(1)

        resources.append({
            'type': resource_type,
            'name': resource_name,
            'attributes': attrs,
        })

    return {
        'resource_count': len(resources),
        'resources': resources[:MAX_RESOURCES_PER_FILE],
    }


def extract_terraform_blocks(content, target_resources=None):
    """Extract resource blocks from Terraform content, optionally filtered."""
    blocks = []
    resource_pattern = r'(resource\s+"[^"]+"\s+"[^"]+"\s*{[^}]*(?:{[^}]*}[^}]*)*})'

    for match in re.finditer(resource_pattern, content, re.DOTALL):
        block = match.group(1)
        if target_resources:
            block_lower = block.lower()
            if any(res in block_lower for res in target_resources):
                blocks.append(block)
        else:
            blocks.append(block)
    return blocks


# --- GitHub file operations ---

def get_relevant_terraform_files(relevant_resources):
    """Fetch and summarize relevant Terraform files from the GitHub repo."""
    try:
        files = _github_request('contents/generated')
        relevant_files = {}

        for file in files:
            if not file['name'].endswith('.tf'):
                continue
            filename = file['name'].lower()
            # Include files matching relevant resources or the main entry point
            if not (any(res in filename for res in relevant_resources) or filename == 'main.tf'):
                continue

            req = urllib.request.Request(
                file['download_url'],
                headers={'Authorization': f'token {GITHUB_TOKEN}'},
            )
            with _safe_urlopen(req) as response:
                content = response.read().decode()
                relevant_files[file['name']] = summarize_terraform_file(content)

        return relevant_files
    except (urllib.error.URLError, KeyError) as e:
        logger.warning('Failed to fetch Terraform files: %s', str(e))
        return {}


def get_relevant_blocks_for_update(file_path, target_resources):
    """Fetch a specific file from GitHub and extract relevant resource blocks."""
    try:
        file_info = _github_request(f'contents/{file_path}')
        content = base64.b64decode(file_info['content']).decode()
        relevant_blocks = extract_terraform_blocks(content, target_resources)

        return {
            'full_content': content,
            'relevant_blocks': relevant_blocks,
            'file_sha': file_info['sha'],
        }
    except (urllib.error.URLError, KeyError) as e:
        logger.warning('Failed to fetch file %s: %s', file_path, str(e))
        return None


# --- Code generation ---

def generate_terraform_code(request, context):
    """Generate Terraform code using Bedrock based on the request and context."""
    operation_type = detect_operation_type(request)
    relevant_resources = identify_relevant_resources(request)
    target_file = extract_target_file_path(request)
    file_sha = None

    # Build the prompt based on operation type
    if operation_type == 'UPDATE':
        file_data = get_relevant_blocks_for_update(target_file, relevant_resources)

        if file_data:
            blocks_context = '\n\nCurrent relevant blocks to update:\n'
            for i, block in enumerate(file_data['relevant_blocks'][:MAX_BLOCKS_FOR_UPDATE]):
                blocks_context += f'\n--- Block {i + 1} ---\n{block}\n'

            prompt = (
                f'Update the following Terraform code: {request}\n\n'
                f'Target file: {target_file}\n'
                f'Use these tags: {json.dumps(context)}{blocks_context}\n\n'
                'Requirements:\n'
                '- Update ONLY the specific parts mentioned in the request\n'
                '- Preserve all other existing code\n'
                '- Maintain proper resource tagging\n'
                '- Use AWS best practices\n'
                '- Keep existing resource references\n\n'
                'Return the complete updated file content with only the requested changes.'
            )
            file_sha = file_data['file_sha']
        else:
            # File not found — fall back to CREATE
            operation_type = 'CREATE'

    if operation_type == 'CREATE':
        existing_context = get_relevant_terraform_files(relevant_resources)

        context_summary = ''
        if existing_context:
            context_summary = '\n\nExisting infrastructure summary:\n'
            for filename, summary in existing_context.items():
                context_summary += f"\n{filename}: {summary['resource_count']} resources\n"
                for resource in summary['resources']:
                    context_summary += f"  - {resource['type']}.{resource['name']}\n"

        prompt = (
            f'Generate Terraform code for: {request}\n\n'
            f'Target file: {target_file}\n'
            f'Use these tags: {json.dumps(context)}{context_summary}\n\n'
            'Requirements:\n'
            '- Include proper resource tagging\n'
            '- Use AWS best practices\n'
            '- Include security groups\n'
            '- Add monitoring\n'
            '- Reference existing resources when appropriate\n'
            '- Avoid duplicating existing infrastructure\n\n'
            'Return only valid Terraform HCL code.'
        )

    logger.info('Invoking Bedrock model %s for %s operation', BEDROCK_MODEL_ID, operation_type)

    response = bedrock.converse(
        modelId=BEDROCK_MODEL_ID,
        messages=[{'role': 'user', 'content': [{'text': prompt}]}],
        inferenceConfig={'maxTokens': BEDROCK_MAX_TOKENS},
    )

    result_text = response['output']['message']['content'][0]['text']
    return result_text, target_file, file_sha


# --- Pull request creation ---

def create_github_pr(terraform_code, target_file=DEFAULT_TARGET_FILE, existing_sha=None):
    """Create a GitHub branch, commit the generated code, and open a PR."""
    try:
        branch_name = f'terraform-{int(time.time())}'

        # Get main branch SHA
        main_ref = _github_request('git/refs/heads/main')
        main_sha = main_ref['object']['sha']

        # Create new branch (retry with suffix on conflict)
        try:
            _github_request(
                'git/refs',
                method='POST',
                data={'ref': f'refs/heads/{branch_name}', 'sha': main_sha},
            )
        except urllib.error.HTTPError as e:
            if e.code == 422:
                branch_name = f'{branch_name}-{hash(terraform_code) % 1000}'
                _github_request(
                    'git/refs',
                    method='POST',
                    data={'ref': f'refs/heads/{branch_name}', 'sha': main_sha},
                )
            else:
                raise

        # Resolve file SHA for updates (use provided or fetch from repo)
        file_sha = existing_sha
        if not file_sha:
            try:
                file_info = _github_request(f'contents/{target_file}')
                file_sha = file_info['sha']
            except urllib.error.HTTPError:
                pass  # File doesn't exist yet — will create new

        # Commit the generated Terraform file
        file_data = {
            'message': f'Add generated Terraform code to {target_file}',
            'content': base64.b64encode(terraform_code.encode()).decode(),
            'branch': branch_name,
        }
        if file_sha:
            file_data['sha'] = file_sha

        _github_request(f'contents/{target_file}', method='PUT', data=file_data)

        # Open pull request
        pr = _github_request('pulls', method='POST', data={
            'title': f'Generated Terraform Infrastructure - {branch_name}',
            'head': branch_name,
            'base': 'main',
            'body': 'Auto-generated Terraform code from AI infrastructure request',
        })

        logger.info('PR created: %s', pr['html_url'])
        return pr['html_url']

    except Exception as e:
        logger.error('PR creation failed: %s', str(e), exc_info=True)
        return f'PR creation failed: {str(e)}'
