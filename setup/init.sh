#!/usr/bin/env bash
set -euo pipefail

cluster_name="${EKS_CLUSTER_NAME:-cluster}"
region="${AWS_REGION:-us-east-1}"
user_name="github-action-user"

user_arn="$(aws iam get-user --user-name "$user_name" --query 'User.Arn' --output text)"
aws eks describe-access-entry \
  --cluster-name "$cluster_name" \
  --principal-arn "$user_arn" \
  --region "$region" >/dev/null

echo "GitHub Actions IAM user and EKS access entry are configured: $user_arn"
echo "AWS credential values must be stored only in encrypted GitHub Actions Secrets."
