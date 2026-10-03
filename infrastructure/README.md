# Workshop — Serverless Users Service

Terraform infrastructure for the Workshop Serverless Users Service.

Provisions AWS resources including Lambda functions, API Gateway, DynamoDB, and IAM roles for a serverless users API.

## Requirements

- Terraform >= 1.0.0
- AWS credentials configured for `us-west-2`

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Variables

| Name | Default | Description |
|------|---------|-------------|
| `region` | `us-west-2` | AWS region |
| `workshop_stack_base_name` | `workshop` | Base name for all resources |
| `environment` | `Workshop` | Environment tag value |
| `project` | `Serverless Patterns` | Project tag value |
