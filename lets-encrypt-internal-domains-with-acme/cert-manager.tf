resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
  depends_on = [kind_cluster.default]
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  version    = "v1.13.2"

  set {
    name  = "installCRDs"
    value = "true"
  }
  
  depends_on = [kind_cluster.default, kubernetes_namespace.cert_manager]
}
