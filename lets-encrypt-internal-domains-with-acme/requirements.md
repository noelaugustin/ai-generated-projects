1.  **Terraform-Based**: Orchestrate all infrastructure (Kind, Helm, Cloudflare) via Terraform.
1.  **Kind Cluster**: Use local Kind clusters for development and testing.
1.  **Cloudflare Tunnel**: Use `cloudflared` to bridge external ACME challenges to the internal cluster without exposing ports.
1.  **Centralized Certificate Management**: All `Certificate` resources and TLS secrets are held in the `istio-system` namespace.
1.  **Dual-Gateway Architecture (Centralized)**: 
    *   **External Gateway (`ops-gateway`)**: Dedicated to Cloudflare Tunnel traffic; strictly limited to ACME HTTP-01 challenges. Located in `istio-system`.
    *   **Internal Gateway (`internal-gateway`)**: Dedicated to internal network traffic; handles TLS termination for all applications. Located in `istio-system`.
1.  **ACME HTTP-01 Challenges**: Use Let's Encrypt with HTTP-01 validation.
1.  **Solver Aggregator Pattern**: Implement a mesh-wide service (`acme-solver-aggregator` in `istio-system`) that aggregates ACME solver pods across namespaces.
1.  **Internal Exposure**: Expose the internal gateway via a `ClusterIP` service, making it reachable from the host Mac using tools like `chipmk/tap/docker-mac-net-connect`.
1.  **Flattened Nested Wildcards**: Use `*.ops.example.com` (proxied) for the tunnel to support nested internal hosts.
1.  **Specific Host Certificates**: issue distinct certificates for each host (e.g., `hello.ops.example.com`).
1.  **Strict Security**: External gateway rejects all traffic not matching `/.well-known/acme-challenge/`.
1.  **Infrastructure as Code**: No manual scripts or Makefiles.