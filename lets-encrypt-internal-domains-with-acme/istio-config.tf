resource "helm_release" "ops_config" {
  name       = "ops-config"
  chart      = "./charts/ops-config"
  namespace  = "istio-system"
  
  # Ensure all infrastructure and CRD providers are ready
  depends_on = [
    kind_cluster.default,
    helm_release.istio_ingress,
    helm_release.internal_ingress,
    helm_release.cert_manager,
    helm_release.metallb
  ]

  set {
    name  = "domain"
    value = var.domain
  }

  set {
    name  = "subdomain"
    value = var.subdomain
  }

  set {
    name  = "metallb_ip_range"
    value = var.metallb_ip_range
  }

  set {
    name  = "email"
    value = var.acme_email
  }

  set {
    name  = "acme_issuer"
    value = var.acme_issuer
  }
}
