#!/usr/bin/env bash
set -euo pipefail

DESIRED="${1:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-n4}"
NODEGROUP_NAME="${NODEGROUP_NAME:-mlops-workers}"

[[ "$DESIRED" =~ ^[1-2]$ ]] || { echo "Usage: $0 <1|2>" >&2; exit 1; }
for command in aws eksctl; do
  command -v "$command" >/dev/null 2>&1 || { echo "Erreur: $command est requis." >&2; exit 1; }
done

CURRENT_DESIRED="$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP_NAME" --region "$AWS_REGION" \
  --query 'nodegroup.scalingConfig.desiredSize' --output text)"
if [[ "$CURRENT_DESIRED" == "$DESIRED" ]]; then
  echo "Node group déjà à la capacité souhaitée : $DESIRED"
  exit 0
fi

eksctl scale nodegroup --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
  --name "$NODEGROUP_NAME" --nodes "$DESIRED" --nodes-min 1 --nodes-max 2 --wait
