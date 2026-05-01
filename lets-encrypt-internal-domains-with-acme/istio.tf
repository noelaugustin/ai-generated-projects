resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
  }
  depends_on = [kind_cluster.default]
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "1.19.3"
  depends_on = [kind_cluster.default, kubernetes_namespace.istio_system]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "1.19.3"
  depends_on = [helm_release.istio_base]

  set {
    name  = "meshConfig.ingressClass"
    value = "istio"
  }

  set {
    name  = "meshConfig.ingressSelector"
    value = "ingress"
  }
}

resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "1.19.3"
  depends_on = [helm_release.istiod]

  set {
    name  = "service.type"
    value = "ClusterIP"
  }

  set {
    name  = "labels.istio"
    value = "ingress"
  }
}

resource "helm_release" "internal_ingress" {
  name       = "internal-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = "1.19.3"
  depends_on = [helm_release.istiod]

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "labels.istio"
    value = "internal-ingress"
  }
}
