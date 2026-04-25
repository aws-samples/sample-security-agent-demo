# AWS Security Agent - Penetration Testing Demo

## Overview

This demo deploys an intentionally vulnerable web application on AWS and uses AWS Security Agent to run an external penetration test against it. The infrastructure is configured with **safe defaults** for long-running demos (private EC2, private RDS, ALB-only ingress) while keeping application-level OWASP Top 10 vulnerabilities intact for the agent to find.

## Prerequisites

- AWS account with permission to create VPC, EC2, RDS, ALB, S3, IAM resources
- AWS CLI configured (`aws configure`)
- Terraform v1.0+
- Access to AWS Security Agent in your AWS account
- **Optional:** A Route 53 public hosted zone in the same AWS account if you want to use a custom `pentest.<your-domain>` subdomain. Without one, use the raw ALB DNS name (see below).

## Quick Start

### 1. Configure

```bash
cd pen-test/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set db_password (required)
# Optionally set domain_name if you have a Route 53 hosted zone
```

### 2. Deploy

```bash
terraform init
terraform apply
```

**Deployment time:** ~8 minutes (RDS takes longest). Wait a further 5-10 minutes after apply for the EC2 user-data script to install the Flask app.

### 3. Get Your Pen Test Target

Terraform outputs two candidates:

| Output | When to use |
|--------|-------------|
| `pentest_domain` | You set `domain_name`. Route 53 auto-verifies with one click in the Security Agent console. |
| `alb_dns_name` | You didn't set `domain_name`. The Security Agent console will ask you to add a DNS TXT record at your registrar to verify ownership. |

```bash
terraform output setup_instructions
```

### 4. Run the Pen Test

1. Open [AWS Security Agent](https://console.aws.amazon.com/securityagent/)
2. Enable penetration testing on your Agent Space
3. In the **Target domains** field, **type** the target (it's not pre-populated — the agent does not auto-discover ALBs). Paste `pentest.<your-domain>` (Path A) or the full ALB DNS name (Path B).
4. Complete verification:
   - **Path A:** one-click DNS_TXT verification (Route 53 in the same account)
   - **Path B:** use **HTTP_ROUTE** verification for an ALB DNS name — the agent fetches a token path over HTTP, no DNS write needed
5. Open **Admin Access** -> **Penetration Test** -> **Create**
6. Select the verified domain and click **Create and execute**

Full walkthrough including credentials and optional settings is in the top-level [README.md](../README.md#demo-3-penetration-testing).

### 5. Cleanup

```bash
terraform destroy
```

## Architecture

```
Internet → ALB (HTTP:80, public subnets) → EC2 (private subnet) → RDS (private subnet)
                                                                → S3
```

**Safe-for-long-running configuration:**
- EC2 is in a private subnet with no public IP
- RDS is not publicly accessible, only reachable from the web security group
- Only HTTP/80 is exposed, via the ALB
- NAT Gateway provides outbound internet for the private subnet

**Intentional application vulnerabilities (Flask app):**
- SQL Injection, XSS, Broken Authentication, IDOR, Sensitive Data Exposure, Insecure Deserialization, SSRF, Path Traversal

**Intentional infrastructure vulnerabilities (non-exploitable from outside):**
- Unencrypted S3 / RDS / EBS, overly permissive IAM roles, no backups, no logging

## Expected Findings

| Severity | Examples |
|----------|----------|
| Critical | SQL Injection, hardcoded credentials, SSRF, insecure deserialization |
| High     | XSS, IDOR, path traversal, unencrypted storage |
| Medium   | Weak session management, verbose errors, missing security headers, debug mode |

## Manual Smoke Testing (before running the agent)

Replace `<TARGET>` with `pentest.<your-domain>` or the ALB DNS name:

```bash
TARGET="<TARGET>"

# SQL Injection
curl "http://$TARGET/search?q=' OR '1'='1"

# IDOR
curl "http://$TARGET/profile?token=1"
curl "http://$TARGET/profile?token=2"

# Unauthenticated API
curl "http://$TARGET/api/users"
```

All three should return data that the agent will flag. See the root-level [TESTING.md](../TESTING.md) for the full verification procedure with pass/fail criteria.

## Cost

~$70/month if left running (NAT Gateway dominates). Destroy after demos.

## Troubleshooting

**App not responding after apply:** Wait 5-10 minutes for user-data to finish. Check target health:
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names aws-security-agent-pentest-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
```

**DNS not resolving:** `dig pentest.<your-domain>`. If you use GoDaddy/Namecheap/etc. with delegated nameservers, allow 5-30 minutes for propagation.

**Domain verification timing out in Security Agent:** Use the `alb_dns_name` output path with a TXT-record verification instead.

## Files

```
pen-test/
├── README.md                     # This file
└── terraform/
    ├── main.tf                   # VPC, EC2, RDS, ALB, S3, IAM, SGs
    ├── dns.tf                    # Optional Route 53 record (gated on domain_name)
    ├── variables.tf              # Configuration variables
    ├── outputs.tf                # Deployment outputs
    ├── user_data.sh              # EC2 bootstrap - installs Flask app
    └── terraform.tfvars.example  # Template for terraform.tfvars
```
