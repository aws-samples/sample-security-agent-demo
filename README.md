# AWS Security Agent Demo Suite


## What is this Demo Suite?

This is a hands-on demo suite designed to showcase **AWS Security Agent** capabilities across three complementary scenarios: automated security design review, AI-powered infrastructure generation with security code review, and penetration testing against intentionally vulnerable infrastructure.

### How it Works

1. **Review** security vulnerability patterns and how the agent detects them (Design Review)
2. **Generate** Terraform infrastructure from natural language using Amazon Bedrock, then use AWS Security Agent to review the generated code for security issues via GitHub integration (AI Infra Generator - sample app)
3. **Deploy** an intentionally vulnerable web application and run penetration tests (Pen Test)
4. **Learn** how AWS Security Agent identifies vulnerabilities across 10 security domains

### What You'll Learn

- How AWS Security Agent detects vulnerabilities across 10 security domains
- How to use Amazon Bedrock to generate Terraform code from natural language (defaults to Claude Sonnet 4)
- How AWS Security Agent reviews AI-generated infrastructure code for security issues via GitHub pull requests
- How AWS Security Agent performs penetration testing against web applications
- Common security misconfigurations in AWS environments and how to remediate them

### Demo Flow

<img src="images/demo-flow.png" width="900" alt="Demo Suite Overview - Design Review, AI Infra Generator, and Penetration Testing">

---

