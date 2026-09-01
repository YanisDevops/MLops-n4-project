# MLOps Niveau 4 sur AWS EKS

Plateforme pédagogique déployable progressivement : MLflow + PostgreSQL + S3, entraînement XGBoost, serving KServe en mode Standard, Helm, Prometheus/Grafana et CI/CD GitHub Actions.

## Architecture

```text
GitHub
  |
GitHub Actions
  |
  v
EKS
 |
 +-- mlops-platform
 |     +-- PostgreSQL
 |     +-- MLflow ----> S3
 |
 +-- ml-serving
 |     +-- KServe InferenceService
 |           |
 |           +-- XGBoost model
 |
 +-- monitoring
       +-- Prometheus
       +-- Grafana
```

Le cluster utilise un Managed Node Group public (pas de NAT Gateway), avec 1 nœud au départ et une capacité de 1 à 2 nœuds. Les workloads utilisent IRSA : aucune clé AWS statique n'est stockée dans Kubernetes.

## Prérequis

- AWS CLI v2 authentifiée
- `eksctl`, `kubectl`, `helm`, `docker`
- Python 3.11 pour l'entraînement local
- droits AWS pour EKS, EC2/VPC, IAM, S3, ECR et CloudFormation

Copier `.env.example` vers `.env`, choisir un suffixe S3 globalement unique, puis exporter les variables dans le shell. Ne jamais committer `.env` ni un Secret réel.

## Variables principales

| Variable | Défaut | Usage |
|---|---|---|
| `AWS_REGION` | `us-east-1` | région AWS |
| `CLUSTER_NAME` | `mlops-n4` | cluster EKS |
| `NODEGROUP_NAME` | `mlops-workers` | node group |
| `INSTANCE_TYPE` | `t3.medium` | type EC2 (à reporter dans `cluster.yaml`) |
| `MLFLOW_BUCKET` | requis | bucket d'artifacts |
| `AWS_ACCOUNT_ID` | détectable par AWS CLI | IAM/ECR |
| `IMAGE_REPOSITORY` | requis pour le serving | dépôt ECR |
| `IMAGE_TAG` | Git SHA conseillé | image immuable |

`eksctl` ne substitue pas les variables dans YAML. Modifier les valeurs annotées dans `infra/eks/cluster.yaml` avant la création si les défauts ne conviennent pas.

## 1. Créer uniquement EKS

```bash
chmod +x infra/eks/*.sh infra/ecr/*.sh scripts/*.sh infra/s3/*.sh infra/iam/scripts/*.sh
export AWS_REGION=us-east-1
export CLUSTER_NAME=mlops-n4
./infra/eks/create-cluster.sh
```

Cette étape crée uniquement le cluster et son node group. Elle ne déploie aucun workload.
Si le cluster existe déjà et qu'il est actif, le script le réutilise et actualise simplement le
kubeconfig.

## 2. Déploiement progressif

```bash
./scripts/deploy.sh namespaces
export MLFLOW_BUCKET=mlops-n4-mlflow-artifacts-<suffixe-unique>
./scripts/deploy.sh storage
kubectl -n mlops-platform create secret generic postgres-secret \
  --from-literal=POSTGRES_DB=mlflow \
  --from-literal=POSTGRES_USER=mlflow \
  --from-literal=POSTGRES_PASSWORD='<mot-de-passe-fort>'
./scripts/deploy.sh postgres
./scripts/deploy.sh mlflow
./scripts/deploy.sh kserve
./scripts/deploy.sh model
export ECR_REPOSITORY=mlops-n4-predictor
export IMAGE_TAG=<git-sha-ou-tag-immuable>
./scripts/deploy.sh ecr
./scripts/deploy.sh image
./scripts/deploy.sh serving
./scripts/deploy.sh monitoring  # optionnel
```

La phase `ecr` crée le repository seulement s'il est absent. La phase `image` authentifie Docker,
construit l'image du predictor et la pousse dans ECR. Si le même tag existe déjà dans ECR, aucun
nouveau build ou push n'est effectué. `latest` est volontairement interdit.

L'image contient uniquement le code de serving. Au démarrage, le predictor charge une seule fois
`models:/TaxiDurationXGB@candidate` depuis MLflow. Le serveur MLflow joue le rôle de proxy vers S3 :
le pod predictor n'a donc besoin ni d'une copie locale du modèle, ni de permissions S3.

Après le passage au proxy d'artifacts, les expériences MLflow existantes conservent leur ancienne
URI S3. Les nouveaux entraînements utilisent par défaut l'expérience
`nyc-taxi-duration-proxied`. Il faut redéployer MLflow avant de relancer l'entraînement.

Les phases sont relançables : les créations AWS impératives vérifient d'abord l'existence de la
ressource, tandis que Kubernetes et Helm réconcilient les ressources existantes avec
`kubectl apply` et `helm upgrade --install`.

`model` entraîne et enregistre le modèle depuis la machine locale. Pour accéder à MLflow localement : `kubectl -n mlops-platform port-forward svc/mlflow 5000:5000`, puis `export MLFLOW_TRACKING_URI=http://127.0.0.1:5000`.

## 3. Tester et diagnostiquer

```bash
./scripts/status.sh
./scripts/test-inference.sh
```

Le script de test fait un port-forward vers le service créé par KServe et vérifie la présence de `predicted_duration`, `model_alias`/`model_version` et `latency_ms`.

## 4. Redimensionner le node group

```bash
./infra/eks/scale-nodes.sh 2
```

La valeur doit rester entre 1 et 2. Si la capacité demandée est déjà appliquée, le script ne lance
aucune opération de scaling. Aucun cluster n'est reconstruit.

## 5. Supprimer

```bash
./scripts/cleanup.sh workloads
./infra/eks/delete-cluster.sh
```

Le bucket S3 n'est volontairement pas vidé/supprimé automatiquement afin d'éviter une perte d'artifacts.

## Coûts à surveiller

- instances EC2 du Managed Node Group et volumes EBS gp3 ;
- plan de contrôle EKS facturé même si les nœuds sont arrêtés ;
- stockage/requêtes S3 et ECR ;
- éventuel LoadBalancer (les Services fournis sont ClusterIP) ;
- logs CloudWatch et trafic inter-AZ.

Les subnets sont publics pour éviter le coût d'une NAT Gateway. Les nœuds reçoivent une IP publique : limiter les règles réseau et préférer un VPC privé/NAT ou des VPC endpoints pour une production durcie.

## Canary ultérieur

Le chart expose `canary.enabled` et `canary.trafficPercent`. KServe peut alors router une part du trafic vers une révision canary sans changer l'architecture générale.
