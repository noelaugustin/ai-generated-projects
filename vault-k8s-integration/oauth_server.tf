resource "kubernetes_service_account" "oauth_server" {
  provider = kubernetes.cluster1
  metadata {
    name      = "oauth-server"
    namespace = "default"
  }
}

resource "kubernetes_config_map" "oauth_server_script" {
  provider = kubernetes.cluster1
  metadata {
    name      = "oauth-server-script"
    namespace = "default"
  }

  data = {
    "server.py" = <<-EOT
import http.server
import json
import jwt
import requests
import base64
from cryptography.hazmat.primitives import serialization

VAULT_ADDR = "http://vault:8200"

# Get Vault Token
with open("/var/run/secrets/kubernetes.io/serviceaccount/token", "r") as f:
    sa_token = f.read()

resp = requests.post(f"{VAULT_ADDR}/v1/auth/oidc-cluster1/login", json={"jwt": sa_token, "role": "oauth-server-role"})
vault_token = resp.json()["auth"]["client_token"]

class OAuthHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/token":
            length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(length).decode('utf-8')
            params = json.loads(post_data)
            
            assertion = params.get("client_assertion")
            
            try:
                # Decode without verification to get headers/claims
                unverified = jwt.decode(assertion, options={"verify_signature": False})
                ns = unverified.get("namespace")
                sa = unverified.get("service_account")
                
                # Fetch public keys from Vault
                v_resp = requests.get(
                    f"{VAULT_ADDR}/v1/persona/data/{ns}/{sa}/identity",
                    headers={"X-Vault-Token": vault_token}
                )
                keys = v_resp.json()["data"]["data"]["keys"]
                
                # Try verifying with each key
                verified = False
                for k in keys:
                    pub_key_pem = base64.b64decode(k["public_key"]).decode()
                    try:
                        jwt.decode(assertion, pub_key_pem, algorithms=["RS256"], audience="oauth-server")
                        verified = True
                        break
                    except:
                        continue
                
                if verified:
                    token = jwt.encode({"sub": f"system:serviceaccount:{ns}:{sa}", "exp": 3600}, "secret-key", algorithm="HS256")
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    self.wfile.write(json.dumps({"access_token": token, "token_type": "Bearer"}).encode())
                else:
                    self.send_error(401, "Invalid signature")
            except Exception as e:
                self.send_error(400, str(e))

server = http.server.HTTPServer(('0.0.0.0', 8080), OAuthHandler)
print("OAuth Server starting on 8080...")
server.serve_forever()
EOT
  }
}

resource "kubernetes_deployment" "oauth_server" {
  provider = kubernetes.cluster1
  metadata {
    name      = "oauth-server"
    namespace = "default"
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "oauth-server" }
    }
    template {
      metadata {
        labels = { app = "oauth-server" }
      }
      spec {
        service_account_name = kubernetes_service_account.oauth_server.metadata[0].name
        container {
          name    = "oauth-server"
          image   = "python:3.9-slim"
          command = ["/bin/sh", "-c", "pip install PyJWT cryptography requests && python -u /scripts/server.py"]
          port {
            container_port = 8080
          }
          volume_mount {
            name       = "scripts"
            mount_path = "/scripts"
          }
        }
        volume {
          name = "scripts"
          config_map {
            name = kubernetes_config_map.oauth_server_script.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "oauth_server" {
  provider = kubernetes.cluster1
  metadata {
    name      = "oauth-server"
    namespace = "default"
  }
  spec {
    selector = { app = "oauth-server" }
    port {
      port        = 80
      target_port = 8080
    }
  }
}
