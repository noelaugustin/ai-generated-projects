# Requirements: Istio Ambient & HashiCorp Vault PKI Local Integration

You are a Principal Platform/DevOps Engineer. Your task is to design, implement, and codify a fully local Kubernetes development playground using Terraform to integrate **Istio in Ambient Mode** with **HashiCorp Vault (OpenBao)** as an external, Docker-based Certificate Authority (CA).

This project must run entirely locally, be completely codified in Terraform (where applicable), and be isolated from the public internet.

---

## 1. High-Level Requirements

*   **Runtime Environment**: Docker-based local setup.
*   **Kubernetes Cluster**: A local Kubernetes cluster managed via **Kind** (Kubernetes in Docker).
*   **External CA / Secrets Management**: A Docker container running HashiCorp Vault (OpenBao) running *outside* of the Kubernetes cluster.
*   **Helm Deployment Standard**: All Kubernetes tooling (MetalLB, cert-manager, istio-csr, Istio Base, Istio CNI, Istiod, and Ztunnel) **must** be deployed using their official Helm charts, rather than using custom raw manifests.
*   **Load Balancing**: **MetalLB** deployed inside Kind to assign external IPs to Kubernetes Gateways.
*   **Certificate Provisioning**: **cert-manager** inside the cluster to handle Gateway TLS certificates.
*   **Workload mTLS (Istio CA)**: **istio-csr** to intercept and forward workload certificate requests to Vault instead of using Istio's built-in self-signed CA.
*   **Service Mesh**: **Istio Ambient Mode** (sidecar-less architecture) installed in the cluster.
*   **Application Ingress**: Expose a mock application (`httpbin`) through a Gateway API `Gateway` terminated by a certificate issued from Vault, supporting traffic for 5 subdomains (`app1` through `app5`).
*   **Local Access and DNS**: DNS and network routing to allow access to both Vault and the applications directly from the host system using domain names.

---

## 2. Infrastructure Architecture & Setup Details

### A. Networking & DNS
1.  **Docker Network**: Create a custom Docker network (e.g. `mesh-network` on `10.10.0.0/16`). Both the Kind cluster nodes and the external Vault container must run on this network.
2.  **DNS Patching**: CoreDNS inside Kubernetes must be patched so that pods can resolve `vault.ops.<ROOT_DOMAIN>` to the Vault container's static IP (e.g., `10.10.0.10`).
3.  **Host Access**: Document host-to-container network routing for macOS/Windows/Linux (such as `docker-mac-net-connect` for macOS) and `/etc/hosts` configurations mapping `vault.ops.<ROOT_DOMAIN>` and application subdomains (`app[1-5].ops.<ROOT_DOMAIN>`) to their respective IPs.

### B. HashiCorp Vault (OpenBao) CA Bootstrap Order
To boot Vault securely over HTTPS, follow a multi-step bootstrap flow:
1.  **Stage 1 (HTTP Initial Boot)**: Launch the container listening on HTTP (port 80) using temporary self-signed dummy certificates for the HTTPS listener.
2.  **Stage 2 (Initialization & Unsealing)**: Wait for the API to respond, initialize and unseal the vault, and export the generated Unseal Key and Root Token to a local folder (e.g., `certs/`).
3.  **Stage 3 (PKI Engine Configuration)**:
    *   Enable the PKI engine for Root CA (e.g., `pki_root`) and generate a root certificate for `<ROOT_DOMAIN>`.
    *   Enable PKI engines for Intermediate CAs (e.g., `pki` for server certs, and `pki_istio` for workload certs).
    *   Generate intermediate CSRs, sign them with the Root CA, and import the signed intermediate certificate chains back into the intermediate engines.
    *   Configure roles (e.g., allow wildcard subdomains, enforce SAN requirements, and configure `key_type = "any"` to allow ECDSA/EC keys used by Istio).
4.  **Stage 4 (Self-Issue & HTTPS Reload)**: Issue a TLS server certificate for `vault.ops.<ROOT_DOMAIN>` from the server intermediate CA. Write this certificate and key to the configuration paths of the Vault container and send a `SIGHUP` to the Vault process to dynamically reload and begin serving traffic over HTTPS (port 443) without losing state.

