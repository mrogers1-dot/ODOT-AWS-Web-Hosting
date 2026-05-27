# Tech Stack

## Cloud Provider
- **AWS** — primary cloud platform

## Infrastructure as Code
- **AWS CloudFormation** and/or **AWS CDK** (TypeScript or Python) for resource provisioning
- **Terraform** may also be used depending on project preference

## Common AWS Services
- **S3** — static site hosting / asset storage
- **CloudFront** — CDN and HTTPS termination
- **Route 53** — DNS management
- **ACM** — SSL/TLS certificate management
- **EC2 / ECS / Lambda** — compute (depending on hosting model)
- **IAM** — access control and roles
- **CodePipeline / CodeBuild / GitHub Actions** — CI/CD

## Package Management
- **npm** or **yarn** (if CDK/TypeScript is used)
- **pip** (if CDK/Python or scripts are used)

## Common Commands

### AWS CDK
```bash
npm install          # Install dependencies
cdk bootstrap        # Bootstrap CDK environment (first-time setup)
cdk synth            # Synthesize CloudFormation templates
cdk diff             # Preview changes before deploying
cdk deploy           # Deploy stack to AWS
cdk destroy          # Tear down stack
```

### Terraform (if applicable)
```bash
terraform init       # Initialize working directory
terraform plan       # Preview changes
terraform apply      # Apply changes
terraform destroy    # Tear down infrastructure
```

### AWS CLI
```bash
aws s3 sync ./dist s3://bucket-name   # Sync build output to S3
aws cloudfront create-invalidation    # Invalidate CloudFront cache
```

## Environment Configuration
- Environment-specific config lives in separate files or CDK context (e.g., `cdk.context.json`, `.env.dev`, `.env.prod`)
- Secrets are managed via **AWS Secrets Manager** or **SSM Parameter Store** — never hardcoded
