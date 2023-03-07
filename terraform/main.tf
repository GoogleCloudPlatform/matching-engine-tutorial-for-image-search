/**
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "project_id" {
  type = string
}

terraform {
  required_version = "~> 1.3.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.53.1"
    }
  }
}

provider "google" {
  project = var.project_id
}

data "google_project" "project" {
  project_id = var.project_id
}

/*
 * APIs
 */

resource "google_project_service" "aiplatform" {
  service = "aiplatform.googleapis.com"
}

resource "google_project_service" "artifactregistry" {
  service = "artifactregistry.googleapis.com"
}

resource "google_project_service" "cloudbuild" {
  service = "cloudbuild.googleapis.com"
}

resource "google_project_service" "compute" {
  service = "compute.googleapis.com"
}

resource "google_project_service" "run" {
  service = "run.googleapis.com"
}

resource "google_project_service" "servicenetworking" {
  service = "servicenetworking.googleapis.com"
}

/*
 * Cloud Storage bucket
 *
 * for embeddings
 */

resource "google_storage_bucket" "flowers" {
  name                        = "${data.google_project.project.project_id}-flowers"
  location                    = "us-central1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
}

// https://cloud.google.com/storage/docs/access-control/iam-roles
resource "google_storage_bucket_iam_member" "vectorizer-objectCreator" {
  bucket = google_storage_bucket.flowers.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.vectorizer.email}"
}

/*
 * Vectorizer job
 */

resource "google_service_account" "vectorizer" {
  account_id   = "vectorizer"
  display_name = "Service Account for Vectorizer job"
}

resource "google_artifact_registry_repository" "vectorizer" {
  location      = "us-central1"
  repository_id = "vectorizer"
  format        = "DOCKER"

  depends_on = [google_project_service.artifactregistry]
}

/*
 * Network
 */

resource "google_compute_network" "flowers-search" {
  name                    = "flowers-search"
  auto_create_subnetworks = false
  routing_mode            = "GLOBAL"

  depends_on = [google_project_service.compute]
}

// https://cloud.google.com/vpc/docs/subnets#ip-ranges
resource "google_compute_subnetwork" "us-central1" {
  name          = "us-central1"
  ip_cidr_range = "10.128.0.0/20"
  region        = "us-central1"
  network       = google_compute_network.flowers-search.id
}

resource "google_compute_global_address" "psa-alloc" {
  name          = "psa-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.flowers-search.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.flowers-search.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa-alloc.name]

  depends_on = [google_project_service.servicenetworking]
}

/*
 * Compute Engine instance
 */

data "google_compute_default_service_account" "default" {
  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "query-runner" {
  name         = "query-runner"
  machine_type = "n1-standard-2"
  zone         = "us-central1-b"

  boot_disk {
    initialize_params {
      size  = "20"
      type  = "pd-balanced"
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network    = google_compute_network.flowers-search.name
    subnetwork = google_compute_subnetwork.us-central1.name

    access_config {}
  }

  metadata_startup_script = file("./startup.sh")

  service_account {
    email  = data.google_compute_default_service_account.default.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_firewall" "allow-internal" {
  name          = "flower-search-allow-internal"
  network       = google_compute_network.flowers-search.name
  priority      = 65534
  source_ranges = ["10.128.0.0/9"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
}

resource "google_compute_firewall" "allow-ssh" {
  name          = "flower-search-allow-ssh"
  network       = google_compute_network.flowers-search.name
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

/*
 * Updater
 */

resource "google_service_account" "updater" {
  account_id   = "updater"
  display_name = "Service Account for updater service"
}

resource "google_artifact_registry_repository" "updater" {
  location      = "us-central1"
  repository_id = "updater"
  format        = "DOCKER"

  depends_on = [google_project_service.artifactregistry]
}

// https://cloud.google.com/vertex-ai/docs/general/access-control?hl=ja
resource "google_project_iam_member" "updater-aiplatform-user" {
  project = data.google_project.project.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.updater.email}"
}
