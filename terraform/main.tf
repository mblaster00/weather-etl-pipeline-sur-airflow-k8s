terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Le cluster GKE en mode Autopilot
resource "google_container_cluster" "primary" {
  name                = var.cluster_name
  location            = var.region
  deletion_protection = false

  enable_autopilot = false

  initial_node_count = 2

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 20        # reduce from 50 to 20
    disk_type    = "pd-standard"  # use HDD instead of SSD
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
}

# Reserve a private IP range for Google services peering
resource "google_compute_global_address" "private_ip_range" {
  name          = "google-managed-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Create the peering connection between your VPC and Google service network
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

resource "google_sql_database_instance" "postgres" {
  name             = "weather-etl-db"
  database_version = "POSTGRES_15"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  lifecycle {
    ignore_changes = [settings]
  }

  settings {
    tier = "db-f1-micro"

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }

  deletion_protection = false
}

# The database
resource "google_sql_database" "weather" {
  name     = "weather"
  instance = google_sql_database_instance.postgres.name
}

# GCP Service Account for the ETL pods
resource "google_service_account" "airflow_pods" {
  account_id   = "airflow-pods-sa"
  display_name = "Airflow ETL Pods"
  project      = var.project_id
}

# Grant Cloud SQL access
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.airflow_pods.email}"
}

# Grant Cloud Storage access
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.airflow_pods.email}"
}

# Bind GCP Service Account to Kubernetes Service Account
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.airflow_pods.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[airflow/airflow-pods-ksa]"
}