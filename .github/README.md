# GitHub Actions vers AWS

Le workflow utilise GitHub OIDC et des identifiants AWS temporaires. Ne pas créer de clés AWS statiques dans GitHub.

## Configuration GitHub

Créer l'environment `production` avec :

- secret `AWS_DEPLOY_ROLE_ARN` : ARN du rôle IAM assumé par GitHub ;
- variables facultatives `AWS_REGION`, `ECR_REPOSITORY`, `EKS_CLUSTER_NAME`.

Ajouter une règle d'approbation à `production` si une validation humaine est souhaitée.

## Configuration AWS

1. Créer le fournisseur OIDC `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. Créer un rôle avec `infra/iam/policies/github-actions-trust-policy.example.json` après remplacement des placeholders.
3. Attacher `infra/iam/policies/github-actions-deploy-policy.json` après remplacement de `AWS_ACCOUNT_ID`.
4. Créer une EKS access entry pour ce rôle et limiter son accès à `ml-serving` :

```bash
aws eks create-access-entry \
  --cluster-name mlops-n4 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<GITHUB_ROLE>

aws eks associate-access-policy \
  --cluster-name mlops-n4 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<GITHUB_ROLE> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
  --access-scope type=namespace,namespaces=ml-serving
```

ECR, EKS, KServe et le namespace `ml-serving` doivent déjà exister.

## Comportement

- PR et push `main` : tests, Helm et build Docker sans accès AWS.
- Lancement manuel avec `deploy=true` : push ECR puis déploiement EKS protégé par `production`.
