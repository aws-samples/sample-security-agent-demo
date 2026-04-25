# Testing & Verification Guide

This guide walks through end-to-end verification of all three demos in this repository. Follow it before a live demo to confirm everything works in your AWS account, or use it as a reference for what "good" looks like.

## Contents

- [Scope](#scope)
- [Before You Start](#before-you-start)
- [Test T1: Demo 1 - Design Review](#test-t1-demo-1---design-review)
- [Test T2: Demo 2 - AI Infrastructure Generator](#test-t2-demo-2---ai-infrastructure-generator)
- [Test T3: Demo 3 - Penetration Testing](#test-t3-demo-3---penetration-testing)
- [Test Report Template](#test-report-template)

## Scope

Every demo has two kinds of steps:

| Kind | What it means | Who runs it |
|------|---------------|-------------|
| **Automatable** | Terraform apply, `curl`, `python3 test_request.py`, `aws` CLI. Produces terminal output you can paste into a report. | You (or CI) |
| **Console-driven** | AWS Security Agent UI actions (create design review, enable pen test, review findings). | You (manual, with screenshots) |

This guide structures each test so you can confirm the automatable parts pass on their own **before** spending time on the console parts.

## Before You Start

Confirm the baseline prerequisites from the [root README](README.md#prerequisites):

```bash
# Required tools
aws --version                    # v2.x
terraform version                # v1.0+
python3 --version                # 3.12+

# Identity
aws sts get-caller-identity      # Should print your account + role
```

For Demo 3 specifically, decide **before you apply** whether you will use a Route 53 hosted zone or the raw ALB DNS name. This determines your test target format and affects the domain verification step in the Security Agent console. See the [domain paths section](README.md#demo-3-variables) in the root README.

---

## Test T1: Demo 1 - Design Review

**Goal:** AWS Security Agent ingests the demo's design documents and produces findings that match the expected breakdown.

**Automatable portion:** File validation only. Everything else is console-driven.

### T1.1 - Input files exist and are well-formed (automatable)

```bash
# From repo root
ls -la design-review/aws-security-agent-demo.md
ls -la design-review/vulnerable-architecture-before-review.png

# Quick-check the markdown
wc -l design-review/aws-security-agent-demo.md   # expect >100 lines
head -5 design-review/aws-security-agent-demo.md
```

**Pass criteria:**
- Both files exist
- Markdown has content (not a stub)
- PNG is a valid image (`file design-review/vulnerable-architecture-before-review.png` reports PNG)

### T1.2 - Enable security requirements in Security Agent (console)

Follow [Demo 1 Step 1](README.md#step-1-enable-security-requirements-aws-console) in the root README.

**Pass criteria:** At least the 9 managed requirements listed are enabled in your Agent Space. Screenshot the **Security requirements** page showing each as Enabled.

### T1.3 - Create and run the design review (console)

Follow [Demo 1 Steps 2-4](README.md#step-2-create-a-design-review-web-application). Upload `aws-security-agent-demo.md` and `vulnerable-architecture-before-review.png`.

**Pass criteria:** Review completes (no errors). Screenshot the completion status.

### T1.4 - Validate findings match expected (console)

Compare against the table in [Demo 1 Step 5](README.md#step-5-review-findings).

**Pass criteria:**

| Severity | Expected count |
|----------|---------------|
| Critical | 6 |
| High     | 3 |
| Medium   | 1 |

Some variance is acceptable (±1 per severity) — the agent evolves. Screenshot the findings summary and attach to your test report.

---

## Test T2: Demo 2 - AI Infrastructure Generator

**Goal:** Lambda generates Terraform via Bedrock and creates a GitHub pull request. AWS Security Agent then reviews that PR and flags issues.

### T2.1 - Deploy (automatable)

```bash
cd github-review/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set github_token, github_owner, github_repo

# Build the Lambda package
zip -j lambda_function.zip ../lambda_function.py

terraform init
terraform apply -auto-approve
```

**Pass criteria:**
- `terraform apply` finishes with "Apply complete!"
- `terraform output -raw api_gateway_url` prints a URL
- `terraform output -raw api_key` prints a value

### T2.2 - Upload organizational context (automatable)

```bash
cd github-review/terraform
aws s3 cp ../it-operations-tags.json s3://$(terraform output -raw s3_bucket_name)/it-operations-tags.json
```

**Pass criteria:** `aws s3 ls s3://$(terraform output -raw s3_bucket_name)/` lists `it-operations-tags.json`.

### T2.3 - Generate a Terraform file via the API (automatable)

```bash
cd github-review
export API_URL=$(cd terraform && terraform output -raw api_gateway_url)
export API_KEY=$(cd terraform && terraform output -raw api_key)

python3 test_request.py create_vpc
```

**Pass criteria:**
- HTTP 200 response
- Response JSON contains non-empty `terraform_code` and a `pr_url` pointing at `github.com/<owner>/<repo>/pull/<N>`
- Opening the PR in GitHub shows a `generated/main.tf` (or similarly-named) file with Terraform content

Capture the response JSON and the PR URL for your test report.

### T2.4 - Exercise the other test cases (automatable, optional)

```bash
python3 test_request.py update_tags
python3 test_request.py create_ec2
```

**Pass criteria:** Each call returns HTTP 200 and creates a new PR.

### T2.5 - Run AWS Security Agent code review on the PR (console)

1. Set up the GitHub integration in Security Agent per [Demo 2 Step 7](README.md#step-7-run-aws-security-agent-code-review)
2. Wait for the agent to scan the PR created in T2.3

**Pass criteria:** The agent posts comments on the PR flagging at least one of: missing encryption, overly permissive IAM, unrestricted security group, missing logging, non-compliant tagging. Screenshot the PR conversation showing the agent comments.

### T2.6 - Cleanup (automatable)

```bash
cd github-review/terraform
terraform destroy -auto-approve
rm lambda_function.zip
```

**Pass criteria:** Destroy finishes with "Destroy complete!". No resources remain when you check the AWS console.

---

## Test T3: Demo 3 - Penetration Testing

**Goal:** Deploy the vulnerable Flask app and confirm the intentional vulnerabilities are reachable. AWS Security Agent then runs a pen test and finds them.

### T3.1 - Pick your domain path (decision point)

**Path A - Route 53 hosted zone:** You own `yourdomain.com` in this AWS account.
- Target will be `pentest.yourdomain.com`
- Set `domain_name = "yourdomain.com"` in `terraform.tfvars`
- Domain verification in Security Agent is one-click

**Path B - No Route 53 hosted zone:** You don't own a hosted zone in this account (or don't want to use it).
- Target will be the raw ALB DNS name (e.g., `aws-security-agent-pentest-alb-123.us-east-1.elb.amazonaws.com`)
- Leave `domain_name = ""` (or omit it entirely)
- Domain verification in Security Agent uses a DNS TXT record at your provider, or HTTP route verification

> **Important:** This guide's automatable tests work identically for both paths. All `curl` commands below use a `TARGET` variable that you set based on the path you chose.

### T3.2 - Deploy (automatable)

```bash
cd pen-test/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set db_password (required)
# Optionally set domain_name if on Path A

terraform init
terraform apply -auto-approve
```

**Pass criteria:** `terraform apply` finishes with 28 resources created in ~8 minutes. `terraform output setup_instructions` prints the target URL.

### T3.3 - Wait for user-data to finish (automatable)

The Flask app takes an additional 5-10 minutes after `terraform apply` to install. Poll until it responds:

```bash
# Path A
export TARGET="pentest.$(terraform output -raw domain_name 2>/dev/null || echo '<your-domain>')"

# Path B
export TARGET="$(terraform output -raw alb_dns_name)"

# Poll up to 10 minutes
for i in $(seq 1 20); do
  code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://$TARGET/" || echo "000")
  echo "attempt $i: HTTP $code"
  [ "$code" = "200" ] && break
  sleep 30
done
```

**Pass criteria:** One of the attempts returns HTTP 200.

### T3.4 - Confirm each intentional vulnerability is reachable (automatable)

> **Shell quoting note:** the SQL injection payload contains single quotes. Use `curl -G --data-urlencode` as shown so bash doesn't eat the quotes before curl sees them. Inline `"q=' OR '1'='1"` in the URL will silently return an empty body.

```bash
# 1. SQL Injection — classic boolean-based on the search endpoint
curl -sG "http://$TARGET/search" --data-urlencode "q=' OR '1'='1"

# 2. IDOR — incrementing the token ID exposes another user's profile
curl -s "http://$TARGET/profile?token=1"
curl -s "http://$TARGET/profile?token=2"

# 3. Unauthenticated API — should dump all users, no auth required
curl -s "http://$TARGET/api/users"

# 4. Reflected XSS — the `q` parameter is echoed back unescaped
curl -sG "http://$TARGET/search" --data-urlencode "q=<script>alert(1)</script>"
```

**Pass criteria:**
- `/search?q=' OR '1'='1` returns results (not an error page)
- `/profile?token=1` and `/profile?token=2` return different user data
- `/api/users` returns JSON with user records
- `/search?q=<script>...` returns HTML with the `<script>` tag included in the response body

Capture each response into your test report — this is proof the vulnerabilities are exploitable, which is exactly what the Security Agent should detect.

### T3.5 - Confirm infrastructure-level vulnerabilities exist (automatable, spot check)

```bash
# Unencrypted RDS
aws rds describe-db-instances \
  --db-instance-identifier aws-security-agent-pentest-vulnerable-db \
  --query 'DBInstances[0].StorageEncrypted'
# Expected: false

# Unencrypted S3 with no default encryption
aws s3api get-bucket-encryption --bucket $(terraform output -raw s3_bucket_name) 2>&1 || echo "no default encryption (expected)"

# Overly permissive IAM
aws iam get-role-policy \
  --role-name aws-security-agent-pentest-ec2-role \
  --policy-name aws-security-agent-pentest-vulnerable-policy \
  --query 'PolicyDocument.Statement[0].Action'
# Expected: includes "s3:*", "rds:*", "ec2:*"
```

**Pass criteria:** Each command's output confirms the intentional misconfiguration.

### T3.6 - Run AWS Security Agent pen test (console)

Follow [Demo 3 Steps 4-6](README.md#step-4-enable-penetration-testing-aws-console) in the root README.

> **Heads-up on Path B:** in the Security Agent console's **Target domains** field, the ALB DNS name is *not* pre-populated — the agent does not auto-discover ALBs. Type the full ALB DNS name into the field, then use **HTTP_ROUTE** verification (not one-click DNS_TXT, which requires a domain you control at a registrar the agent can talk to).

**Pass criteria:** Pen test completes (can take several hours). Findings match the expected table:

| Severity | Expected findings |
|----------|-------------------|
| Critical | SQL Injection, hardcoded credentials, SSRF, insecure deserialization |
| High     | XSS, IDOR, path traversal, unencrypted storage |
| Medium   | Weak session management, verbose errors, missing security headers, debug mode |

Screenshot the findings summary and attach to your test report.

### T3.7 - Cleanup (automatable)

```bash
cd pen-test/terraform
terraform destroy -auto-approve
```

**Pass criteria:** Destroy finishes with "Destroy complete!". If you used Path A, also confirm the `pentest.<your-domain>` Route 53 record is gone.

---

## Test Report Template

Copy this into a new file (e.g., `test-report-YYYY-MM-DD.md`) and fill in the blanks after each test.

```markdown
# Test Report — AWS Security Agent Demo Suite

- **Date:**
- **Tester:**
- **AWS account:**
- **Region:**
- **Commit SHA:** `git rev-parse HEAD`

## T1 — Design Review

- [ ] T1.1 File validation
- [ ] T1.2 Requirements enabled  _(screenshot)_
- [ ] T1.3 Review completes  _(screenshot)_
- [ ] T1.4 Findings match expected  _(screenshot, paste counts)_

Notes:

## T2 — AI Infrastructure Generator

- [ ] T2.1 Terraform apply succeeds
- [ ] T2.2 Context uploaded
- [ ] T2.3 API returns PR URL  _(paste URL)_
- [ ] T2.4 Other test cases pass  _(optional)_
- [ ] T2.5 Security Agent flags PR  _(screenshot)_
- [ ] T2.6 Teardown clean

Notes:

## T3 — Penetration Testing

- **Path chosen:** A (Route 53) / B (ALB DNS)
- **TARGET used:**
- [ ] T3.2 Terraform apply succeeds (28 resources)
- [ ] T3.3 App responds with HTTP 200
- [ ] T3.4 Each vulnerability reachable  _(paste response snippets)_
- [ ] T3.5 Infra misconfigurations confirmed
- [ ] T3.6 Security Agent pen test findings match  _(screenshot)_
- [ ] T3.7 Teardown clean

Notes:
```
