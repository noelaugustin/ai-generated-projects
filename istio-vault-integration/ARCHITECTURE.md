# Istio Ambient Mesh & Vault PKI Integration Architecture

Welcome to the Istio + Vault playground! This document is intended for Junior SREs or platform engineers to understand how the components tie together.

## Overview
This setup creates a local Kubernetes environment running Istio in Ambient Mode. We use HashiCorp Vault (OpenBao) as an external, Dockerized CA to issue certificates for the service mesh and the application gateways. The infrastructure is entirely codified using Terraform.

## Key Features & How They Are Enabled

Here is a quick reference explaining how each key feature in this setup is enabled and configured, written to be easily understood by a junior developer:

*   **External CA & Secrets Management (HashiCorp Vault / OpenBao)**: We run Vault as an isolated Docker container on the same Docker network as the Kubernetes cluster. Terraform bootstraps and unseals Vault, configures its PKI engines with Root and Intermediate CAs, and dynamically reconfigures Vault to secure its own API with a signed TLS certificate over HTTPS.
*   **Cluster Load Balancing (MetalLB)**: We deploy the MetalLB Helm chart inside our Kind cluster and configure it with a range of IP addresses on the local Docker network subnet. When a Kubernetes Gateway or Service requests an external IP address, MetalLB automatically assigns it one from this pool so that it can receive traffic from outside the cluster.
*   **Workload Mutual TLS Security (Istio mTLS via istio-csr)**: We deploy the `istio-csr` agent in the cluster and configure the Istio control plane (`istiod`) to forward certificate requests to it rather than signing them itself. When workloads communicate, `istio-csr` intercepts their certificate requests, authenticates them against Vault's AppRole, and issues Vault-signed mTLS certificates.
*   **Secure Ingress Traffic (Gateway API & cert-manager)**: We define a Gateway API resource listening on HTTPS (port 443) and reference a Certificate resource managed by `cert-manager`. `cert-manager` connects to Vault using AppRole credentials to dynamically request, store, and renew the TLS certificate for the `*.ops.<your-root-domain>` subdomains.

## Components & Flow

### 1. External Vault (OpenBao)
- **What it is**: An isolated Docker container running OpenBao, mocking an enterprise Vault instance outside of Kubernetes.
- **Why we need it**: In real-world environments, the PKI (Public Key Infrastructure) is highly secured and usually sits outside the cluster. We use it to store our Root CA and dynamically issue Intermediate certificates.
- **How it works**:
  - Vault boots initially over HTTP (port 80).
  - A Terraform `local-exec` provisioner connects to Vault to initialize and unseal it.
  - The script enables Vault's PKI engines, generates the `<your-root-domain>` Root CA directly inside Vault, signs intermediate CAs (`ops.<your-root-domain>` and `istio.<your-root-domain>`), and exports the root/intermediate certificates to the host.
  - Vault uses the `ops.<your-root-domain>` Intermediate CA to self-issue a TLS Server certificate.
  - Vault dynamically reconfigures itself to serve traffic over HTTPS (port 443) using this certificate chain and restarts.

### 2. Kubernetes Cluster (Kind)
- **What it is**: Kubernetes-in-Docker (Kind) creates a multi-node cluster locally using Docker containers as nodes.
- **Networking**:
  - We run Kind and Vault on the same custom Docker network (`mesh-network`).
  - A CoreDNS patch inside the cluster ensures pods can resolve `vault.ops.<your-root-domain>` to the Vault Docker container's IP (`10.10.0.10`).

### 3. Load Balancer (MetalLB)
- **What it is**: Provides Network Load Balancer implementations for bare metal/local clusters.
- **Why we need it**: Kind does not provide an external load balancer out-of-the-box. Without it, services of type `LoadBalancer` (like the Istio Gateway) would stay in `<pending>` state forever.
- **How it works**: MetalLB is given an IP pool (`10.10.0.100 - 10.10.0.250`) on the same `mesh-network`. When Istio requests an IP, MetalLB assigns one and advertises it via Layer 2 ARP.

### 4. Certificate Management (cert-manager & istio-csr)
- **What it is**: 
  - `cert-manager` automates certificate provisioning and lifecycle management inside Kubernetes.
  - `istio-csr` (cert-manager-istio-csr) is an agent that allows Istio to delegate its certificate signing requests (CSRs) to cert-manager rather than using its built-in self-signed CA.
- **How it works**:
  - `cert-manager` has two `ClusterIssuer` resources (one for external traffic and one for the internal service mesh) configured to talk to our external Vault instance using AppRole credentials.
  - Instead of relying on Istio's native CA, we run `istio-csr`, which intercepts workload mTLS CSRs and uses the `vault-issuer-istio` ClusterIssuer to get them signed by Vault.

### 5. Istio Ambient Mesh
- **What it is**: The sidecar-less data plane architecture for Istio. It splits the proxy functions into a secure L4 node-level component (`ztunnel`) and an optional L7 component (`waypoint`).
- **How it works**:
  - We install `istio-base`, `istio-cni`, and `ztunnel` using standard Helm charts.
  - The Istio control plane (`istiod`) is configured to disable its internal CA server (`pilot.env.ENABLE_CA_SERVER = false`) and point to `istio-csr` as the custom CA address. Ztunnel and workloads receive Vault-signed certificates dynamically.

### 6. Application Routing & Gateway API
- **What it is**: The modern way to expose services to the outside world, replacing Ingress.
- **How it works**:
  - We deploy `httpbin` to act as our backend service.
  - A `Gateway` resource listens on `*.ops.<your-root-domain>` (HTTPS, port 443) and terminates TLS using a certificate provided by `cert-manager` (and signed by Vault).
  - Multiple `HTTPRoute` resources route traffic from `app1` through `app5` subdomains to the `httpbin` service.

## Testing the Flow
To test this, you can run the `tests/verify-tls.sh` script. It checks if:
1. Vault's TLS API is reachable using our Root CA.
2. The application subdomains respond with certificates trusted by the same Root CA.
