#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-n4}"

for command in aws eksctl; do
  command -v "$command" >/dev/null 2>&1 || { echo "Erreur: $command est requis." >&2; exit 1; }
done

if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Cluster EKS déjà absent : $CLUSTER_NAME"
  exit 0
fi

echo "Suppression du cluster $CLUSTER_NAME dans $AWS_REGION (le bucket S3 est conservé)."
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait
