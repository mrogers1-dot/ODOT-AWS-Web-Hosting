# Project Structure

## Top-Level Layout

```
AWS-WebHosting/
├── .kiro/                  # Kiro configuration and steering rules
│   └── steering/           # AI assistant guidance files
├── infra/                  # Infrastructure as Code (CDK, CloudFormation, or Terraform)
│   ├── stacks/             # CDK stacks or CloudFormation templates
│   ├── constructs/         # Reusable CDK constructs
│   └── config/             # Environment-specific configuration
├── src/                    # Application source code (if applicable)
├── scripts/                # Utility and deployment scripts
├── .github/                # GitHub Actions workflows (CI/CD)
│   └── workflows/
├── docs/                   # Architecture diagrams and documentation
├── cdk.json                # CDK app entry point and context (if using CDK)
├── package.json            # Node dependencies (if using CDK/TypeScript)
└── README.md
```

## Conventions

- **One stack per environment** — avoid mixing dev/staging/prod resources in a single stack
- **Constructs over inline code** — extract reusable AWS resource patterns into named constructs
- **No hardcoded values** — use CDK context, environment variables, or parameter store for all config
- **Tagging** — all AWS resources must include `Environment`, `Project`, and `Owner` tags
- **Least privilege IAM** — IAM roles and policies should grant only the permissions required

## Naming Conventions

- Stack names: `{Project}-{Environment}` (e.g., `WebHosting-Prod`)
- S3 buckets: `{project}-{purpose}-{environment}` (e.g., `webhosting-assets-dev`)
- CloudFormation exports: `{StackName}:{ResourceName}` (e.g., `WebHosting-Prod:BucketArn`)
- File names: kebab-case for scripts and config, PascalCase for CDK constructs/stacks

## Environment Separation

- Each environment (dev, staging, prod) deploys to its own AWS account or isolated namespace
- Environment-specific values are never committed as plaintext — use SSM or Secrets Manager
