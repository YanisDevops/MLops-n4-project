#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-mlops-n4-predictor}"

command -v aws >/dev/null 2>&1 || { echo "Erreur: aws est requis." >&2; exit 1; }

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
EXPECTED_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

if REPOSITORY_URI="$(aws ecr describe-repositories --region "$AWS_REGION" \
  --repository-names "$ECR_REPOSITORY" \
  --query 'repositories[0].repositoryUri' --output text 2>/dev/null)"; then
  echo "Repository ECR déjà présent : $REPOSITORY_URI"
else
  echo "Création du repository ECR : $ECR_REPOSITORY"
  REPOSITORY_URI="$(aws ecr create-repository --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --query 'repository.repositoryUri' --output text)"
fi

[[ "$REPOSITORY_URI" == "$EXPECTED_URI" ]] || {
  echo "Erreur: URI ECR inattendue : $REPOSITORY_URI" >&2
  exit 1
}

echo "IMAGE_REPOSITORY=$REPOSITORY_URI"
