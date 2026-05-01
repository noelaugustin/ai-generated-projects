resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
  depends_on = [kind_cluster.default]
}

resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = kubernetes_namespace.metallb_system.metadata[0].name
  version    = "0.13.12"

  timeout = 600
  depends_on = [kind_cluster.default, kubernetes_namespace.metallb_system]
}

resource "helm_release" "metallb_config" {
  name       = "metallb-config"
  chart      = "./charts/metallb-config"
  namespace  = kubernetes_namespace.metallb_system.metadata[0].name
  
  depends_on = [helm_release.metallb]

  set {
    name  = "metallb_ip_range"
    value = var.metallb_ip_range
  }
}
