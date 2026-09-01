#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-mlops-n4-predictor}"
: "${IMAGE_TAG:?Définir IMAGE_TAG avec un tag immuable, par exemple le Git SHA}"

[[ "$IMAGE_TAG" != "latest" && "$IMAGE_TAG" != "replace-with-git-sha" ]] || {
  echo "Erreur: utiliser un IMAGE_TAG immuable; latest et replace-with-git-sha sont interdits." >&2
  exit 1
}

for command in aws docker; do
  command -v "$command" >/dev/null 2>&1 || { echo "Erreur: $command est requis." >&2; exit 1; }
done

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
RESOLVED_REPOSITORY="${ECR_REGISTRY}/${ECR_REPOSITORY}"
IMAGE_URI="${RESOLVED_REPOSITORY}:${IMAGE_TAG}"

if ! aws ecr describe-repositories --region "$AWS_REGION" \
  --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
  echo "Erreur: repository ECR absent. Exécuter d'abord ./scripts/deploy.sh ecr." >&2
  exit 1
fi

if [[ -n "${IMAGE_REPOSITORY:-}" && "$IMAGE_REPOSITORY" != "$RESOLVED_REPOSITORY" ]]; then
  echo "Avertissement: IMAGE_REPOSITORY=$IMAGE_REPOSITORY est ignoré." >&2
  echo "Utilisation du repository du compte AWS authentifié : $RESOLVED_REPOSITORY" >&2
fi

echo "Authentification Docker auprès de $ECR_REGISTRY..."
aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

if aws ecr describe-images --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" \
  --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Image déjà présente dans ECR : $IMAGE_URI"
  echo "Aucun build ni push nécessaire."
  exit 0
fi

echo "Construction de l'image : $IMAGE_URI"
docker build --pull -t "$IMAGE_URI" "$ROOT_DIR"
docker push "$IMAGE_URI"
echo "Image publiée : $IMAGE_URI"
