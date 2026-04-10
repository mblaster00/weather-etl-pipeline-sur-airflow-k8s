#!/bin/bash

PROJECT_ID="weather-etl-airflow"

echo "Pulling secrets from Secret Manager..."

# OpenWeatherMap API key
API_KEY=$(gcloud secrets versions access latest \
  --secret="openweather-api-key" \
  --project=$PROJECT_ID)

# Cloud SQL config
CLOUDSQL_HOST=$(gcloud secrets versions access latest \
  --secret="cloudsql-host" \
  --project=$PROJECT_ID)

CLOUDSQL_DB=$(gcloud secrets versions access latest \
  --secret="cloudsql-database" \
  --project=$PROJECT_ID)

# Airflow passwords
WEBSERVER_PASSWORD=$(gcloud secrets versions access latest \
  --secret="airflow-webserver-password" \
  --project=$PROJECT_ID)

POSTGRES_PASSWORD=$(gcloud secrets versions access latest \
  --secret="airflow-postgres-password" \
  --project=$PROJECT_ID)

echo "Injecting into Kubernetes Secrets..."

# OpenWeatherMap API key
kubectl create secret generic weather-api-secret \
  --from-literal=api_key=$API_KEY \
  --namespace airflow \
  --dry-run=client -o yaml | kubectl apply -f -

# Cloud SQL config
kubectl create secret generic cloudsql-secret \
  --from-literal=host=$CLOUDSQL_HOST \
  --from-literal=database=$CLOUDSQL_DB \
  --namespace airflow \
  --dry-run=client -o yaml | kubectl apply -f -

# Airflow webserver password
kubectl create secret generic airflow-webserver-secret \
  --from-literal=password=$WEBSERVER_PASSWORD \
  --namespace airflow \
  --dry-run=client -o yaml | kubectl apply -f -

# Airflow PostgreSQL password
kubectl create secret generic airflow-postgres-secret \
  --from-literal=password=$POSTGRES_PASSWORD \
  --namespace airflow \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done. All secrets injected."