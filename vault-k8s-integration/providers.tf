terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.23.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10.0"
    }
  }
}

provider "kind" {}

provider "docker" {
}

provider "vault" {
  # Vault will be mapped to localhost port 8282 on the host to avoid collisions. 
  address = "http://localhost:8282"
  token   = "root"
}

provider "kubernetes" {
  alias                  = "cluster1"
  host                   = kind_cluster.cluster1.endpoint
  client_certificate     = kind_cluster.cluster1.client_certificate
  client_key             = kind_cluster.cluster1.client_key
  cluster_ca_certificate = kind_cluster.cluster1.cluster_ca_certificate
}

provider "kubernetes" {
  alias                  = "cluster2"
  host                   = kind_cluster.cluster2.endpoint
  client_certificate     = kind_cluster.cluster2.client_certificate
  client_key             = kind_cluster.cluster2.client_key
  cluster_ca_certificate = kind_cluster.cluster2.cluster_ca_certificate
}
