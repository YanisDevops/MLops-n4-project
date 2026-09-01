#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-n4}"
: "${MLFLOW_BUCKET:?Définir MLFLOW_BUCKET}"
POLICY_NAME="${POLICY_NAME:-mlops-n4-mlflow-s3}"
ROLE_NAME="${ROLE_NAME:-mlops-n4-mlflow}"
NAMESPACE="${NAMESPACE:-mlops-platform}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-mlflow}"

for command in aws eksctl kubectl sed; do
  command -v "$command" >/dev/null 2>&1 || { echo "Erreur: $command est requis." >&2; exit 1; }
done

CALLER_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ -n "${AWS_ACCOUNT_ID:-}" && "$AWS_ACCOUNT_ID" != "$CALLER_ACCOUNT_ID" ]]; then
  echo "Avertissement: AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID ne correspond pas au compte authentifié $CALLER_ACCOUNT_ID." >&2
  echo "Le compte retourné par AWS STS sera utilisé." >&2
fi
AWS_ACCOUNT_ID="$CALLER_ACCOUNT_ID"
ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME"
POLICY_FILE="$(mktemp)"
trap 'rm -f "$POLICY_FILE"' EXIT
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
sed "s/MLFLOW_BUCKET_PLACEHOLDER/$MLFLOW_BUCKET/g" "$ROOT_DIR/infra/iam/policies/mlflow-s3-policy.json" > "$POLICY_FILE"

POLICY_ARN="$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='$POLICY_NAME'].Arn | [0]" --output text)"
if [[ -z "$POLICY_ARN" || "$POLICY_ARN" == "None" ]]; then
  echo "Création de la policy IAM $POLICY_NAME..."
  POLICY_ARN="$(aws iam create-policy --policy-name "$POLICY_NAME" \
    --policy-document "file://$POLICY_FILE" --query 'Policy.Arn' --output text)"
else
  echo "Policy IAM déjà présente : $POLICY_ARN"
fi

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"
  echo "Rôle IAM déjà présent : $ROLE_ARN"

  if ! aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
    --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyArn" --output text | grep -qx "$POLICY_ARN"; then
    echo "Association de la policy existante au rôle..."
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
  else
    echo "Policy déjà associée au rôle."
  fi

  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Erreur: le namespace $NAMESPACE n'existe pas. Exécuter d'abord la phase namespaces." >&2
    exit 1
  fi

  if ! kubectl -n "$NAMESPACE" get serviceaccount "$SERVICE_ACCOUNT" >/dev/null 2>&1; then
    kubectl -n "$NAMESPACE" create serviceaccount "$SERVICE_ACCOUNT"
  else
    echo "ServiceAccount déjà présent : $NAMESPACE/$SERVICE_ACCOUNT"
  fi

  kubectl -n "$NAMESPACE" annotate serviceaccount "$SERVICE_ACCOUNT" \
    eks.amazonaws.com/role-arn="$ROLE_ARN" --overwrite
else
  echo "Création du rôle IRSA et du ServiceAccount..."
  eksctl create iamserviceaccount --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
    --namespace "$NAMESPACE" --name "$SERVICE_ACCOUNT" --role-name "$ROLE_NAME" \
    --attach-policy-arn "$POLICY_ARN" --approve --override-existing-serviceaccounts
fi

echo "IRSA prêt : $NAMESPACE/$SERVICE_ACCOUNT -> $ROLE_ARN"
