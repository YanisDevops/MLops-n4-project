#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-n4}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/infra/eks/cluster.yaml}"

for command in aws eksctl kubectl; do
  command -v "$command" >/dev/null 2>&1 || { echo "Erreur: $command est requis." >&2; exit 1; }
done

if CLUSTER_STATUS="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query 'cluster.status' --output text 2>/dev/null)"; then
  echo "Cluster EKS déjà présent : $CLUSTER_NAME (statut: $CLUSTER_STATUS)"
  if [[ "$CLUSTER_STATUS" == "CREATING" || "$CLUSTER_STATUS" == "UPDATING" ]]; then
    echo "Attente du statut ACTIVE..."
    aws eks wait cluster-active --name "$CLUSTER_NAME" --region "$AWS_REGION"
  elif [[ "$CLUSTER_STATUS" != "ACTIVE" ]]; then
    echo "Erreur: le cluster existe mais son statut $CLUSTER_STATUS ne permet pas le déploiement." >&2
    exit 1
  fi
else
  echo "Création du cluster $CLUSTER_NAME dans $AWS_REGION depuis $CONFIG_FILE"
  echo "Note: le nom et la région de cluster.yaml doivent correspondre aux variables."
  eksctl create cluster -f "$CONFIG_FILE"
fi

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl get nodes -o wide
