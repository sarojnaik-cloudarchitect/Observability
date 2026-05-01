#!/bin/bash
# BebliTech — Assume Production Account Role
# Run: source ./scripts/assume-prod-role.sh

echo "Assuming beblitech-production account..."

CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::159622728101:role/OrganizationAccountAccessRole \
  --role-session-name beblitech-prod-session \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo $CREDS | awk '{print $3}')
export AWS_DEFAULT_REGION=us-east-1

echo "Production account active for 1 hour."
aws sts get-caller-identity --no-cli-pager
