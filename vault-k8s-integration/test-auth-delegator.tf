resource "kubernetes_service_account" "vault_auth1" {
  provider = kubernetes.cluster1
  metadata { name = "vault-auth" }
}
resource "kubernetes_secret" "vault_auth1" {
  provider = kubernetes.cluster1
  metadata {
    name = "vault-auth-token"
    annotations = { "kubernetes.io/service-account.name" = kubernetes_service_account.vault_auth1.metadata[0].name }
  }
  type = "kubernetes.io/service-account-token"
}
resource "kubernetes_cluster_role_binding" "vault_auth1" {
  provider = kubernetes.cluster1
  metadata { name = "vault-auth-delegator" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_auth1.metadata[0].name
    namespace = "default"
  }
}

resource "kubernetes_service_account" "vault_auth2" {
  provider = kubernetes.cluster2
  metadata { name = "vault-auth" }
}
resource "kubernetes_secret" "vault_auth2" {
  provider = kubernetes.cluster2
  metadata {
    name = "vault-auth-token"
    annotations = { "kubernetes.io/service-account.name" = kubernetes_service_account.vault_auth2.metadata[0].name }
  }
  type = "kubernetes.io/service-account-token"
}
resource "kubernetes_cluster_role_binding" "vault_auth2" {
  provider = kubernetes.cluster2
  metadata { name = "vault-auth-delegator" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "system:auth-delegator"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_auth2.metadata[0].name
    namespace = "default"
  }
}
