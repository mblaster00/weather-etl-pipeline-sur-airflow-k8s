<div align="center">

<img src="https://img.shields.io/badge/Apache%20Airflow-2.9+-017CEE?style=for-the-badge&logo=apacheairflow&logoColor=white"/>
<img src="https://img.shields.io/badge/Kubernetes-GKE-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white"/>
<img src="https://img.shields.io/badge/Terraform-1.5+-7B42BC?style=for-the-badge&logo=terraform&logoColor=white"/>
<img src="https://img.shields.io/badge/PostgreSQL-Cloud%20SQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white"/>
<img src="https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python&logoColor=white"/>

<br/><br/>

# weather-etl-airflow

### Production-grade ETL pipeline orchestrated by Apache Airflow,
### deployed on Google Kubernetes Engine via Terraform & Helm.

<br/>

[Overview](#-overview) · [Architecture](#-architecture) · [Pipeline](#-pipeline) · [Security](#-security) · [Getting Started](#-getting-started) · [Project Structure](#-project-structure) · [Monitoring](#-monitoring) · [Roadmap](#-roadmap)

</div>

---

## Overview

This project implements a cloud-native, fault-tolerant ETL pipeline that ingests hourly weather data from the [OpenWeatherMap API](https://openweathermap.org/api), transforms it, and persists it to a managed PostgreSQL database on GCP.

Built as a hands-on deep dive into Data Engineering fundamentals — with a focus on production patterns: isolated task execution, declarative infrastructure, zero-secret deployments via Workload Identity, and GitOps-style DAG delivery.

What makes this non-trivial:

- Each ETL task runs in its own ephemeral Kubernetes pod (`KubernetesPodOperator`) — full isolation, independent scaling, no shared state
- Infrastructure is fully reproducible from a single `terraform apply`
- DAGs sync automatically from GitHub via gitSync — no redeploy needed to ship pipeline changes
- Cloud SQL access via Workload Identity — no static credentials anywhere in the cluster
- All secrets managed centrally via Google Secret Manager — no `.env` files, no secrets in Git, full audit trail

---

Each pod reads its input and writes its output to Cloud Storage — fully decoupled, no shared memory between tasks.

---

## Pipeline

The `weather_etl` DAG runs every hour with built-in resilience:

```
check_api_health ──► extract_weather ──► transform_data ──► load_to_postgres
   (HttpSensor)    (KubernetesPod)     (KubernetesPod)     (KubernetesPod)
```

| Task | Operator | Responsibility |
|---|---|---|
| `check_api_health` | `HttpSensor` | Guards the pipeline — skips execution if API is unreachable |
| `extract_weather` | `KubernetesPodOperator` | Fetches raw JSON from OpenWeatherMap, writes to Cloud Storage |
| `transform_data` | `KubernetesPodOperator` | Reads raw JSON, normalises and validates, writes to Cloud Storage |
| `load_to_postgres` | `KubernetesPodOperator` | Reads transformed data, upserts into Cloud SQL |

Resilience config:

```python
default_args = {
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(minutes=30),
}
```

Key Airflow concepts covered: DAGs · Operators · Sensors · Hooks · XComs · Connections · Variables · `KubernetesExecutor`

---

## Security

Secret management follows a zero-trust approach — no credentials in the codebase, no shared `.env` files.

**Google Secret Manager** is the single source of truth for all secret values. Access is controlled per team member via IAM roles with a full audit trail of who accessed what and when.

```bash
# Create a secret — done once by the team lead
echo -n "YOUR_VALUE" | gcloud secrets create openweather-api-key --data-file=-

# Grant access to a teammate
gcloud secrets add-iam-policy-binding openweather-api-key \
  --member="user:teammate@company.com" \
  --role="roles/secretmanager.secretAccessor"
```

**Kubernetes Secrets** are injected automatically by the CI/CD pipeline on every deploy — pulled from Secret Manager, never stored on disk:

```bash
API_KEY=$(gcloud secrets versions access latest --secret="openweather-api-key")
kubectl create secret generic weather-api-secret \
  --from-literal=api_key=$API_KEY \
  --namespace airflow \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Workload Identity** handles Cloud SQL authentication — pods connect to the database without any password. GCP manages authentication transparently via Kubernetes and GCP Service Account bindings.

**Private networking** — Cloud SQL has no public IP. All traffic stays within the VPC.

**gitSync SSH Deploy Key** — DAG sync uses a read-only SSH deploy key, not a personal access token. The private key lives in a Kubernetes Secret only.

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| Google Cloud SDK | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| Terraform | >= 1.5 | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| Helm | >= 3.12 | [helm.sh](https://helm.sh/docs/intro/install/) |
| kubectl | latest | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Docker | latest | [docs.docker.com](https://docs.docker.com/get-docker/) |

You will also need a GCP project with billing enabled and an [OpenWeatherMap API key](https://openweathermap.org/api) (free tier).

---

### 1 — Configure Terraform

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Fill in your project_id in terraform.tfvars
```

---

### 2 — Provision GKE with Terraform

```bash
terraform init
terraform plan
terraform apply
```

This provisions a GKE Autopilot cluster, Cloud SQL PostgreSQL 15, VPC with private networking, Workload Identity bindings, and Kubernetes namespaces `airflow` and `data`.

Connect kubectl to the cluster using the command printed in Terraform outputs:

```bash
gcloud container clusters get-credentials weather-etl-cluster \
  --region europe-west1 \
  --project YOUR_PROJECT_ID
```

---

### 3 — Push secrets to Google Secret Manager

```bash
echo -n "YOUR_OPENWEATHER_API_KEY" | gcloud secrets create openweather-api-key --data-file=-
echo -n "YOUR_CLOUDSQL_PRIVATE_IP" | gcloud secrets create cloudsql-host --data-file=-
echo -n "weather" | gcloud secrets create cloudsql-database --data-file=-
echo -n "YOUR_WEBSERVER_PASSWORD" | gcloud secrets create airflow-webserver-password --data-file=-
echo -n "YOUR_POSTGRES_PASSWORD" | gcloud secrets create airflow-postgres-password --data-file=-
```

---

### 4 — Inject secrets into Kubernetes

```bash
# Run k8s/inject-secrets.sh — fills K8s Secrets from Secret Manager
chmod +x k8s/inject-secrets.sh
./k8s/inject-secrets.sh
```

---

### 5 — Generate and register the gitSync SSH key

```bash
ssh-keygen -t ed25519 -C "airflow-gitsync" -f ./airflow-gitsync-key

# Add the public key to GitHub → repo Settings → Deploy keys (read-only)
cat airflow-gitsync-key.pub

# Inject the private key into Kubernetes
kubectl create secret generic airflow-gitsync-ssh \
  --from-file=gitSshKey=./airflow-gitsync-key \
  --namespace airflow

# Delete local key files — the K8s Secret is the only copy
rm ./airflow-gitsync-key ./airflow-gitsync-key.pub
```

---

### 6 — Deploy Airflow via Helm

```bash
helm repo add apache-airflow https://airflow.apache.org
helm repo update

helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --values helm/values.yaml
```

Verify the rollout:

```bash
kubectl get pods -n airflow --watch
```

---

### 7 — Initialize the database schema

Trigger the `init_db` DAG manually once from the Airflow UI at `http://localhost:8080` after running:

```bash
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow
```

---

### 8 — Build and push the ETL image

```bash
docker build -t europe-west1-docker.pkg.dev/YOUR_PROJECT/weather-etl/weather-etl:latest .
docker push europe-west1-docker.pkg.dev/YOUR_PROJECT/weather-etl/weather-etl:latest
```

Enable the `weather_etl` DAG in the UI and trigger a first run to validate the full pipeline.

---

## Project Structure

```
weather-etl-airflow/
│
├── terraform/                        # GCP infrastructure as code
│   ├── main.tf                       # VPC · GKE · Cloud SQL · Workload Identity
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example      # Template — copy to terraform.tfvars locally
│
├── helm/
│   └── values.yaml                   # Airflow Helm overrides — no secrets inside
│
├── dags/
│   ├── weather_etl.py                # Main DAG
│   ├── init_db.py                    # One-time schema initialisation DAG
│   ├── sql/
│   │   └── init.sql                  # Table definition + indexes
│   └── utils/
│       ├── extract.py                # OpenWeatherMap API client
│       ├── transform.py              # Data normalisation
│       └── load.py                   # Cloud SQL upsert
│
├── docker/
│   ├── Dockerfile                    # Image for ETL pods
│   └── requirements.txt
│
├── k8s/
│   ├── namespace.yaml
│   └── inject-secrets.sh             # Pulls from Secret Manager → K8s Secrets
│
├── .gitignore
└── README.md
```

---

## Monitoring

| Layer | Tool | What it covers |
|---|---|---|
| Pipeline | Airflow UI | DAG runs · task states · logs per pod |
| Infrastructure | Cloud Monitoring | Pod CPU/memory · node health · Cloud SQL metrics |
| Alerts | Cloud Alerting | Task failure notifications · SLA misses |
| Logs | Cloud Logging | Centralised logs from all ephemeral pods |
| Secret access | Cloud Audit Logs | Who accessed which secret and when |

---

## Roadmap

- [x] Project design & architecture
- [x] Terraform: VPC + GKE Autopilot + Cloud SQL
- [x] Helm: Airflow deployment + gitSync
- [x] First DAG with `PythonOperator`
- [x] Refactor to `KubernetesPodOperator`
- [x] Workload Identity + Google Secret Manager
- [ ] CI/CD pipeline — auto build and push image on merge to main
- [ ] Grafana dashboard on collected weather data
- [ ] Multi-city support with dynamic task generation

---

## References

- [Apache Airflow — Core Concepts](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/index.html)
- [KubernetesPodOperator](https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/operators.html)
- [Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/stable/index.html)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [Google Secret Manager](https://cloud.google.com/secret-manager/docs/quickstart)
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [External Secrets Operator](https://external-secrets.io/latest/)