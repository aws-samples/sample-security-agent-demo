"""
Test script for the AI Infrastructure Generator API.

Configure environment variables before running:
    export API_URL="https://<id>.execute-api.<region>.amazonaws.com/prod/generate"
    export API_KEY="<your-api-key>"
    python3 test_request.py
"""

import os
import sys
import json
import requests


API_URL = os.environ.get('API_URL', '')
API_KEY = os.environ.get('API_KEY', '')

# Sample requests to test different operations
SAMPLE_REQUESTS = {
    'create_vpc': {
        'request': 'create a new VPC with public and private subnets in file vpc/main.tf',
    },
    'update_tags': {
        'request': 'update tag CostCenter value to IT-OPS-003 for file ./generated/ec2/main.tf',
    },
    'create_ec2': {
        'request': 'create EC2 instance and associate existing EBS volume',
    },
}


def test_request(name, payload):
    """Send a test request to the API and print the response."""
    print(f'\n--- {name} ---')
    headers = {'Content-Type': 'application/json', 'x-api-key': API_KEY}

    try:
        response = requests.post(API_URL, json=payload, headers=headers)

        if response.status_code == 200:
            result = response.json()
            print(f"Terraform Code:\n{result['terraform_code']}")
            print(f"\nPR URL: {result['pr_url']}")
        else:
            print(f'Error: {response.status_code}')
            print(response.text)
    except Exception as e:
        print(f'Request failed: {e}')


def main():
    if not API_URL:
        print('Error: API_URL environment variable is not set.')
        print('Usage:')
        print('  export API_URL="https://<id>.execute-api.<region>.amazonaws.com/prod/generate"')
        print('  export API_KEY="<your-api-key>"')
        sys.exit(1)

    if not API_KEY:
        print('Error: API_KEY environment variable is not set.')
        print('Usage: export API_KEY=$(cd terraform && terraform output -raw api_key)')
        sys.exit(1)

    # Run a single request by name, or default to update_tags
    request_name = sys.argv[1] if len(sys.argv) > 1 else 'update_tags'

    if request_name == 'all':
        for name, payload in SAMPLE_REQUESTS.items():
            test_request(name, payload)
    elif request_name in SAMPLE_REQUESTS:
        test_request(request_name, SAMPLE_REQUESTS[request_name])
    else:
        print(f'Unknown request: {request_name}')
        print(f'Available: {", ".join(SAMPLE_REQUESTS.keys())}, all')
        sys.exit(1)


if __name__ == '__main__':
    main()
