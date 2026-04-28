resource "vault_mount" "persona" {
  depends_on = [time_sleep.wait_for_vault]
  path        = "persona"
  type        = "kv"
  options     = { version = "2" }
  description = "KV secrets engine for personas"
}

# Cluster 1 JWT/OIDC Auth
resource "vault_jwt_auth_backend" "cluster1" {
  depends_on         = [time_sleep.wait_for_vault]
  path               = "oidc-cluster1"
  type               = "jwt"
  jwks_url           = "https://cluster-1-control-plane:6443/openid/v1/jwks"
  jwks_ca_pem        = kind_cluster.cluster1.cluster_ca_certificate
  bound_issuer       = "https://kubernetes.default.svc.cluster.local"
}

resource "vault_jwt_auth_backend_role" "cluster1_persona_role" {
  backend         = vault_jwt_auth_backend.cluster1.path
  role_name       = "persona-role"
  token_policies  = [vault_policy.persona_policy.name]
  bound_audiences = ["https://kubernetes.default.svc.cluster.local", "vault"]
  user_claim      = "sub"
  role_type       = "jwt"
  
  claim_mappings = {
    "/kubernetes.io/namespace"            = "persona_ns"
    "/kubernetes.io/serviceaccount/name"  = "persona_sa"
  }
}

# Cluster 2 JWT/OIDC Auth
resource "vault_jwt_auth_backend" "cluster2" {
  depends_on         = [time_sleep.wait_for_vault]
  path               = "oidc-cluster2"
  type               = "jwt"
  jwks_url           = "https://cluster-2-control-plane:6443/openid/v1/jwks"
  jwks_ca_pem        = kind_cluster.cluster2.cluster_ca_certificate
  bound_issuer       = "https://kubernetes.default.svc.cluster.local"
}

resource "vault_jwt_auth_backend_role" "cluster2_persona_role" {
  backend         = vault_jwt_auth_backend.cluster2.path
  role_name       = "persona-role"
  token_policies  = [vault_policy.persona_policy.name]
  bound_audiences = ["https://kubernetes.default.svc.cluster.local", "vault"]
  user_claim      = "sub"
  role_type       = "jwt"
  
  claim_mappings = {
    "/kubernetes.io/namespace"            = "persona_ns"
    "/kubernetes.io/serviceaccount/name"  = "persona_sa"
  }
}

resource "vault_policy" "persona_policy" {
  depends_on = [time_sleep.wait_for_vault]
  name = "persona_policy"
  policy = <<EOT
# Access for Cluster 1
path "persona/data/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster1.accessor}.metadata.persona_ns}}/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster1.accessor}.metadata.persona_sa}}/*" {
  capabilities = ["read", "list"]
}
path "persona/data/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster1.accessor}.metadata.persona_ns}}/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster1.accessor}.metadata.persona_sa}}" {
  capabilities = ["read", "list"]
}

# Access for Cluster 2
path "persona/data/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster2.accessor}.metadata.persona_ns}}/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster2.accessor}.metadata.persona_sa}}/*" {
  capabilities = ["read", "list"]
}
path "persona/data/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster2.accessor}.metadata.persona_ns}}/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster2.accessor}.metadata.persona_sa}}" {
  capabilities = ["read", "list"]
}

# Listing access
path "persona/metadata/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster1.accessor}.metadata.persona_ns}}/*" {
  capabilities = ["list"]
}
path "persona/metadata/{{identity.entity.aliases.${vault_jwt_auth_backend.cluster2.accessor}.metadata.persona_ns}}/*" {
}
EOT
}

resource "vault_policy" "identity_manager_policy" {
  depends_on = [time_sleep.wait_for_vault]
  name = "identity_manager_policy"
  policy = <<EOT
path "persona/data/*" {
  capabilities = ["create", "update", "patch", "read", "list"]
}
path "persona/metadata/*" {
  capabilities = ["read", "list", "delete"]
}
EOT
}

# Role for Identity Manager (assuming it runs in default namespace as 'identity-manager')
resource "vault_jwt_auth_backend_role" "identity_manager_role" {
  backend         = vault_jwt_auth_backend.cluster1.path
  role_name       = "identity-manager-role"
  token_policies  = [vault_policy.identity_manager_policy.name]
  bound_audiences = ["https://kubernetes.default.svc.cluster.local", "vault"]
  user_claim      = "sub"
  role_type       = "jwt"
  
  bound_claims = {
    "/kubernetes.io/serviceaccount/name" = "identity-manager"
  }
}

resource "vault_policy" "oauth_server_policy" {
  depends_on = [time_sleep.wait_for_vault]
  name = "oauth_server_policy"
  policy = <<EOT
# OAuth server needs to see public keys
path "persona/data/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_jwt_auth_backend_role" "oauth_server_role" {
  backend         = vault_jwt_auth_backend.cluster1.path
  role_name       = "oauth-server-role"
  token_policies  = [vault_policy.oauth_server_policy.name]
  bound_audiences = ["https://kubernetes.default.svc.cluster.local", "vault"]
  user_claim      = "sub"
  role_type       = "jwt"
  
  bound_claims = {
    "/kubernetes.io/serviceaccount/name" = "oauth-server"
  }
}
