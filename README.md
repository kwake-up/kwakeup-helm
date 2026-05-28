# kwakeup Helm Chart

[kwakeup](https://kwakeup.net) is a cloud resource scheduler that starts and stops EC2 instances, RDS clusters, Kubernetes workloads, and more on a schedule — reducing cloud costs without sacrificing uptime.

- **Chart version**: 1.0.4
- **App version**: 1.0.2
- **Source**: https://github.com/kwake-up/kwakeup-helm

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Installation](#installation)
  - [Minimal Production Install](#minimal-production-install)
  - [Development Install (Built-in Postgres)](#development-install-built-in-postgres)
- [Configuration Reference](#configuration-reference)
  - [Image](#image)
  - [Service Account](#service-account)
  - [Ingress](#ingress)
  - [Database](#database)
  - [Encryption Key](#encryption-key)
  - [Bootstrap Admin](#bootstrap-admin)
  - [Session](#session)
  - [CORS](#cors)
  - [OIDC / SSO](#oidc--sso)
  - [SAML 2.0](#saml-20)
  - [Built-in PostgreSQL](#built-in-postgresql)
  - [Resources & Scheduling](#resources--scheduling)
- [Cloud Provider Setup](#cloud-provider-setup)
  - [AWS (EKS)](#aws-eks)
  - [GCP (GKE)](#gcp-gke)
  - [Azure (AKS)](#azure-aks)
- [Secret Management](#secret-management)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Kubernetes **1.24+**
- Helm **3.10+**
- A **PostgreSQL 14+** database (or enable the built-in postgres for development)
- For cloud scheduling: appropriate IAM permissions on the target cloud account (see [Cloud Provider Setup](#cloud-provider-setup))

---

## Quick Start

```bash
helm upgrade --install kwakeup oci://ghcr.io/kwake-up/kwakeup-helm \
  --namespace kwakeup --create-namespace 
```

The built-in PostgreSQL is enabled by default. The bootstrap admin password and encryption key auto-generate if omitted — retrieve them with:

```bash
# Bootstrap admin email
kubectl get secret kwakeup-bootstrap -n kwakeup \
  -o jsonpath='{.data.bootstrap-admin-email}' | base64 -d

# Bootstrap admin password
kubectl get secret kwakeup-bootstrap -n kwakeup \
  -o jsonpath='{.data.bootstrap-admin-password}' | base64 -d

# Encryption key (protects stored cloud credentials — back this up)
kubectl get secret kwakeup-encryption -n kwakeup \
  -o jsonpath='{.data.encryption-key}' | base64 -d
```

> For production, disable the built-in postgres, point the app at a managed database, and reference secrets externally. See [Installation](#installation).

---

## Installation

### Minimal Production Install

**Step 1** — Create the secrets your cluster needs before installing the chart:

```bash
# Bootstrap admin credentials
kubectl create secret generic kwakeup-bootstrap \
  --from-literal=bootstrap-admin-email=admin@example.com \
  --from-literal=bootstrap-admin-password='<strong-password>'

# Database DSN
kubectl create secret generic kwakeup-db-dsn \
  --from-literal=db_dsn='host=db.example.com port=5432 user=kwakeup password=<pw> dbname=kwakeup sslmode=require'
```

**Step 2** — Create a `values.yaml`:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: kwakeup.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: kwakeup-tls
      hosts:
        - kwakeup.example.com

app:
  bootstrapAdmin:
    existingSecret: kwakeup-bootstrap

database:
  secretName: kwakeup-db-dsn

pdb:
  enabled: true
```

**Step 3** — Install:

```bash
helm upgrade --install kwakeup oci://ghcr.io/kwake-up/kwakeup-helm \
  --namespace kwakeup --create-namespace \
  -f values.yaml
```

---

### Default Install (Built-in Postgres)

The built-in PostgreSQL StatefulSet is **enabled by default**, so a bare `helm install` gives a fully working application. This is convenient for evaluation and development; for production, replace it with a managed external database (see [Database](#database)).

The postgres password is auto-generated on first install and persisted across upgrades. To retrieve it:

```bash
kubectl get secret kwakeup-postgres -n kwakeup \
  -o jsonpath='{.data.postgres-password}' | base64 -d
```

---

## Configuration Reference

### Image

```yaml
image:
  repository: ghcr.io/kwake-up/kwakeup
  tag: ""           # defaults to the chart appVersion
  pullPolicy: IfNotPresent

imagePullSecrets: []
```

### Service Account

```yaml
serviceAccount:
  create: true
  name: ""          # defaults to the release full name
  annotations: {}   # used for cloud IAM binding — see Cloud Provider Setup
```

`automountServiceAccountToken` is set to `false` on both the ServiceAccount and the Pod. The application does not call the Kubernetes API directly; re-enable only if you extend it with an operator pattern.

### Ingress

```yaml
ingress:
  enabled: false
  className: ""       # e.g. "nginx", "traefik", "alb"
  annotations: {}
  hosts:
    - host: kwakeup.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: kwakeup-tls
      hosts:
        - kwakeup.example.com
```

**CORS**: When the ingress is enabled and `app.cors.allowedOrigins` is empty, the chart automatically derives `CORS_ALLOWED_ORIGINS` from the ingress host list (prefixed with `https://`). Set `app.cors.allowedOrigins` explicitly if you have additional origins or need `http://`.

### Database

Choose **one** of the following options:

#### Option A — External secret (recommended for production)

```yaml
database:
  secretName: kwakeup-db-dsn   # name of the Secret
  secretKey: db_dsn            # key inside the Secret (default: db_dsn)
```

Pre-create the secret:

```bash
kubectl create secret generic kwakeup-db-dsn \
  --from-literal=db_dsn='host=db.example.com port=5432 user=kwakeup password=<pw> dbname=kwakeup sslmode=require'
```

#### Option B — Inline DSN (development only)

```yaml
database:
  dsn: "host=db.example.com port=5432 user=kwakeup password=secret dbname=kwakeup sslmode=require"
```

#### Option C — Built-in PostgreSQL (default, development only)

```yaml
postgres:
  enabled: true  # default
  postgresUser: kwakeup
  postgresPassword: ""      # auto-generated if empty
  postgresDatabase: kwakeupdb
  persistence:
    enabled: true
    size: 8Gi
    storageClassName: ""    # uses cluster default if empty
```

To use an existing secret for the built-in postgres credentials, create a secret with keys `postgres-user`, `postgres-password`, `postgres-db`, and `dsn`, then set:

```yaml
postgres:
  enabled: true
  existingSecret: my-postgres-secret
```

### Encryption Key

The encryption key protects cloud account credentials stored in the database. **Losing this key makes stored credentials unrecoverable.**

```yaml
app:
  encryptionKey:
    value: ""                  # auto-generates a 64-char key on first install
    existingSecret: ""         # reference a pre-existing Secret (recommended)
    secretKey: encryption-key  # key inside the Secret
```

Auto-generated keys are persisted across upgrades via `helm.sh/resource-policy: keep` and a `lookup` check. For production, manage this key in your secret manager and reference it:

```bash
kubectl create secret generic kwakeup-encryption \
  --from-literal=encryption-key='<your-64-char-key>'
```

```yaml
app:
  encryptionKey:
    existingSecret: kwakeup-encryption
```

### Bootstrap Admin

The bootstrap admin is created **once**, on first startup when the database is empty. After that, manage users through the application UI.

```yaml
app:
  bootstrapAdmin:
    email: ""             # required for first login
    password: ""          # auto-generated if empty; retrieve from the Secret
    existingSecret: ""    # recommended for production
    secretKeys:
      email: bootstrap-admin-email
      password: bootstrap-admin-password
```

To retrieve an auto-generated password:

```bash
kubectl get secret kwakeup-bootstrap -n kwakeup \
  -o jsonpath='{.data.bootstrap-admin-password}' | base64 -d
```

### Session

```yaml
app:
  session:
    absoluteTTL: "24h"   # maximum session lifetime (Go duration)
    idleTTL: "30m"       # session expires after this period of inactivity
```

### CORS

```yaml
app:
  cors:
    allowedOrigins: ""   # e.g. "https://kwakeup.example.com,https://admin.example.com"
                         # auto-derived from ingress.hosts when left empty
    allowedMethods: "GET,POST,PUT,DELETE,OPTIONS"
    maxAge: "12h"
```

### OIDC / SSO

```yaml
app:
  oidc:
    enabled: false
    issuer: "https://accounts.google.com"         # IdP discovery URL
    clientId: "my-client-id"
    clientSecret: ""                              # use existingSecret in production
    existingSecret: ""                            # Secret with key oidc-client-secret
    secretKey: oidc-client-secret
    redirectUrl: "https://kwakeup.example.com/auth/oidc/callback"
    groupsClaim: "groups"                         # JWT claim used for group membership
```

Pre-create the OIDC secret:

```bash
kubectl create secret generic kwakeup-oidc \
  --from-literal=oidc-client-secret='<your-client-secret>'
```

```yaml
app:
  oidc:
    enabled: true
    issuer: "https://login.microsoftonline.com/<tenant-id>/v2.0"
    clientId: "<app-registration-client-id>"
    existingSecret: kwakeup-oidc
    redirectUrl: "https://kwakeup.example.com/auth/oidc/callback"
```

### SAML 2.0

```yaml
app:
  saml:
    enabled: false
    idpMetadataUrl: ""      # URL to your IdP's metadata XML
    spEntityId: ""          # e.g. "https://kwakeup.example.com"
    spAcsUrl: ""            # e.g. "https://kwakeup.example.com/auth/saml/acs"
    spCert: ""              # PEM-encoded SP certificate (use existingSecret in production)
    spKey: ""               # PEM-encoded SP private key (use existingSecret in production)
    existingSecret: ""      # Secret with keys saml-sp-cert, saml-sp-key
    secretKeys:
      cert: saml-sp-cert
      key: saml-sp-key
```

Pre-create the SAML secret:

```bash
kubectl create secret generic kwakeup-saml \
  --from-file=saml-sp-cert=./sp.crt \
  --from-file=saml-sp-key=./sp.key
```

```yaml
app:
  saml:
    enabled: true
    idpMetadataUrl: "https://idp.example.com/metadata.xml"
    spEntityId: "https://kwakeup.example.com"
    spAcsUrl: "https://kwakeup.example.com/auth/saml/acs"
    existingSecret: kwakeup-saml
```

### Resources & Scheduling

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 256Mi   # no CPU limit intentionally — avoids throttling on burst

nodeSelector: {}
tolerations: []
affinity: {}

pdb:
  enabled: false    # enable in production
  minAvailable: 1
```

---

## Cloud Provider Setup

kwakeup needs cloud credentials to schedule resources. The recommended approach on managed Kubernetes is **pod-level IAM binding** (no long-lived keys in secrets).

### AWS (EKS)

#### 1. Enable IRSA on your cluster

IRSA (IAM Roles for Service Accounts) lets pods assume an IAM role via a projected service account token.

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster <cluster-name> \
  --approve
```

#### 2. Create the IAM policy

Create a policy granting the permissions kwakeup needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances",
        "rds:StartDBInstance",
        "rds:StopDBInstance",
        "rds:StartDBCluster",
        "rds:StopDBCluster",
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters",
        "eks:ListClusters",
        "eks:DescribeCluster",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

> `eks:ListClusters` and `eks:DescribeCluster` are required for EKS cluster discovery (endpoint and CA certificate). `sts:GetCallerIdentity` is required for generating short-lived EKS bearer tokens via presigned STS URLs.

```bash
aws iam create-policy \
  --policy-name kwakeup-policy \
  --policy-document file://kwakeup-policy.json
```

#### 3. Create the IAM role with a trust policy

```bash
eksctl create iamserviceaccount \
  --name kwakeup \
  --namespace kwakeup \
  --cluster <cluster-name> \
  --attach-policy-arn arn:aws:iam::<account-id>:policy/kwakeup-policy \
  --approve \
  --override-existing-serviceaccounts
```

Or manually create the role with this trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<account-id>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<oidc-id>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.<region>.amazonaws.com/id/<oidc-id>:sub": "system:serviceaccount:kwakeup:kwakeup",
          "oidc.eks.<region>.amazonaws.com/id/<oidc-id>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

#### 4. Annotate the service account in values.yaml

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/kwakeup-role
```

#### Cross-account scheduling

To schedule resources in a **different AWS account**, create an IAM role in the target account that trusts the kwakeup role:

```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::<kwakeup-account-id>:role/kwakeup-role"
  },
  "Action": "sts:AssumeRole"
}
```

Then configure the target account in the kwakeup UI with the cross-account role ARN.

---

### GCP (GKE)

#### 1. Enable Workload Identity on your cluster

```bash
gcloud container clusters update <cluster-name> \
  --workload-pool=<project-id>.svc.id.goog \
  --region <region>
```

Enable it on the node pool too:

```bash
gcloud container node-pools update <node-pool> \
  --cluster <cluster-name> \
  --region <region> \
  --workload-metadata=GKE_METADATA
```

#### 2. Create a GCP service account

```bash
gcloud iam service-accounts create kwakeup \
  --display-name "kwakeup scheduler"
```

#### 3. Grant the required roles

```bash
# Compute Engine (start/stop VMs)
gcloud projects add-iam-policy-binding <project-id> \
  --member "serviceAccount:kwakeup@<project-id>.iam.gserviceaccount.com" \
  --role "roles/compute.instanceAdmin.v1"

# Cloud SQL (start/stop instances)
gcloud projects add-iam-policy-binding <project-id> \
  --member "serviceAccount:kwakeup@<project-id>.iam.gserviceaccount.com" \
  --role "roles/cloudsql.editor"

# GKE (scale workloads)
gcloud projects add-iam-policy-binding <project-id> \
  --member "serviceAccount:kwakeup@<project-id>.iam.gserviceaccount.com" \
  --role "roles/container.developer"
```

#### 4. Bind the Kubernetes service account to the GCP service account

```bash
gcloud iam service-accounts add-iam-policy-binding \
  kwakeup@<project-id>.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:<project-id>.svc.id.goog[kwakeup/kwakeup]"
```

#### 5. Annotate the Kubernetes service account in values.yaml

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: kwakeup@<project-id>.iam.gserviceaccount.com
```

#### Cross-project scheduling

To schedule resources in a **different GCP project**, configure the target account in the kwakeup UI with `serviceAccountEmail` pointing to a service account in the target project. Then grant the kwakeup SA permission to impersonate it:

```bash
# Allow kwakeup's SA to impersonate the target SA
gcloud iam service-accounts add-iam-policy-binding \
  target-sa@<target-project-id>.iam.gserviceaccount.com \
  --role roles/iam.serviceAccountTokenCreator \
  --member "serviceAccount:kwakeup@<kwakeup-project-id>.iam.gserviceaccount.com"

# Grant the target SA the required roles in the target project
gcloud projects add-iam-policy-binding <target-project-id> \
  --member "serviceAccount:target-sa@<target-project-id>.iam.gserviceaccount.com" \
  --role "roles/compute.instanceAdmin.v1"
```

> `roles/iam.serviceAccountTokenCreator` is required for the kwakeup SA to generate short-lived tokens as the target SA. Without it, the impersonation call will return a 403.

---

### Azure (AKS)

#### 1. Enable Workload Identity on your cluster

```bash
az aks update \
  --name <cluster-name> \
  --resource-group <resource-group> \
  --enable-oidc-issuer \
  --enable-workload-identity
```

Retrieve the OIDC issuer URL:

```bash
AKS_OIDC_ISSUER=$(az aks show \
  --name <cluster-name> \
  --resource-group <resource-group> \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)
```

#### 2. Create a managed identity

```bash
az identity create \
  --name kwakeup \
  --resource-group <resource-group>

CLIENT_ID=$(az identity show \
  --name kwakeup \
  --resource-group <resource-group> \
  --query clientId -o tsv)
```

#### 3. Assign the required roles

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Virtual Machines — list + start/stop across the subscription
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Virtual Machine Contributor" \
  --scope /subscriptions/$SUBSCRIPTION_ID

# Azure SQL — list servers + pause/resume databases across the subscription
az role assignment create \
  --assignee $CLIENT_ID \
  --role "SQL DB Contributor" \
  --scope /subscriptions/$SUBSCRIPTION_ID

# AKS — list clusters + authenticate to the cluster API across the subscription
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope /subscriptions/$SUBSCRIPTION_ID

# AKS — manage Deployments/StatefulSets within each cluster (Kubernetes RBAC via Azure)
# Repeat for every AKS cluster kwakeup should schedule workloads in.
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Azure Kubernetes Service RBAC Writer" \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/<resource-group>/providers/Microsoft.ContainerService/managedClusters/<cluster-name>
```

> The VM and SQL roles must be scoped at the **subscription** level because kwakeup scans resources across the entire subscription. `Azure Kubernetes Service Cluster User Role` is required at subscription scope to enumerate all AKS clusters; `Azure Kubernetes Service RBAC Writer` grants Kubernetes RBAC edit access and must be assigned per cluster.

#### 4. Create the federated identity credential

```bash
az identity federated-credential create \
  --name kwakeup-federated \
  --identity-name kwakeup \
  --resource-group <resource-group> \
  --issuer $AKS_OIDC_ISSUER \
  --subject system:serviceaccount:kwakeup:kwakeup \
  --audience api://AzureADTokenExchange
```

#### 5. Annotate the Kubernetes service account in values.yaml

```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: <client-id>

podAnnotations:
  azure.workload.identity/use: "true"
```

#### Cross-subscription scheduling

To schedule resources in a **different Azure subscription**, assign the managed identity the same roles on the target subscription:

```bash
az role assignment create \
  --assignee $CLIENT_ID \
  --role "Virtual Machine Contributor" \
  --scope /subscriptions/<target-subscription-id>

az role assignment create \
  --assignee $CLIENT_ID \
  --role "SQL DB Contributor" \
  --scope /subscriptions/<target-subscription-id>

az role assignment create \
  --assignee $CLIENT_ID \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope /subscriptions/<target-subscription-id>
```

---

## Secret Management

All sensitive values in the chart can be externalized to pre-existing Kubernetes secrets. This allows integration with [External Secrets Operator](https://external-secrets.io), [Vault Agent Injector](https://developer.hashicorp.com/vault/docs/platform/k8s/injector), or any GitOps-safe secret provisioning tool.

| Secret | `existingSecret` field | Required keys |
|---|---|---|
| Encryption key | `app.encryptionKey.existingSecret` | `encryption-key` |
| Bootstrap admin | `app.bootstrapAdmin.existingSecret` | `bootstrap-admin-email`, `bootstrap-admin-password` |
| OIDC client secret | `app.oidc.existingSecret` | `oidc-client-secret` |
| SAML SP cert & key | `app.saml.existingSecret` | `saml-sp-cert`, `saml-sp-key` |
| External DB DSN | `database.secretName` | `db_dsn` (configurable via `database.secretKey`) |
| Built-in postgres | `postgres.existingSecret` | `postgres-user`, `postgres-password`, `postgres-db`, `dsn` |

Chart-managed secrets that are auto-generated (encryption key, postgres password, bootstrap password) are protected with `helm.sh/resource-policy: keep` so they survive `helm uninstall` and are never silently rotated on `helm upgrade`.

---

## Upgrading

```bash
helm upgrade kwakeup oci://ghcr.io/kwake-up/kwakeup-helm \
  --namespace kwakeup \
  -f values.yaml
```

Secrets with `helm.sh/resource-policy: keep` (encryption key, postgres credentials, bootstrap admin) are never overwritten by an upgrade. If you need to rotate one of these manually:

```bash
kubectl patch secret kwakeup-encryption -n kwakeup \
  -p '{"stringData":{"encryption-key":"<new-key>"}}'
```

> Rotating the encryption key requires re-encrypting all stored cloud credentials in the database. Refer to the kwakeup documentation for the key rotation procedure.

---

## Troubleshooting

**Application fails to start with a database error**

Check that one of `database.secretName`, `database.dsn`, or `postgres.enabled` is set. Verify the DSN is reachable from within the cluster:

```bash
kubectl run -it --rm pg-test --image=postgres:16-alpine --restart=Never -- \
  psql "host=db.example.com port=5432 user=kwakeup dbname=kwakeup sslmode=require"
```

**Cannot log in after install**

If `app.bootstrapAdmin.email` was not set, no admin user was created. Set it and run `helm upgrade` to trigger a re-run of the bootstrap (the application only creates the user if the database is empty).

**Encryption key secret missing after uninstall/reinstall**

The `helm.sh/resource-policy: keep` annotation prevents secret deletion on `helm uninstall`, but `kubectl delete secret kwakeup-encryption` will remove it. If lost, restore from your backup before reinstalling.

**CORS errors in the browser**

Verify `app.cors.allowedOrigins` matches the exact origin (scheme + host + port) of your frontend. When using the ingress auto-derivation, check that `ingress.hosts` contains all frontend origins.

**Render templates locally**

```bash
helm template kwakeup ./helm -f my-values.yaml --debug
```

**Validate the chart**

```bash
helm lint ./helm -f my-values.yaml
```
