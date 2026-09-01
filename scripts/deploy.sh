#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHASE="${1:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-mlops-n4}"
KSERVE_VERSION="${KSERVE_VERSION:-v0.14.1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-mlops-n4-predictor}"

banner() { printf '\n================================\nPHASE : %s\n================================\n' "${1^^}"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "Erreur: $1 est requis." >&2; exit 1; }; }
namespace_exists() { kubectl get namespace "$1" >/dev/null 2>&1; }
require_secret() { kubectl -n mlops-platform get secret postgres-secret >/dev/null 2>&1 || { echo "Erreur: créer postgres-secret (voir secret.example.yaml)." >&2; exit 1; }; }

cluster_ready() {
  need aws
  need kubectl
  local status context
  status="$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query 'cluster.status' --output text 2>/dev/null)" || {
      echo "Erreur: cluster EKS introuvable : $CLUSTER_NAME dans $AWS_REGION." >&2
      exit 1
    }
  [[ "$status" == "ACTIVE" ]] || {
    echo "Erreur: le cluster $CLUSTER_NAME n'est pas ACTIVE (statut: $status)." >&2
    exit 1
  }
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
  context="$(kubectl config current-context)"
  [[ "$context" == *":cluster/$CLUSTER_NAME" ]] || {
    echo "Erreur: contexte kubectl inattendu : $context" >&2
    exit 1
  }
  kubectl cluster-info >/dev/null
}

choose_phase() {
  printf '%s\n' \
    "================================" \
    "DÉPLOIEMENT MLOPS NIVEAU 4" \
    "================================" \
    "1. Namespaces" \
    "2. Stockage S3, IRSA et PVC" \
    "3. PostgreSQL" \
    "4. MLflow" \
    "5. KServe" \
    "6. Entraînement et enregistrement du modèle" \
    "7. Création du repository ECR" \
    "8. Build et push de l'image predictor" \
    "9. Serving du modèle" \
    "10. Monitoring Prometheus/Grafana (optionnel)" \
    "11. Toutes les phases obligatoires" \
    "0. Quitter"

  read -r -p "Numéro de la phase à exécuter : " selection
  case "$selection" in
    1) PHASE=namespaces ;;
    2) PHASE=storage ;;
    3) PHASE=postgres ;;
    4) PHASE=mlflow ;;
    5) PHASE=kserve ;;
    6) PHASE=model ;;
    7) PHASE=ecr ;;
    8) PHASE=image ;;
    9) PHASE=serving ;;
    10) PHASE=monitoring ;;
    11) PHASE=all ;;
    0) echo "Déploiement annulé."; exit 0 ;;
    *) echo "Erreur: numéro de phase invalide: $selection" >&2; exit 1 ;;
  esac
}

if [[ -z "$PHASE" ]]; then
  [[ -t 0 ]] || { echo "Erreur: mode non interactif; indiquer une phase en argument." >&2; exit 1; }
  choose_phase
fi

phase_namespaces() {
  banner namespaces; need kubectl; cluster_ready
  echo "Réconciliation des namespaces (les ressources existantes sont conservées et mises à jour)."
  kubectl apply -f "$ROOT_DIR/k8s/namespaces.yaml"
}

phase_storage() {
  banner storage; need aws; need kubectl; need eksctl; cluster_ready
  : "${MLFLOW_BUCKET:?Définir MLFLOW_BUCKET}"
  namespace_exists mlops-platform || phase_namespaces
  "$ROOT_DIR/infra/s3/create-bucket.sh"
  "$ROOT_DIR/infra/iam/scripts/create-mlflow-irsa.sh"
  kubectl apply -f "$ROOT_DIR/k8s/postgres/storageclass.yaml"
  kubectl apply -f "$ROOT_DIR/k8s/postgres/pvc.yaml"
}

phase_postgres() {
  banner postgres; need kubectl; cluster_ready
  namespace_exists mlops-platform || phase_namespaces
  require_secret
  kubectl apply -f "$ROOT_DIR/k8s/postgres/storageclass.yaml"
  kubectl apply -f "$ROOT_DIR/k8s/postgres/pvc.yaml"
  kubectl apply -f "$ROOT_DIR/k8s/postgres/service.yaml"
  kubectl apply -f "$ROOT_DIR/k8s/postgres/deployment.yaml"
  kubectl -n mlops-platform rollout status deployment/postgres --timeout=5m
}

