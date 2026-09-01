#!/usr/bin/env bash
set -euo pipefail
command -v kubectl >/dev/null 2>&1 || { echo "Erreur: kubectl est requis." >&2; exit 1; }

section() { printf '\n=== %s ===\n' "$1"; }
section "EKS nodes"; kubectl get nodes -o wide
section "Namespaces"; kubectl get namespaces
for ns in mlops-platform ml-serving kserve monitoring; do
  section "Pods: $ns"; kubectl get pods -n "$ns" -o wide 2>/dev/null || echo "Namespace absent"
done
section "Services"; kubectl get services -A
section "PVC"; kubectl get pvc -A
section "InferenceServices"; kubectl get inferenceservices.serving.kserve.io -A 2>/dev/null || echo "CRD KServe absente"
