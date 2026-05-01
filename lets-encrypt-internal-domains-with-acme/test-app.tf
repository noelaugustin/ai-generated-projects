resource "kubernetes_namespace" "hello_world" {
  metadata {
    name = "hello-world"
  }
}

resource "kubernetes_deployment" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hello_world.metadata[0].name
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "hello-world"
      }
    }
    template {
      metadata {
        labels = {
          app = "hello-world"
        }
      }
      spec {
        container {
          name  = "hello-world"
          image = "paulbouwer/hello-kubernetes:1.10"
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "hello_world" {
  metadata {
    name      = "hello-world"
    namespace = kubernetes_namespace.hello_world.metadata[0].name
  }
  spec {
    selector = {
      app = "hello-world"
    }
    port {
      port        = 80
      target_port = 8080
    }
  }
}

# Certificate and VirtualService moved to local Helm chart in istio-config.tf
