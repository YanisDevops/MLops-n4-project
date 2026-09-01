#!/usr/bin/env bash
set -euo pipefail
SCOPE="${1:-workloads}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-n4}"
[[ "$SCOPE" == workloads ]] || { echo "Usage: $0 workloads" >&2; exit 1; }
for command in aws kubectl; do
  command -v "$command" >/dev/null 2>&1 || { echo "Erreur: $command est requis." >&2; exit 1; }
done

if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "Cluster déjà absent : aucun workload à supprimer."
  exit 0
fi

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
echo "Suppression des workloads du projet; le cluster, les volumes EBS et S3 sont conservés."
kubectl delete namespace ml-serving monitoring kserve mlops-platform --ignore-not-found
