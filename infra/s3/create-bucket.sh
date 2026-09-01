#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
: "${MLFLOW_BUCKET:?Définir MLFLOW_BUCKET avec un nom S3 globalement unique}"
command -v aws >/dev/null 2>&1 || { echo "Erreur: aws est requis." >&2; exit 1; }

EXISTING_BUCKET="$(aws s3api list-buckets --query "Buckets[?Name=='$MLFLOW_BUCKET'].Name | [0]" --output text)"
if [[ "$EXISTING_BUCKET" == "$MLFLOW_BUCKET" ]]; then
  echo "Bucket existant: $MLFLOW_BUCKET"
else
  echo "Création du bucket : $MLFLOW_BUCKET"
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$MLFLOW_BUCKET" --region "$AWS_REGION"
  else
    aws s3api create-bucket --bucket "$MLFLOW_BUCKET" --region "$AWS_REGION" \
      --create-bucket-configuration "LocationConstraint=$AWS_REGION"
  fi
fi

echo "Application de la configuration de sécurité S3..."
aws s3api put-public-access-block --bucket "$MLFLOW_BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$MLFLOW_BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$MLFLOW_BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
