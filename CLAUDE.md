# Workshop — Serverless Users Service

## Project Overview
Serverless Users Service built with Terraform and Python on AWS.

## Directory Structure
- `infrastructure/` — Terraform configuration for all AWS resources
- `src/` — Python 3.10 Lambda function source code
- `tests/` — pytest test suites

## Infrastructure
- **IaC tool:** Terraform (not SAM or CDK)
- **AWS region:** us-west-2
- **Base name variable:** `workshop_stack_base_name` (value: `"workshop"`)
- All resources must be tagged:
  - `Name` — resource-specific name
  - `Environment` = `"Workshop"`
  - `Project` = `"Serverless Patterns"`

## Lambda Functions
- **Runtime:** Python 3.10
- **Source:** `src/` directory

## Testing
- **Framework:** pytest
- **AWS mocking:** moto
- **Location:** `tests/` directory

## IAM
Follow least-privilege principles — grant only the permissions each Lambda function or role strictly requires.