> ⚠️ **Disclaimer:** This repository includes intentionally vulnerable infrastructure designed to demonstrate AWS Security Agent capabilities. **Do not deploy in production environments or store real data.**
>
> **Intentionally vulnerable directories:**
> - `pen-test/terraform/` — Deploys a Flask web app (`user_data.sh`) with OWASP Top 10 vulnerabilities (SQL injection, XSS, SSRF, insecure deserialization, path traversal, hardcoded credentials) and insecure AWS infrastructure (unencrypted S3, RDS, EBS; overly permissive IAM; HTTP-only ALB).
> - `design-review/` — Design documents (architecture diagram and design document) containing example vulnerable configurations as input for Security Agent design reviews. Not deployable.
> - `github-review/generated/` — Sample Terraform output from the AI generator. Not applied by the demo.
>
> **Production-quality directories:**
> - `github-review/terraform/` and `github-review/lambda_function.py` — The Demo 2 deployment infrastructure (Lambda, API Gateway, S3, IAM). No intentional vulnerabilities.
>
> Any AWS access keys in this repository (e.g., `AKIAIOSFODNN7EXAMPLE`) are [AWS documentation placeholder keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_identifiers.html), not real credentials.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture Overview](#architecture-overview)
- [Configuration Reference](#configuration-reference)
- [Demo 1: Design Review](#demo-1-design-review)
- [Demo 2: AI Infrastructure Generator](#demo-2-ai-infrastructure-generator)
- [Demo 3: Penetration Testing](#demo-3-penetration-testing)
- [Cost Estimate](#cost-estimate)
- [Cleanup](#cleanup)
- [Additional Resources](#additional-resources)

---

## Prerequisites

### Required Tools

Install these tools before deploying any demo:

| Tool | Version | Installation | Verify |
|------|---------|-------------|--------|
| AWS CLI | v2+ | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | `aws --version` |
| Terraform | v1.0+ | [Install Guide](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) | `terraform version` |
| Python | 3.12+ | [Install Guide](https://www.python.org/downloads/) | `python3 --version` |
| pip | Latest | Included with Python | `pip3 --version` |

### AWS Account Requirements

- An AWS account with permissions to create IAM roles, Lambda functions, API Gateway, S3 buckets, EC2 instances, RDS databases, VPCs, and ALBs
- AWS CLI configured with credentials:

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and default region (us-east-1)
```

- **AWS Security Agent access** (Demo 1 and Demo 3): You must have access to the [AWS Security Agent console](https://console.aws.amazon.com/securityagent/) and web application
- **Amazon Bedrock model access** (Demo 2 only): You must [enable model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access-modify.html) in the Bedrock console for the model you plan to use before deploying. This applies **only to the Demo 2 sample Lambda that generates Terraform code** — its default is **Anthropic Claude Sonnet 4**, and you can point it at any Bedrock-supported model by overriding the `bedrock_model_id` variable. This setting has no effect on AWS Security Agent itself; the model AWS Security Agent uses for design review, code review, and penetration testing is managed by the service and is not user-configurable.

### Demo-Specific Prerequisites

| Prerequisite | Demo 1 | Demo 2 | Demo 3 |
|-------------|--------|--------|--------|
| AWS Security Agent Agent Space | ✅ Required | — | ✅ Required |
| GitHub account with a repository | — | ✅ Required | — |
| GitHub personal access token | — | ✅ Required | — |
| Route 53 hosted zone | — | — | Optional |
| `requests` Python package | — | ✅ `pip install requests` | — |

<details>
<summary><b>GitHub Token Setup (Demo 2)</b></summary>

Create a [fine-grained personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token) with these permissions on your target repository:

- **Contents**: Read and **write** (branch + commit creation)
- **Pull requests**: Read and **write** (PR creation)
- **Metadata**: Read (auto-granted)

> **Important:** all three must be set to *Read and write* (not just Read). The Lambda will return `HTTP Error 403: Forbidden` on PR creation if **Pull requests: write** is missing, or on branch creation if **Contents: write** is missing.

The repository must already exist and have at least one commit on `main` (GitHub's "Add a README" option at creation time is the simplest way). Save the token securely — you will need it during Terraform deployment.

</details>

<details>
<summary><b>AWS Security Agent Setup (Demo 1 and Demo 3)</b></summary>

If you haven't set up AWS Security Agent yet:

1. Navigate to [AWS Security Agent](https://console.aws.amazon.com/securityagent/) in the AWS Console
2. Click **Set up AWS Security Agent**
3. Enter a name for your Agent Space (e.g., `security-agent-demo`)
4. Select **IAM-only access** under User access configuration
5. Click **Set up AWS Security Agent**

This creates your Agent Space and establishes the web application. For SSO access, see the [full setup guide](https://docs.aws.amazon.com/securityagent/latest/userguide/setup-security-agent.html).

</details>

---

## Architecture Overview

### AI Infrastructure Generator (Demo 2)

> Sample application for generating non-secure Terraform code to demonstrate AWS Security Agent code review.

<img src="images/demo2-architecture.png" width="700" alt="Demo 2 Architecture - AI Infrastructure Generator">

### Penetration Testing Environment (Demo 3)

<img src="images/demo3-architecture.png" width="700" alt="Demo 3 Architecture - Penetration Testing Environment">

### AWS Services Used

| Service | Demo | Purpose |
|---------|------|---------|
| Amazon Bedrock | Demo 2 | Terraform code generation by the Demo 2 sample Lambda (defaults to Claude Sonnet 4, configurable via `bedrock_model_id`). Not related to the model AWS Security Agent runs. |
| AWS Lambda | Demo 2 | Request processing and orchestration |
| Amazon API Gateway | Demo 2 | REST API endpoint |
| Amazon S3 | Demo 2, Demo 3 | Context storage, vulnerable bucket |
| Amazon EC2 | Demo 3 | Vulnerable web application host |
| Amazon RDS (MySQL) | Demo 3 | Application database |
| Application Load Balancer | Demo 3 | Public-facing entry point |
| Amazon VPC | Demo 3 | Network isolation |
| Amazon Route 53 | Demo 3 | DNS management (optional) |
| AWS IAM | All | Access management |

---

## Configuration Reference

Each demo uses Terraform variables for configuration. Variables marked **Required** have no default and must be provided by the user via `terraform.tfvars` or environment variables (`TF_VAR_<name>`).

### Demo 2 Variables

File: `github-review/terraform/terraform.tfvars`
(copy from `terraform.tfvars.example`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `github_token` | **Yes** | — | GitHub PAT with `Contents` and `Pull requests` write access |
| `github_owner` | **Yes** | — | GitHub username or organization |
| `github_repo` | **Yes** | — | Target repository name for generated PRs |
| `aws_region` | No | `us-east-1` | AWS region for deployment |
| `project_name` | No | `bedrock-infra-generator` | Prefix for all resource names |
| `bedrock_model_id` | No | `us.anthropic.claude-sonnet-4-20250514-v1:0` | Bedrock inference profile ID used **only by the Demo 2 sample Lambda** to generate Terraform. Does not change the model AWS Security Agent uses. |
| `context_key` | No | `it-operations-tags.json` | S3 key for the organizational tags file |

### Demo 3 Variables

File: `pen-test/terraform/terraform.tfvars`
(copy from `terraform.tfvars.example`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `db_password` | **Yes** | — | RDS admin password (min 8 characters) |
| `domain_name` | No | `""` (empty) | Route 53 hosted zone domain (e.g., `example.com`). Leave empty to skip DNS and use the raw ALB DNS name from the `alb_dns_name` output. |
| `aws_region` | No | `us-east-1` | AWS region for deployment |
| `project_name` | No | `aws-security-agent-pentest` | Prefix for all resource names |
| `instance_type` | No | `t3.micro` | EC2 instance type |
| `db_username` | No | `admin` | RDS admin username |

> **Two supported paths for the pen test target:**
>
> - **With a Route 53 hosted zone (you own `yourdomain.com` in this AWS account):** set `domain_name = "yourdomain.com"` and the Terraform will create `pentest.yourdomain.com` pointing to the ALB. AWS Security Agent verifies ownership with a single click.
> - **Without a Route 53 hosted zone:** leave `domain_name` empty (the default). Use the `alb_dns_name` output as your target. In the Security Agent console, choose DNS TXT verification and add the record at your DNS provider, or use HTTP route verification.

---

## Demo 1: Design Review

The design review demo showcases AWS Security Agent's automated vulnerability detection across **10 security domains** with **36 vulnerability scenarios**. You upload design documents to the Security Agent web application, and it analyzes them against enabled security requirements.

### Security Domains Covered

| Domain | Example Vulnerability |
|--------|----------------------|
| Audit Logging | CloudTrail disabled |
| Authentication | IAM user without MFA |
| Authorization | Wildcard IAM policies (`*:*`) |
| Information Protection | Unencrypted RDS |
| Log Protection | CloudWatch Logs without KMS |
| Privileged Access | Overly broad Lambda roles |
| Secret Protection | Hardcoded credentials in code |
| Secure by Default | Unrestricted security groups |
| Tenant Isolation | Missing tenant boundaries in DynamoDB |
| Custom Rules | Unencrypted log storage in S3 |

### Step 1: Enable Security Requirements (AWS Console)

Before running a design review, configure which security requirements the agent should evaluate against.

1. Navigate to [AWS Security Agent](https://console.aws.amazon.com/securityagent/) in the AWS Console
2. In the left sidebar, choose **Security requirements**
3. On the **Managed security requirements** tab, select the requirements you want to enable:
   - Audit Logging Best Practices
   - Authentication Best Practices
   - Authorization Best Practices
   - Information Protection Best Practices
   - Log Protection Best Practices
   - Privileged Access Best Practices
   - Secret Protection Best Practices
   - Secure by Default Best Practices
   - Tenant Isolation Best Practices
4. Click **Enable** to activate the selected requirements

> **Tip:** You can also create custom security requirements under the **Custom security requirements** tab. See the demo file for an example custom log protection requirement.

### Step 2: Create a Design Review (Web Application)

1. In the AWS Console, navigate to your Agent Space and click **Admin access** (or **Web app** tab) to open the Security Agent web application
2. In the left sidebar, click **Design reviews**
3. Click **Create Design Review**
4. Enter a name: `security-agent-demo-review`

### Step 3: Upload Design Files

Upload the design documents from this repository for the agent to analyze.

1. In the **Files to review** section, upload the following files from the `design-review/` folder:
   - `AnyBank Digital Portal Design Document.docx` — the vulnerability scenarios document
   - `AnyBank Digital Portal Architecture.png` — the architecture diagram
2. Supported formats: DOC, DOCX, JPEG, MD, PDF, PNG, TXT (max 5 files, 2MB each, 6MB total)

> **Tip:** For best results, include architecture diagrams and technical documentation that describe your system's security-relevant components and data flows.

### Step 4: Run the Design Review

1. Review the uploaded files to ensure accuracy
2. Click **Start design review**
3. Wait for the analysis to complete (typically a few minutes)

### Step 5: Review Findings

1. Once complete, the findings summary shows counts for each status: **Compliant**, **Non-compliant**, **Insufficient data**, and **Not applicable**
2. Filter by **Non-compliant** to see findings that need attention
3. Click on any finding to see:
   - The specific security requirement being evaluated
   - A detailed explanation of why the finding received its status
   - Recommended remediation guidance
4. Compare the agent's findings against the expected results in [`design-review/AnyBank Digital Portal Design Document.docx`](design-review/AnyBank%20Digital%20Portal%20Design%20Document.docx)

<img src="design-review/images/review-output.png" width="700" alt="AWS Security Agent design review findings summary">

### Expected Results

The agent should detect vulnerabilities across all 10 security domains:

| Severity | Expected Count |
|----------|---------------|
| Critical | 6 (authorization, audit logging, information protection, secrets, secure defaults, tenant isolation) |
| High | 3 (authentication, privileged access, custom log test) |
| Medium | 1 (log protection) |

---

## Demo 2: AI Infrastructure Generator

> ⚠️ **Important:** This demo is a sample application designed to generate Terraform code that is **intentionally not security-hardened**. The purpose is to produce pull requests with infrastructure code that AWS Security Agent can then review and flag for security issues. **Do not use the generated Terraform code in production** — it is meant to showcase the Security Agent's GitHub code review capabilities, not to serve as a reference for secure infrastructure.

An AI-powered system that converts natural language infrastructure requests into Terraform code and creates GitHub pull requests automatically using Amazon Bedrock. Once the PRs are created, you use **AWS Security Agent's code review feature** to scan the generated code for security misconfigurations — demonstrating how the agent catches issues in AI-generated infrastructure code.

### Step 1: Enable Bedrock Model Access (AWS Console)

Enable access for the model the **Demo 2 sample Lambda** will use to generate Terraform. The default is **Anthropic Claude Sonnet 4**, but you can point the Lambda at any Bedrock-supported model by setting the `bedrock_model_id` variable in your `terraform.tfvars`. This variable configures only this sample Lambda — it does not affect the model AWS Security Agent uses for its reviews.

1. Navigate to [Amazon Bedrock](https://console.aws.amazon.com/bedrock/) in the AWS Console
2. In the left sidebar, click **Model access**
3. Click **Modify model access**
4. Find your chosen model (e.g., **Anthropic** → **Claude Sonnet 4**) and check the box
5. Click **Next** → **Submit**
6. Wait for the access status to show **Access granted**

### Step 2: Configure Terraform Variables

Navigate to the Terraform directory and create your `terraform.tfvars` from the example file:

```bash
cd github-review/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your GitHub details (see [Configuration Reference](#demo-2-variables)):

```hcl
github_token = "github_pat_..."
github_owner = "your-username"
github_repo  = "your-repo"
```

### Step 3: Deploy Infrastructure

```bash
# From github-review/terraform/

# Create the Lambda deployment package
zip -j lambda_function.zip ../lambda_function.py

# Deploy infrastructure (~1 minute)
terraform init
terraform plan
terraform apply
```

The deployment creates:
1. ✅ API Gateway REST endpoint
2. ✅ Lambda function with Bedrock access
3. ✅ S3 bucket for organizational context
4. ✅ IAM roles with least-privilege permissions

### Step 4: Upload Context to S3

Upload the organizational tags file that Bedrock uses to tag generated infrastructure:

```bash
# From github-review/terraform/
aws s3 cp ../it-operations-tags.json s3://$(terraform output -raw s3_bucket_name)/it-operations-tags.json
```

> **Note:** This file contains organizational metadata (environment, cost center, compliance requirements, business unit, etc.) that Bedrock injects into every generated Terraform resource as tags. Without it, the Lambda still works but generated code won't include your org's tagging standards. You can customize `it-operations-tags.json` to match your own organization's tagging policy.

### Step 5: Test the API

```bash
# From github-review/terraform/
cd ..
export API_URL=$(cd terraform && terraform output -raw api_gateway_url)
export API_KEY=$(cd terraform && terraform output -raw api_key)

# Run a single test (from github-review/)
python3 test_request.py update_tags

# Run all test cases
python3 test_request.py all
```

Available test cases:

| Name | Request |
|------|---------|
| `create_vpc` | Create a new VPC with public and private subnets |
| `update_tags` | Update CostCenter tag on an EC2 file |
| `create_ec2` | Create EC2 instance with EBS volume |

### Step 6: Verify

A successful response looks like:

```json
{
  "terraform_code": "resource \"aws_vpc\" \"main\" { ... }",
  "pr_url": "https://github.com/your-user/your-repo/pull/1",
  "status": "success"
}
```

Check your GitHub repository for the new pull request with the generated Terraform code.

### Step 7: Run AWS Security Agent Code Review

This is the key part of the demo — use AWS Security Agent to review the generated pull requests for security issues.

1. Navigate to [AWS Security Agent](https://console.aws.amazon.com/securityagent/) in the AWS Console
2. Set up the **GitHub integration** by connecting your repository (see [Code Review Guide](https://docs.aws.amazon.com/securityagent/latest/userguide/code-review.html))
3. AWS Security Agent will automatically review new pull requests and flag security findings such as:
   - Missing encryption configurations
   - Overly permissive IAM policies
   - Unrestricted security group rules
   - Missing logging and monitoring
   - Non-compliant tagging
4. Review the agent's comments directly on the GitHub pull request

<img src="github-review/diagrams/security-agent-output.png" width="700" alt="AWS Security Agent code review findings on a GitHub pull request">

> **Tip:** Try generating multiple types of infrastructure (VPC, EC2, RDS) to see the range of security findings the agent can detect in AI-generated code.

For full details on the Lambda function flow, see [`github-review/README.md`](github-review/README.md).

---

## Demo 3: Penetration Testing

Deploys an intentionally vulnerable web application and runs AWS Security Agent penetration testing against it.

<details>
<summary><b>✅ Verified run notes & gotchas (tested end-to-end on macOS / Isengard, us-east-1)</b></summary>

These notes capture the exact path that worked, plus the errors encountered and how to get past them. Replace `<AWS_ACCOUNT_ID>`, `<ALB_DNS_NAME>`, and `<YOUR_ALIAS>` with your own values.

**Terraform install (Homebrew):** `brew install terraform` fails — the formula was removed from Homebrew core (`Error: No available formula with the name "terraform"`). Use the HashiCorp tap:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version   # e.g. Terraform v1.15.8 on darwin_arm64
```

> If the tap emits a `vagrant.rb` import warning, ignore it — `terraform` still installs and works.

**Credentials (Isengard via `ada`):** `terraform apply` fails with `InvalidClientTokenId` / `403` if credentials aren't set. Fetch them, then verify:

```bash
ada credentials update --account <AWS_ACCOUNT_ID> --role Admin --provider isengard
aws sts get-caller-identity
# Arn: arn:aws:sts::<AWS_ACCOUNT_ID>:assumed-role/Admin/<YOUR_ALIAS>-Isengard
```

> **Token expiry:** Isengard tokens expire (`ExpiredToken` error), commonly hit at `terraform destroy` time. Re-run `mwinit -o` and the `ada credentials update` command above, then retry.

**Observed deploy timing:** ~5.5 min total, `27 resources added`. RDS (`db.t3.micro`) is the long pole at ~5m19s; NAT Gateway ~1m45s; ALB ~3m24s.

**`curl` gotchas during manual testing:**
- Keep the whole `curl` command on **one line** — a wrapped line makes zsh throw `curl: (2) no URL specified` / `no such file or directory`.
- Don't paste example annotations (e.g. `then token=2`) onto the command line — zsh treats `then` as a hostname (`Could not resolve host: then`).
- The SQLi payload `?q=' OR '1'='1` can trip zsh/curl with `URL rejected: Malformed input to a URL function` — URL-encode it, or lead with the IDOR / API calls which are the most reliable live demos.

**During the pen test run:** the run is server-side (in AWS), so your laptop can sleep; it takes ~1–4 hours. A live scan opens many DB connections, so the small `db.t3.micro` may briefly return `pymysql OperationalError (1040, 'Too many connections')` — expected, not a failure.

</details>

<details>
<summary><b>What vulnerabilities are included?</b></summary>

**Application-Level:**
- SQL Injection (search and login endpoints)
- Cross-Site Scripting (XSS)
- Broken Authentication
- Broken Access Control (IDOR)
- Sensitive Data Exposure
- Insecure Deserialization
- SSRF (Server-Side Request Forgery)
- Path Traversal

**Infrastructure-Level (non-exploitable):**
- Unencrypted S3 bucket
- Unencrypted RDS storage
- Unencrypted EBS volumes
- Overly permissive IAM roles
- No backup configuration
- Missing CloudWatch logging

</details>

### Step 1: Configure Terraform Variables

Create your `terraform.tfvars` from the example file:

```bash
cd pen-test/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values, or set environment variables (see [Configuration Reference](#demo-3-variables)):

```bash
export TF_VAR_db_password="YourStrongPassword123!"

# Optional: only if you own a Route 53 hosted zone in this AWS account.
# Leave unset to use the raw ALB DNS name instead.
export TF_VAR_domain_name="yourdomain.com"
```

### Step 2: Deploy Infrastructure

```bash
cd pen-test/terraform
terraform init
terraform plan
terraform apply
```

**Deployment time:** ~8 minutes (RDS takes longest)

The deployment creates:
1. ✅ VPC with public and private subnets
2. ✅ EC2 instance running vulnerable Flask app (private subnet)
3. ✅ RDS MySQL database (unencrypted, no backups)
4. ✅ Application Load Balancer (public-facing)
5. ✅ S3 bucket (unencrypted)
6. ✅ Overly permissive IAM roles

### Step 3: Verify the Application

Wait 5–10 minutes after deployment for the application to initialize:

```bash
terraform output pentest_target_url
```

Open the URL in your browser. You should see the "⚠️ Vulnerable Demo Application" page with links to Search, Login, Profile, Upload, and API endpoints.

### Step 4: Enable Penetration Testing (AWS Console)

1. Navigate to [AWS Security Agent](https://console.aws.amazon.com/securityagent/) in the AWS Console
2. In the left sidebar, select **Agent Spaces**, then select your Agent Space
3. Click **Enable penetration test** in the header

#### Configure Domain

1. In the **Target domains** field, **type** the target. Nothing is pre-populated — AWS Security Agent does not auto-discover ALBs or Route 53 records.
   - **Path A (Route 53 hosted zone in this account):** type `pentest.<your-domain>` (e.g., `pentest.example.com`)
   - **Path B (ALB DNS name):** type the full ALB DNS name from `terraform output -raw alb_dns_name`, for example `aws-security-agent-pentest-alb-1234567890.us-east-1.elb.amazonaws.com`
2. Select verification method: **DNS_TXT** (recommended) or **HTTP_ROUTE**
3. Click **Next**

#### Verify Domain Ownership

- **Path A — Route 53 domains (same account):** the domain you typed will appear in the verification list. Select it and click **One-click verification** — AWS Security Agent creates the TXT record automatically.
- **Path B — ALB DNS name or external DNS providers:** AWS Security Agent cannot write TXT records to AWS-managed ALB DNS, so one-click verification is not available. You must either:
  - Use **HTTP_ROUTE** verification (recommended for ALB targets): the agent gives you a path + token, and verifies by fetching it over HTTP. This "just works" since the ALB is already reachable.
  - Or switch to **DNS_TXT** with a domain you control at any registrar and add the TXT record manually.
- Click **Next** after verification succeeds.

#### Configure Additional Capabilities (Optional)

- **VPC settings:** If testing the private EC2 instance directly, select the VPC and subnets from the Terraform deployment
- **CloudWatch logs:** Select or let the agent create a log group
- **Service access:** Use the default IAM role (recommended)
- Click **Save** to enable penetration testing

### Step 5: Run a Penetration Test (Web Application)

1. In the AWS Console, navigate to your Agent Space and click **Admin access** to open the web application
2. In the left sidebar, click **Penetration Test**
3. Click **Create your first penetration test**
4. Configure the test:
   - Select the verified domain as the target
   - Select the IAM role and log group
   - (Optional) Enable **automatic code remediation** to have the agent create PRs with fixes
5. Click **Next**
6. (Optional) If the app requires login, provide credentials in the **Agent Space login prompt**:
   - Username: `admin`, Password: `admin123` (from the demo app's sample data)
7. (Optional) Upload additional context files (e.g., the `design-review/AnyBank Digital Portal Design Document.docx`)
8. Click **Create and execute**

> **Note:** The penetration test can take up to several hours to complete. You can monitor progress in real-time on the test detail screen.

### Step 6: Review Findings

Once the penetration test completes:

1. Navigate to the penetration test detail screen
2. Review findings organized by severity

<img src="pen-test/images/pen-testing-output.png" width="700" alt="AWS Security Agent penetration testing findings">

### Expected Findings

| Severity | Expected Findings |
|----------|-------------------|
| **Critical** | SQL Injection in search and login endpoints, hardcoded credentials, SSRF, insecure deserialization |
| **High** | XSS in search, IDOR in profile access, path traversal in file upload, unencrypted storage |
| **Medium** | Weak session management, verbose error messages, missing security headers, debug mode enabled |

### Manual Testing (Optional)

You can also test vulnerabilities manually before running the Security Agent. Set `TARGET` to either `pentest.<your-domain>` (if you used Route 53) or the raw ALB DNS name:

```bash
export TARGET="$(cd pen-test/terraform && terraform output -raw alb_dns_name)"

# SQL Injection
curl "http://$TARGET/search?q=' OR '1'='1"

# IDOR - Access another user's profile
curl "http://$TARGET/profile?token=1"
curl "http://$TARGET/profile?token=2"

# Unauthenticated API - Exposes sensitive data
curl "http://$TARGET/api/users"
```

For full details, see [`pen-test/README.md`](pen-test/README.md).

---

## Cost Estimate

⚠️ **These demos deploy real AWS resources that incur costs.**

| Resource | Demo | Approximate Cost |
|----------|------|-----------------|
| NAT Gateway | Demo 3 | ~$32/month |
| ALB | Demo 3 | ~$16/month |
| RDS db.t3.micro | Demo 3 | ~$15/month |
| EC2 t3.micro | Demo 3 | ~$7/month |
| Lambda | Demo 2 | Pay per invocation |
| API Gateway | Demo 2 | Pay per request |
| S3 | Demo 2 | < $1/month |
| **Total (all running)** | | **~$70/month** |

**Recommendation:** Destroy infrastructure immediately after demos.

**Note:** The above values are indicative only, real values may differ based on usage.

---

## Cleanup

### Demo 2: AI Infrastructure Generator

```bash
cd github-review/terraform
terraform destroy
```

### Demo 3: Penetration Testing

```bash
cd pen-test/terraform
terraform destroy
```

> **Note:** Verify all resources are destroyed by checking the AWS Console. NAT Gateways and Elastic IPs may take a few minutes to release.

### AWS Security Agent (Console)

1. Navigate to [AWS Security Agent](https://console.aws.amazon.com/securityagent/) in the AWS Console
2. Delete any penetration test configurations
3. Optionally delete the Agent Space if no longer needed

---

## Additional Resources

| Resource | Link |
|----------|------|
| Testing & Verification Guide | [TESTING.md](TESTING.md) |
| AWS Security Agent Documentation | [User Guide](https://docs.aws.amazon.com/securityagent/latest/userguide/) |
| AWS Security Agent Setup | [Setup Guide](https://docs.aws.amazon.com/securityagent/latest/userguide/setup-security-agent.html) |
| Design Review Guide | [Create a Design Review](https://docs.aws.amazon.com/securityagent/latest/userguide/perform-design-review.html) |
| Penetration Testing Quickstart | [Quickstart Guide](https://docs.aws.amazon.com/securityagent/latest/userguide/quickstart.html) |
| Amazon Bedrock Documentation | [User Guide](https://docs.aws.amazon.com/bedrock/latest/userguide/) |
| Amazon Bedrock Model Access | [Enable Models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access-modify.html) |
| Terraform AWS Provider | [Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) |
| OWASP Top 10 | [Project Page](https://owasp.org/www-project-top-ten/) |

---

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
