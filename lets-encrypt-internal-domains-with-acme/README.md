# Istio Centralized ACME Certificate Management

This project demonstrates a professional, centralized approach to managing TLS certificates for internal domains within a Kind Kubernetes cluster. It uses Istio as a service mesh, cert-manager for certificate lifecycle management, and a dual-gateway pattern to isolate internal traffic from external ACME validation challenges.

## Architecture

- **Dual-Gateway Pattern**: 
    - `istio-ingress` (External): Handles only ACME HTTP-01 challenges via Cloudflare Tunnel.
    - `internal-gateway` (Internal): Handles all application traffic, exposed via MetalLB.
- **MetalLB**: Provides L2 LoadBalancer services within the Kind cluster.
- **Managed Docker Network**: A dedicated bridge network (`kind-shared`) ensures deterministic routing and visibility for host-to-cluster connectivity.
- **Cloudflare Tunnel**: Securely routes ACME challenges from the public internet to the cluster without opening inbound ports.

## Prerequisites

1.  **Kind**: Kubernetes-in-Docker.
2.  **Terraform**: For infrastructure orchestration.
3.  **docker-mac-net-connect**: (macOS) Required to route traffic from the host to the MetalLB LoadBalancer IPs.
    ```bash
    brew install chipmk/tap/docker-mac-net-connect
    sudo brew services start docker-mac-net-connect
    ```

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your Cloudflare credentials.

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `domain` | Your base domain (e.g., `example.com`) | - |
| `subdomain` | Subdomain for ops (e.g., `ops.example.com`) | - |
| `acme_issuer` | Use `letsencrypt-staging` or `letsencrypt-prod` | `letsencrypt-staging` |
| `acme_email` | Email for Let's Encrypt account | - |
| `docker_network_subnet` | Subnet for the shared bridge | `172.21.0.0/16` |
| `metallb_ip_range` | IP range for internal LoadBalancers | `172.21.255.200-250` |

## Usage

1.  **Deploy Infrastructure**:
    ```bash
    terraform init
    terraform apply
    ```

2.  **Verify Routing**:
    Ensure your Mac has a route to the `kind-shared` subnet:
    ```bash
    netstat -nr | grep 172.21
    ```

3.  **Access the Application**:
    The internal application is reachable via the `internal-gateway` IP:
    ```bash
    # Get the internal gateway IP
    kubectl get svc internal-ingress -n istio-system
    
    # Access via Curl (assuming hello.ops.example.com resolves to that IP)
    curl -k https://172.21.255.200 -H "Host: hello.ops.example.com"
    ```

## TLS Workflow

1.  `cert-manager` creates a `Challenge` resource.
2.  Istio routes the ACME token request from the public `*.ops.example.com` (via Cloudflare Tunnel) to the cert-manager solver.
3.  Once validated, the certificate is stored in a Kubernetes secret.
4.  Istio's `internal-gateway` uses this secret to provide TLS for internal clients.

---

### Switching to Production

To use production certificates, update your `terraform.tfvars`:
```hcl
acme_issuer = "letsencrypt-prod"
```
Then run `terraform apply`.
