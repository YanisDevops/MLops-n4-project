# KServe sur EKS

Le projet cible **KServe Standard Mode** (RawDeployment) afin d'éviter Istio, Knative et le scale-to-zero. `scripts/deploy.sh kserve` installe d'abord `cert-manager`, puis le chart OCI officiel KServe avec `kserve.controller.deploymentMode=RawDeployment`.

La version est épinglée par `KSERVE_VERSION` dans le script. Vérifier sa compatibilité avec la version Kubernetes avant une mise à jour. Le namespace `kserve` doit exister (`deploy.sh namespaces`).

L'InferenceService utilise un predictor personnalisé : le modèle est récupéré/chargé une seule fois au démarrage du processus, jamais à chaque requête.