phase_mlflow() {
  banner mlflow; need kubectl; cluster_ready
  : "${MLFLOW_BUCKET:?Définir MLFLOW_BUCKET}"
  namespace_exists mlops-platform || phase_namespaces
  kubectl -n mlops-platform wait --for=condition=ready pod -l app=postgres --timeout=60s
  require_secret
  kubectl -n mlops-platform get serviceaccount mlflow >/dev/null 2>&1 || {
  echo "Erreur: ServiceAccount mlflow absent. Exécuter d'abord ./scripts/deploy.sh storage." >&2
  exit 1
}
  sed "s|MLFLOW_BUCKET_PLACEHOLDER|$MLFLOW_BUCKET|g; s|us-east-1|$AWS_REGION|g" "$ROOT_DIR/k8s/mlflow/configmap.yaml" | kubectl apply -f -
  kubectl apply -f "$ROOT_DIR/k8s/mlflow/service.yaml"
  kubectl apply -f "$ROOT_DIR/k8s/mlflow/deployment.yaml"
  kubectl -n mlops-platform rollout status deployment/mlflow --timeout=5m
}

phase_kserve() {
  banner kserve; need helm; need kubectl; cluster_ready
  namespace_exists kserve || phase_namespaces
  echo "Réconciliation de cert-manager et KServe avec Helm."
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm upgrade --install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true --wait
  helm upgrade --install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd --version "$KSERVE_VERSION" --namespace kserve --wait
  helm upgrade --install kserve oci://ghcr.io/kserve/charts/kserve --version "$KSERVE_VERSION" --namespace kserve \
    --set kserve.controller.deploymentMode=RawDeployment --wait
  kubectl -n kserve rollout status deployment/kserve-controller-manager --timeout=5m
}

phase_model() {
  banner model; need python; : "${MLFLOW_TRACKING_URI:?Définir MLFLOW_TRACKING_URI}"
  python "$ROOT_DIR/training/train.py"
}

phase_ecr() {
  banner ecr; need aws
  "$ROOT_DIR/infra/ecr/create-repository.sh"
}

phase_image() {
  banner image; need aws; need docker
  : "${IMAGE_TAG:?Définir IMAGE_TAG avec un tag immuable, par exemple le Git SHA}"
  "$ROOT_DIR/scripts/build-push-image.sh"
}

phase_serving() {
  banner serving; need aws; need helm; need kubectl; cluster_ready
  kubectl get crd inferenceservices.serving.kserve.io >/dev/null 2>&1 || { echo "Erreur: KServe n'est pas installé." >&2; exit 1; }
  : "${IMAGE_TAG:?Définir IMAGE_TAG (Git SHA, jamais latest)}"
  [[ "$IMAGE_TAG" != latest && "$IMAGE_TAG" != replace-with-git-sha ]] || { echo "Erreur: IMAGE_TAG doit être immuable." >&2; exit 1; }
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  IMAGE_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
  aws ecr describe-images --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" \
    --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1 || {
      echo "Erreur: image absente de ECR : $IMAGE_REPOSITORY:$IMAGE_TAG" >&2
      echo "Exécuter d'abord ./scripts/deploy.sh image." >&2
      exit 1
    }
  namespace_exists ml-serving || { echo "Erreur: exécuter la phase namespaces." >&2; exit 1; }
  args=(upgrade --install taxi-duration "$ROOT_DIR/helm/ml-serving" --namespace ml-serving --set-string image.repository="$IMAGE_REPOSITORY" --set-string image.tag="$IMAGE_TAG")
  helm "${args[@]}"
  kubectl -n ml-serving wait --for=condition=Ready inferenceservice/taxi-duration --timeout=10m
}

phase_monitoring() {
  banner monitoring; need helm; need kubectl; cluster_ready
  namespace_exists monitoring || phase_namespaces
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring \
    -f "$ROOT_DIR/k8s/monitoring/values.yaml" --wait --timeout 10m
}

phase_all() {
  phase_namespaces; phase_storage; phase_postgres; phase_mlflow; phase_kserve; phase_model
  phase_ecr; phase_image; phase_serving
  echo "Monitoring reste optionnel: ./scripts/deploy.sh monitoring"
}

case "$PHASE" in
  namespaces) phase_namespaces;; storage) phase_storage;; postgres) phase_postgres;; mlflow) phase_mlflow;;
  kserve) phase_kserve;; model) phase_model;; ecr) phase_ecr;; image) phase_image;;
  serving) phase_serving;; monitoring) phase_monitoring;; all) phase_all;;
  *)
    echo "Erreur: phase inconnue: $PHASE" >&2
    echo "Usage: $0 [namespaces|storage|postgres|mlflow|kserve|model|ecr|image|serving|monitoring|all]" >&2

    echo "Sans argument, un menu interactif est affiché." >&2
    exit 1
    ;;
esac
