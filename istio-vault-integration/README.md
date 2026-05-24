# Istio Ambient Mesh & HashiCorp Vault PKI Integration

This repository provides a fully codified local playground to demonstrate how to integrate **Istio in Ambient Mode** with **HashiCorp Vault (OpenBao)** as an external, Dockerized Certificate Authority (CA) for both workload mutual TLS (mTLS) and external gateway TLS termination.

The setup is built locally using **Kind** (Kubernetes in Docker), **MetalLB** for load balancing, **cert-manager** for TLS lifecycle management, and **istio-csr** to bridge Istio's certificate requests directly to Vault.

---

## Key Features & How They Are Enabled

For junior developers or platform engineering newcomers, here is a quick reference explaining how each key feature is enabled in this setup:

*   **External CA & Secrets Management (HashiCorp Vault / OpenBao)**: We run Vault as an isolated Docker container on the same Docker network as the Kubernetes cluster. Terraform bootstraps and unseals Vault, configures its PKI engines with Root and Intermediate CAs, and dynamically reconfigures Vault to secure its own API with a signed TLS certificate over HTTPS.
*   **Cluster Load Balancing (MetalLB)**: We deploy the MetalLB Helm chart inside our Kind cluster and configure it with a range of IP addresses on the local Docker network subnet. When a Kubernetes Gateway or Service requests an external IP address, MetalLB automatically assigns it one from this pool so that it can receive traffic from outside the cluster.
*   **Workload Mutual TLS Security (Istio mTLS via istio-csr)**: We deploy the `istio-csr` agent in the cluster and configure the Istio control plane (`istiod`) to forward certificate requests to it rather than signing them itself. When workloads communicate, `istio-csr` intercepts their certificate requests, authenticates them against Vault's AppRole, and issues Vault-signed mTLS certificates.
*   **Secure Ingress Traffic (Gateway API & cert-manager)**: We define a Gateway API resource listening on HTTPS (port 443) and reference a Certificate resource managed by `cert-manager`. `cert-manager` connects to Vault using AppRole credentials to dynamically request, store, and renew the TLS certificate for the `*.ops.<your-root-domain>` subdomains.

---

## Documentation Index

To help you navigate this repository, we have split the documentation into distinct guides:

1.  **[Architecture Guide](file:///Users/naugustin/work/hobby-projects/ai-generated-projects/istio-vault-integration/ARCHITECTURE.md)**: Deep dive into each component (Vault, Kind, MetalLB, cert-manager, Istio Ambient, and Gateway Routing) and how they communicate.
2.  **[Validation & Local Access Guide](file:///Users/naugustin/work/hobby-projects/ai-generated-projects/istio-vault-integration/validation.md)**: Step-by-step instructions to configure local macOS routing, set up DNS name resolution, trust the root certificate in your Keychain, and test access in your browser.

---

## Quick Start

### 1. Prerequisites
Ensure you have the following installed on your machine:
*   [Docker Desktop](https://www.docker.com/products/docker-desktop/)
*   [Terraform](https://developer.hashicorp.com/terraform/downloads) (v1.5.0+)
*   [kubectl](https://kubernetes.io/docs/tasks/tools/)
*   `curl` and `jq`

### 2. Deploy Infrastructure
Navigate to the `terraform` directory and apply the configuration:
```bash
cd terraform
terraform init
terraform apply -auto-approve
```
*Note: The bootstrap script will run automatically. It will initialize Vault, save tokens in the `certs/` folder, and bring up the Kind cluster and all Helm components.*

### 3. Verify TLS Integration
Once the deploy is complete and you have set up your local routing/DNS according to the [Validation Guide](file:///Users/naugustin/work/hobby-projects/ai-generated-projects/istio-vault-integration/validation.md), run the automated validation test script:
```bash
./tests/verify-tls.sh
```

### 4. Cleanup
To destroy all created resources:
```bash
cd terraform
terraform destroy -auto-approve
```
