# Multi-Cluster Vault-Kubernetes OIDC Integration

This project demonstrates a secure, automated integration between HashiCorp Vault and multiple Kubernetes (Kind) clusters using **JWT/OIDC-based authentication** and dynamic path-based policies.

## Features
- **Multi-Cluster Support**: Deploys two independent `kind` clusters and a central Vault instance.
- **OIDC Authentication**: Configures Vault as a consumer of Kubernetes OIDC discovery endpoints, eliminating the need for long-lived service account tokens for authentication.
- **Dynamic Policy Templating**: Uses dynamic Vault accessor IDs and JWT claim metadata to enforce cross-namespace secret isolation. 
- **Persistence**: Simulates persistent storage for Vault using local host-path volume mounts.
- **Automated Verification**: Deploys validation pods to verify that secrets can only be accessed by the correct identity in the correct namespace.

## Prerequisites
- [Docker](https://www.docker.com/)
- [Kind](https://kind.sigs.k8s.io/)
- [Terraform](https://www.terraform.io/)
- `kubectl`, `curl`, and `jq`

## Getting Started

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Deploy the Infrastructure**:
   ```bash
   terraform apply -auto-approve
   ```

3. **Verify Secret Isolation**:
   The validation pods in `ns-a` and `ns-b` automatically attempt to read their own secrets and each other's secrets. Check the logs:
   ```bash
   # Check logs for Pod in ns-a
   kubectl --context kind-cluster-1 -n ns-a logs vault-test-pod
   
   # Check logs for Pod in ns-b
   kubectl --context kind-cluster-1 -n ns-b logs vault-test-pod
   ```

## Architecture
- **Vault Backend**: KV-V2 enabled at `persona/`.
- **Auth Method**: `vault_jwt_auth_backend` pointing to cluster OIDC config at `/.well-known/openid-configuration`.
- **Policy**: `persona_policy` uses `{{identity.entity.aliases.<accessor>.metadata.persona_ns}}` for dynamic path matching.

## Cleanup
To destroy the infrastructure and clean up all resources:
```bash
terraform destroy -auto-approve
rm -rf vault_data/
```
