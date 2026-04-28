resource "kubernetes_service_account" "identity_manager" {
  provider = kubernetes.cluster1
  metadata {
    name      = "identity-manager"
    namespace = "default"
  }
}

resource "kubernetes_config_map" "identity_manager_script" {
  provider = kubernetes.cluster1
  metadata {
    name      = "identity-manager-script"
    namespace = "default"
  }

  data = {
    "rotate.sh" = <<-EOT
      #!/bin/sh
      set -e

      SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      VAULT_ADDR="http://vault:8200"

      # Login to Vault
      echo "Logging into Vault..."
      LOGIN_RESP=$(curl -s --request POST --data "{\"jwt\": \"$SA_TOKEN\", \"role\": \"identity-manager-role\"}" $VAULT_ADDR/v1/auth/oidc-cluster1/login)
      VAULT_TOKEN=$(echo $LOGIN_RESP | jq -r .auth.client_token)

      if [ "$VAULT_TOKEN" = "null" ]; then
        echo "Failed to login to Vault"
        exit 1
      fi

      rotate_keys() {
        NS=$1
        SA=$2
        TARGET_PATH="persona/data/$NS/$SA/identity"
        
        echo "Rotating keys for $NS/$SA..."
        
        # Get existing keys
        EXISTING=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" $VAULT_ADDR/v1/$TARGET_PATH)
        KEYS=$(echo $EXISTING | jq -r '.data.data.keys // []')
        
        # Generate new RSA key pair
        openssl genrsa -out /tmp/private.pem 2048
        openssl rsa -in /tmp/private.pem -pubout -out /tmp/public.pem
        
        KID=$(date +%s)
        PRIV=$(cat /tmp/private.pem | base64 | tr -d '\n')
        PUB=$(cat /tmp/public.pem | base64 | tr -d '\n')
        
        # Create new key object
        NEW_KEY="{\"kid\": \"$KID\", \"private_key\": \"$PRIV\", \"public_key\": \"$PUB\", \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
        
        # Append and keep only last 3
        UPDATED_KEYS=$(echo $KEYS | jq ". + [$NEW_KEY] | .[-3:]")
        
        # Write back to Vault
        curl -s -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
          --data "{\"data\": {\"keys\": $UPDATED_KEYS}}" \
          $VAULT_ADDR/v1/$TARGET_PATH > /dev/null
        
        echo "Successfully rotated keys for $NS/$SA. Active keys: $(echo $UPDATED_KEYS | jq '. | length')"
      }

      rotate_keys "ns-a" "test-sa"
      rotate_keys "ns-b" "test-sa"
    EOT
  }
}

resource "kubernetes_cron_job_v1" "identity_manager" {
  provider = kubernetes.cluster1
  metadata {
    name      = "identity-manager"
    namespace = "default"
  }
  spec {
    schedule = "*/5 * * * *" # Every 5 minutes for testing
    job_template {
      metadata {}
      spec {
        template {
          metadata {}
          spec {
            service_account_name = kubernetes_service_account.identity_manager.metadata[0].name
            container {
              name    = "manager"
              image   = "alpine:latest"
              command = ["/bin/sh", "-c", "apk add --no-cache curl jq openssl && sh /scripts/rotate.sh"]
              volume_mount {
                name       = "scripts"
                mount_path = "/scripts"
              }
            }
            volume {
              name = "scripts"
              config_map {
                name = kubernetes_config_map.identity_manager_script.metadata[0].name
              }
            }
            restart_policy = "OnFailure"
          }
        }
      }
    }
  }
}
