resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "ops_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "ops-tunnel"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "ops_tunnel_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.ops_tunnel.id

  config {
    ingress_rule {
      hostname = "*.${var.subdomain}"
      service  = "http://istio-ingress.istio-system.svc.cluster.local:80"
    }
    ingress_rule {
      hostname = "*.${var.domain}"
      service  = "http://istio-ingress.istio-system.svc.cluster.local:80"
    }
    ingress_rule {
      service = "http_status:404"
    }
  }
}

resource "cloudflare_record" "ops_wildcard" {
  zone_id         = var.cloudflare_zone_id
  name            = "*.ops"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.ops_tunnel.id}.cfargotunnel.com"
  type            = "CNAME"
  proxied         = true
  allow_overwrite = true
}

# Deployment for cloudflared in the cluster
resource "kubernetes_secret" "tunnel_credentials" {
  metadata {
    name      = "tunnel-credentials"
    namespace = kubernetes_namespace.istio_system.metadata[0].name
  }

  data = {
    "credentials.json" = jsonencode({
      AccountTag   = var.cloudflare_account_id
      TunnelSecret = random_id.tunnel_secret.b64_std
      TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.ops_tunnel.id
    })
  }

  depends_on = [kind_cluster.default]
}

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.istio_system.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          args  = ["tunnel", "--config", "/etc/cloudflared/config/config.yaml", "run"]

          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared/config"
            read_only  = true
          }

          volume_mount {
            name       = "creds"
            mount_path = "/etc/cloudflared/creds"
            read_only  = true
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.cloudflared_config.metadata[0].name
          }
        }

        volume {
          name = "creds"
          secret {
            secret_name = kubernetes_secret.tunnel_credentials.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kind_cluster.default]
}

resource "kubernetes_config_map" "cloudflared_config" {
  metadata {
    name      = "cloudflared-config"
    namespace = kubernetes_namespace.istio_system.metadata[0].name
  }

  data = {
    "config.yaml" = <<EOT
tunnel: ${cloudflare_zero_trust_tunnel_cloudflared.ops_tunnel.id}
credentials-file: /etc/cloudflared/creds/credentials.json
metrics: 0.0.0.0:2000
no-autoupdate: true
ingress:
  - hostname: "*.${var.subdomain}"
    service: http://istio-ingress.istio-system.svc.cluster.local:80
  - hostname: "*.${var.domain}"
    service: http://istio-ingress.istio-system.svc.cluster.local:80
  - service: http_status:404
EOT
  }

  depends_on = [kind_cluster.default]
}
