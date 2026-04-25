output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer - use this as your pen test target domain"
  value       = aws_lb.vulnerable_alb.dns_name
}

output "database_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.vulnerable_db.endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Name of the vulnerable S3 bucket"
  value       = aws_s3_bucket.vulnerable_bucket.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.vulnerable_vpc.id
}

output "pentest_target_url" {
  description = "Full URL to use as pen test target"
  value       = "http://${aws_lb.vulnerable_alb.dns_name}"
}

output "setup_instructions" {
  description = "Next steps for AWS Security Agent setup"
  value       = <<-EOT
    
    ========================================
    AWS Security Agent Pen Test Setup
    ========================================
    
    ${var.domain_name != "" ? "Pen test target: http://pentest.${var.domain_name}" : "Pen test target: http://${aws_lb.vulnerable_alb.dns_name}"}
    
    1. Navigate to: https://us-east-1.console.aws.amazon.com/securityagent/
    
    2. Create Agent Space:
       - Name: vulnerable-app-pentest
       - Access: IAM-only
    
    3. Enable Penetration Testing:
       - Target Domain: ${var.domain_name != "" ? "pentest.${var.domain_name}" : aws_lb.vulnerable_alb.dns_name}
       - Validation: ${var.domain_name != "" ? "Automatic (Route 53 one-click)" : "Manual (add DNS TXT record at the domain registrar shown on-screen)"}
    
    4. Run Pen Test:
       - Access Web App -> Admin Access
       - Create Penetration Test
       - Target: ${var.domain_name != "" ? "http://pentest.${var.domain_name}" : "http://${aws_lb.vulnerable_alb.dns_name}"}
    
    5. Expected Findings:
       - SQL Injection, XSS, IDOR, SSRF, Path Traversal
       - Unencrypted storage, overly permissive IAM
       - Hardcoded credentials, verbose errors
    
    ========================================
    Application Access
    ========================================
    
    Web Application: ${var.domain_name != "" ? "http://pentest.${var.domain_name}" : "http://${aws_lb.vulnerable_alb.dns_name}"}
    ALB DNS Name:    ${aws_lb.vulnerable_alb.dns_name}
    Database:        ${aws_db_instance.vulnerable_db.endpoint}
    S3 Bucket:       ${aws_s3_bucket.vulnerable_bucket.id}
    
    WARNING: This infrastructure is intentionally vulnerable!
    Do not use in production or store real data.
    
    ========================================
  EOT
}