### C. Load Balancing (MetalLB)
*   Deploy MetalLB inside the cluster.
*   Configure an `IPAddressPool` with a range of IPs on the same Docker subnet (e.g., `10.10.0.100` to `10.10.0.250`).
*   Deploy a Layer 2 Advertisement (`L2Advertisement`) to map external requests to Kind node interfaces.

### D. cert-manager & ClusterIssuers
*   Install `cert-manager` inside Kubernetes (with CRDs enabled).
*   Enable the AppRole auth method in Vault. Create a `cert-manager` policy allowing cert signing, define a role, and generate a `role_id` and `secret_id` stored inside a Kubernetes Secret.
*   Configure two `ClusterIssuer` resources (`vault-issuer` and `vault-issuer-istio`) that talk to Vault using the AppRole credentials. Configure them with the Root CA `caBundle` so they trust the Vault HTTPS endpoint.

### E. istio-csr (cert-manager-istio-csr)
*   Deploy `istio-csr` in the `cert-manager` namespace.
*   Configure it to use the `vault-issuer-istio` ClusterIssuer as its backend CA.
*   **Ambient Mode Authorization**: In Istio Ambient mode, node-level proxies (`ztunnel`) request certificates on behalf of the workloads on their node. You **must** set the `app.server.caTrustedNodeAccounts` Helm configuration to trust the ztunnel service accounts (e.g., `istio-system/ztunnel,kube-system/ztunnel`) to allow this impersonation.
*   Use version `v0.12.0` or higher to ensure compatibility with `caTrustedNodeAccounts`.

### F. Istio Ambient Mode Installation
*   Install `istio-base`, `istio-cni`, `istiod` (control plane), and `ztunnel` (node agent) using Helm.
*   Configure `istiod` to disable its internal CA server (`pilot.env.ENABLE_CA_SERVER = false`) and set its CA address (`global.caAddress`) to point to `cert-manager-istio-csr.cert-manager.svc:443`.
*   Configure `ztunnel`'s Helm chart setting the `caAddress` to `cert-manager-istio-csr.cert-manager.svc:443`.

### G. Application & Gateway API Routing
*   Deploy `httpbin` to a namespace (e.g. `apps`) labeled for Ambient mode redirection (`istio.io/dataplane-mode=ambient`).
*   Deploy a cert-manager `Certificate` requesting wildcard SANs (`app1` through `app5` subdomains) from the `vault-issuer` ClusterIssuer.
*   Deploy a Gateway API `Gateway` resource using class `istio`, listening on port 443 (HTTPS), terminating TLS with the cert-manager issued certificate.
*   Deploy an `HTTPRoute` mapping traffic from subdomains `app[1-5].ops.<ROOT_DOMAIN>` to the `httpbin` service.

---

## 3. Testing & Verification

Write an automated shell verification script (`tests/verify-tls.sh`) that validates the setup:
1.  **Forced Domain Environment**: Force the script to require the `ROOT_DOMAIN` environment variable (e.g., `export ROOT_DOMAIN="yourdomain.com"`). Fail and exit with code `1` if it is not set.
2.  **Verify Vault TLS**: Retrieve the Root CA certificate from the Vault container. Use `curl` with the `--cacert` flag to query Vault's HTTPS API health endpoint (`https://vault.ops.$ROOT_DOMAIN:443/v1/sys/health`) using host resolution. It must verify successfully without TLS warnings.
3.  **Verify Application Routes**: Query each of the 5 application subdomains (`https://app[1-5].ops.$ROOT_DOMAIN/get`) using `curl` and the Vault Root CA. The requests must successfully route to `httpbin` and verify the TLS chain successfully.
4.  **Comments**: The script must contain comments explaining each scenario and assertion being tested.

---

## 4. Documentation Requirements
Provide a complete architectural overview document (`ARCHITECTURE.md`) detailing how components communicate and a local setup guide (`validation.md`) so a Junior SRE can configure local machine networking, hosts records, trust the Root CA, and debug connections step-by-step.