# Populate secrets in vault for the test personas
resource "vault_kv_secret_v2" "ns_a_sa_secret" {
  depends_on = [vault_mount.persona]
  mount      = vault_mount.persona.path
  name       = "ns-a/test-sa/secret1"
  data_json  = jsonencode({
    "secret_value" = "hello-from-ns-a"
  })
}

resource "vault_kv_secret_v2" "ns_b_sa_secret" {
  depends_on = [vault_mount.persona]
  mount      = vault_mount.persona.path
  name       = "ns-b/test-sa/secret1"
  data_json  = jsonencode({
    "secret_value" = "hello-from-ns-b"
  })
}

# Namespace a
resource "kubernetes_namespace" "ns_a" {
  provider = kubernetes.cluster1
  metadata { name = "ns-a" }
}

resource "kubernetes_service_account" "ns_a_sa" {
  provider = kubernetes.cluster1
  metadata {
    name      = "test-sa"
    namespace = kubernetes_namespace.ns_a.metadata[0].name
  }
}

resource "kubernetes_pod" "test_pod_a" {
  provider = kubernetes.cluster1
  metadata {
    name      = "vault-test-pod"
    namespace = kubernetes_namespace.ns_a.metadata[0].name
  }

  spec {
    service_account_name = kubernetes_service_account.ns_a_sa.metadata[0].name
    container {
      name    = "test"
      image   = "python:3.9-slim"
      command = ["/bin/sh", "-c", "pip install PyJWT cryptography requests && python -u /scripts/client.py"]
      volume_mount {
        name       = "scripts"
        mount_path = "/scripts"
      }
    }
    volume {
      name = "scripts"
      config_map {
        name = kubernetes_config_map.test_scripts_a.metadata[0].name
      }
    }
  }
}

resource "kubernetes_config_map" "test_scripts_a" {
  provider = kubernetes.cluster1
  metadata {
    name      = "test-scripts"
    namespace = kubernetes_namespace.ns_a.metadata[0].name
  }
  data = {
    "client.py" = <<-EOT
print("Starting Client Script...")
import jwt
import requests
import time
import base64
import os

VAULT_ADDR = "http://vault.default.svc.cluster.local:8200"
OAUTH_ADDR = "http://oauth-server.default.svc.cluster.local"

# 1. Login to Vault
with open("/var/run/secrets/kubernetes.io/serviceaccount/token", "r") as f:
    sa_token = f.read()

print("Logging into Vault...")
resp = requests.post(f"{VAULT_ADDR}/v1/auth/oidc-cluster1/login", json={"jwt": sa_token, "role": "persona-role"})
vault_token = resp.json()["auth"]["client_token"]
ns = resp.json()["auth"]["metadata"]["persona_ns"]
sa = resp.json()["auth"]["metadata"]["persona_sa"]

print(f"Authenticated as {ns}/{sa}")

# 2. Fetch Identity Keys
print("Fetching identity keys from Vault...")
v_resp = requests.get(
    f"{VAULT_ADDR}/v1/persona/data/{ns}/{sa}/identity",
    headers={"X-Vault-Token": vault_token}
)
if v_resp.status_code != 200:
    print(f"Error fetching keys: {v_resp.text}")
    time.sleep(3600)

keys = v_resp.json()["data"]["data"]["keys"]
latest_key = keys[-1]
priv_key_pem = base64.b64decode(latest_key["private_key"]).decode()

# 3. Sign Client Assertion
print("Signing client assertion...")
assertion = jwt.encode({
    "namespace": ns,
    "service_account": sa,
    "aud": "oauth-server",
    "exp": time.time() + 60,
    "iat": time.time()
}, priv_key_pem, algorithm="RS256")

# 4. Exchange for Access Token
print("Exchanging for Access Token...")
o_resp = requests.post(f"{OAUTH_ADDR}/token", json={"client_assertion": assertion})
if o_resp.status_code == 200:
    print("SUCCESS: Got Access Token!")
    print(o_resp.json())
else:
    print(f"FAILED: {o_resp.status_code} - {o_resp.text}")

time.sleep(3600)
EOT
  }
}

# Namespace b
resource "kubernetes_namespace" "ns_b" {
  provider = kubernetes.cluster1
  metadata { name = "ns-b" }
}

resource "kubernetes_service_account" "ns_b_sa" {
  provider = kubernetes.cluster1
  metadata {
    name      = "test-sa"
    namespace = kubernetes_namespace.ns_b.metadata[0].name
  }
}

resource "kubernetes_pod" "test_pod_b" {
  provider = kubernetes.cluster1
  metadata {
    name      = "vault-test-pod"
    namespace = kubernetes_namespace.ns_b.metadata[0].name
  }

  spec {
    service_account_name = kubernetes_service_account.ns_b_sa.metadata[0].name
    container {
      name    = "test"
      image   = "python:3.9-slim"
      command = ["/bin/sh", "-c", "pip install PyJWT cryptography requests && python -u /scripts/client.py"]
      volume_mount {
        name       = "scripts"
        mount_path = "/scripts"
      }
    }
    volume {
      name = "scripts"
      config_map {
        name = kubernetes_config_map.test_scripts_b.metadata[0].name
      }
    }
  }
}

resource "kubernetes_config_map" "test_scripts_b" {
  provider = kubernetes.cluster1
  metadata {
    name      = "test-scripts"
    namespace = kubernetes_namespace.ns_b.metadata[0].name
  }
  data = kubernetes_config_map.test_scripts_a.data
}
