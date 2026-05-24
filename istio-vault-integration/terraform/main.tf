terraform {
  required_providers {
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.2.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25.0"
    }
  }
}

# --- 2. OpenBao Infrastructure ---

provider "docker" {}

locals {
  network_name   = "mesh-network"
  network_subnet = "10.10.0.0/16"
  has_token      = fileexists("${path.module}/../certs/vault_terraform_token.txt")
}

resource "null_resource" "mesh_network" {
  triggers = {
    subnet = local.network_subnet
    name   = local.network_name
  }

  provisioner "local-exec" {
    command = <<EOF
      existing_subnet=$(docker network inspect ${local.network_name} -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)
      if [ -n "$existing_subnet" ]; then
        if [ "$existing_subnet" = "${local.network_subnet}" ]; then
          echo "Network ${local.network_name} already exists with correct subnet. Continuing..."
        else
          echo "Network ${local.network_name} exists but with wrong subnet ($existing_subnet). Recreating..."
          containers=$(docker network inspect ${local.network_name} -f '{{range $k, $v := .Containers}}{{$k}} {{end}}' 2>/dev/null || true)
          for container in $containers; do
            docker network disconnect -f ${local.network_name} $container || true
          done
          docker network rm ${local.network_name}
          docker network create --subnet=${local.network_subnet} ${local.network_name}
        fi
      else
        echo "Network ${local.network_name} does not exist. Creating..."
        docker network create --subnet=${local.network_subnet} ${local.network_name}
      fi
    EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOF
      containers=$(docker network inspect ${self.triggers.name} -f '{{range $k, $v := .Containers}}{{$k}} {{end}}' 2>/dev/null || true)
      for container in $containers; do
        docker network disconnect -f ${self.triggers.name} $container || true
      done
      docker network rm ${self.triggers.name} || true
    EOF
  }
}

resource "docker_image" "openbao" {
  name         = "hashicorp/vault:1.15.4"
  keep_locally = true
}


# --- Dummy Certificates for Vault Bootstrap ---
resource "tls_private_key" "dummy" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "dummy" {
  private_key_pem = tls_private_key.dummy.private_key_pem

  subject {
    common_name  = "dummy.vault.local"
    organization = "Dummy"
  }

  validity_period_hours = 1
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "docker_volume" "vault_data" {
  name = "vault-data"
}

resource "docker_container" "openbao" {
  name  = "openbao"
  image = docker_image.openbao.image_id

  depends_on = [null_resource.mesh_network]

  ports {
    internal = 80
    external = 8200
    ip       = "127.0.0.1"
  }

  ports {
    internal = 443
    external = 8201
    ip       = "127.0.0.1"
  }

  lifecycle {
    ignore_changes = [entrypoint, env]
  }

  networks_advanced {
    name         = local.network_name
    ipv4_address = "10.10.0.10"
  }

  capabilities { add = ["IPC_LOCK"] }

  volumes {
    volume_name    = docker_volume.vault_data.name
    container_path = "/vault/file"
  }

  upload {
    file    = "/vault/config/config.hcl"
    content = <<-EOT
      storage "file" {
        path = "/vault/file"
      }
      listener "tcp" {
        address     = "0.0.0.0:80"
        tls_disable = 1
      }
      listener "tcp" {
        address       = "0.0.0.0:443"
        tls_cert_file = "/vault/config/vault-chain.crt"
        tls_key_file  = "/vault/config/vault.key"
      }
      ui = true
      disable_mlock = true
    EOT
  }

  upload {
    file    = "/vault/config/vault-chain.crt"
    content = tls_self_signed_cert.dummy.cert_pem
  }

  upload {
    file    = "/vault/config/vault.key"
    content = tls_private_key.dummy.private_key_pem
  }

  env = [
    "VAULT_ADDR=http://10.10.0.10:80"
  ]
  command = ["server"]
}

resource "null_resource" "vault_bootstrap" {
  depends_on = [docker_container.openbao]

  triggers = {
    container_id = docker_container.openbao.id
  }

  provisioner "local-exec" {
    command = <<EOF
      mkdir -p ../certs
      # Strip any trailing newlines from existing files
      for f in ../certs/*.txt; do
        if [ -f "$f" ]; then
          content=$(tr -d '\r\n' < "$f")
          printf "%s" "$content" > "$f"
        fi
      done

      # Wait for Vault to start
      echo "Waiting for Vault to start..."
      for i in {1..30}; do
        if curl -s http://127.0.0.1:8200/v1/sys/init > /dev/null; then
          break
        fi
        sleep 2
      done

      # Check if Vault is initialized
      init_status=$(curl -s http://127.0.0.1:8200/v1/sys/init)
      is_initialized=$(echo "$init_status" | jq -r '.initialized')

      if [ "$is_initialized" = "false" ]; then
        echo "Vault is not initialized. Initializing..."
        init_response=$(curl -s -X POST -d '{"secret_shares":1, "secret_threshold":1}' http://127.0.0.1:8200/v1/sys/init)
        
        unseal_key=$(echo "$init_response" | jq -r '.keys_base64[0]')
        root_token=$(echo "$init_response" | jq -r '.root_token')

        printf "%s" "$unseal_key" > ../certs/vault_unseal_key.txt
        printf "%s" "$root_token" > ../certs/vault_root_token.txt

        # Unseal Vault
        curl -s -X POST -d "{\"key\": \"$unseal_key\"}" http://127.0.0.1:8200/v1/sys/unseal

        # Create Terraform token
        token_response=$(curl -s -H "X-Vault-Token: $root_token" -X POST -d '{"policies": ["root"], "ttl": "768h", "renewable": true}' http://127.0.0.1:8200/v1/auth/token/create)
        terraform_token=$(echo "$token_response" | jq -r '.auth.client_token')
        printf "%s" "$terraform_token" > ../certs/vault_terraform_token.txt
        echo "Vault initialized and bootstrapped successfully."
      else
        echo "Vault is already initialized."
        # If the unseal key exists, unseal Vault
        if [ -f ../certs/vault_unseal_key.txt ]; then
          echo "Unsealing Vault..."
          unseal_key=$(cat ../certs/vault_unseal_key.txt)
          curl -s -X POST -d "{\"key\": \"$unseal_key\"}" http://127.0.0.1:8200/v1/sys/unseal
          
          # If terraform token is missing but root token exists, create it
          if [ ! -f ../certs/vault_terraform_token.txt ] && [ -f ../certs/vault_root_token.txt ]; then
            echo "Creating missing Terraform token..."
            root_token=$(cat ../certs/vault_root_token.txt)
            token_response=$(curl -s -H "X-Vault-Token: $root_token" -X POST -d '{"policies": ["root"], "ttl": "768h", "renewable": true}' http://127.0.0.1:8200/v1/auth/token/create)
            terraform_token=$(echo "$token_response" | jq -r '.auth.client_token')
            printf "%s" "$terraform_token" > ../certs/vault_terraform_token.txt
          fi
        else
          echo "Error: Vault is initialized but unseal key is missing on host!"
          echo "Resetting Vault to force re-initialization..."
          docker rm -f openbao || true
          docker volume rm vault-data || true
          exit 1
        fi
      fi
    EOF
  }
}

provider "vault" {
  address         = "http://127.0.0.1:8200"
  skip_tls_verify = true
  token           = local.has_token ? file("${path.module}/../certs/vault_terraform_token.txt") : (null_resource.vault_bootstrap.id != "" ? (fileexists("${path.module}/../certs/vault_terraform_token.txt") ? file("${path.module}/../certs/vault_terraform_token.txt") : "") : "")
}

resource "vault_auth_backend" "approle" {
  depends_on = [null_resource.vault_bootstrap]
  type       = "approle"
}

resource "vault_mount" "pki_root" {
  depends_on                = [null_resource.vault_bootstrap]
  path                      = "pki_root"
  type                      = "pki"
  default_lease_ttl_seconds = 315360000
  max_lease_ttl_seconds     = 315360000
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend      = vault_mount.pki_root.path
  type         = "internal"
  common_name  = "${var.root_domain} Root CA"
  ttl          = "315360000s"
  organization = "Ratlab"
  ou           = "Root CA"
}

resource "vault_mount" "pki" {
  depends_on                = [null_resource.vault_bootstrap]
  path                      = "pki"
  type                      = "pki"
  default_lease_ttl_seconds = 157680000
  max_lease_ttl_seconds     = 157680000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "int" {
  backend      = vault_mount.pki.path
  type         = "internal"
  common_name  = "ops.${var.root_domain} CA"
  organization = "Ratlab"
  ou           = "Ops CA"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "root_sign" {
  backend      = vault_mount.pki_root.path
  csr          = vault_pki_secret_backend_intermediate_cert_request.int.csr
  common_name  = "ops.${var.root_domain} CA"
  ttl          = "157680000s"
  organization = "Ratlab"
  ou           = "Ops CA"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "int_signed" {
  backend     = vault_mount.pki.path
  certificate = "${vault_pki_secret_backend_root_sign_intermediate.root_sign.certificate}\n${vault_pki_secret_backend_root_cert.root.certificate}"
}

resource "vault_mount" "pki_istio" {
  depends_on                = [null_resource.vault_bootstrap]
  path                      = "pki_istio"
  type                      = "pki"
  default_lease_ttl_seconds = 157680000
  max_lease_ttl_seconds     = 157680000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "istio" {
  backend      = vault_mount.pki_istio.path
  type         = "internal"
  common_name  = "istio.${var.root_domain} CA"
  organization = "Ratlab"
  ou           = "Istio CA"
}

resource "vault_pki_secret_backend_root_sign_intermediate" "root_sign_istio" {
  backend      = vault_mount.pki_root.path
  csr          = vault_pki_secret_backend_intermediate_cert_request.istio.csr
  common_name  = "istio.${var.root_domain} CA"
  ttl          = "157680000s"
  organization = "Ratlab"
  ou           = "Istio CA"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "istio_signed" {
  backend     = vault_mount.pki_istio.path
  certificate = "${vault_pki_secret_backend_root_sign_intermediate.root_sign_istio.certificate}\n${vault_pki_secret_backend_root_cert.root.certificate}"
}



resource "vault_policy" "cert_manager" {
  name   = "cert-manager"
  policy = <<EOT
path "pki/sign/istio" {
  capabilities = ["create", "update"]
}
path "pki_istio/sign/istio" {
  capabilities = ["create", "update"]
}
EOT
}

# AppRole for Cert-Manager
resource "vault_approle_auth_backend_role" "cert_manager" {
  backend        = vault_auth_backend.approle.path
  role_name      = "cert-manager"
  token_policies = [vault_policy.cert_manager.name]
}

resource "vault_approle_auth_backend_role_secret_id" "cert_manager" {
  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.cert_manager.role_name
}

resource "vault_pki_secret_backend_role" "istio" {
  depends_on       = [vault_pki_secret_backend_intermediate_set_signed.istio_signed]
  backend          = vault_mount.pki_istio.path
  name             = "istio"
  allowed_domains  = ["cluster.local", "ops.${var.root_domain}", "istio.${var.root_domain}"]
  allow_subdomains = true
  allow_any_name   = true
  require_cn       = false
  allowed_uri_sans = ["spiffe://*"]
  max_ttl          = "2592000s"
  key_type         = "any"
  organization     = ["Ratlab"]
  ou               = ["Istio Workload"]
}


resource "vault_pki_secret_backend_role" "vault" {
  depends_on       = [vault_pki_secret_backend_intermediate_set_signed.int_signed]
  backend          = vault_mount.pki.path
  name             = "istio"
  allowed_domains  = ["ops.${var.root_domain}"]
  allow_subdomains = true
  require_cn       = false
  max_ttl          = "2592000s"
  organization     = ["Ratlab"]
  ou               = ["Ops Server"]
}

resource "vault_pki_secret_backend_cert" "vault_cert" {
  backend     = vault_mount.pki.path
  name        = vault_pki_secret_backend_role.vault.name
  common_name = "vault.ops.${var.root_domain}"
}

# Reload Vault to apply the real certificates
resource "null_resource" "vault_reload" {
  triggers = {
    cert_sha     = sha1("${vault_pki_secret_backend_cert.vault_cert.certificate}\n${vault_pki_secret_backend_cert.vault_cert.issuing_ca}\n${vault_pki_secret_backend_root_cert.root.certificate}")
    container_id = docker_container.openbao.id
  }

  provisioner "local-exec" {
    command = <<EOT
      docker exec -i openbao sh -c 'cat > /vault/config/vault-chain.crt' <<EOF
${vault_pki_secret_backend_cert.vault_cert.certificate}
${vault_pki_secret_backend_cert.vault_cert.issuing_ca}
${vault_pki_secret_backend_root_cert.root.certificate}
EOF
      docker exec -i openbao sh -c 'cat > /vault/config/vault.key' <<EOF
${vault_pki_secret_backend_cert.vault_cert.private_key}
EOF
      docker exec -i openbao sh -c "kill -s HUP \$(pgrep vault || pidof vault || echo 7)"
    EOT
  }
}

# --- 3. Kubernetes Infrastructure ---

provider "kind" {}

resource "kind_cluster" "mesh_cluster" {
  name           = "mesh-cluster"
  wait_for_ready = true
  depends_on     = [null_resource.mesh_network, null_resource.vault_reload]

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    node {
      role = "control-plane"
      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
        protocol       = "TCP"
      }
    }
  }
}

resource "null_resource" "connect_kind_to_mesh_network" {
  depends_on = [kind_cluster.mesh_cluster]
  provisioner "local-exec" {
    command = "docker network connect mesh-network mesh-cluster-control-plane || true"
  }
}

resource "null_resource" "coredns_patch" {
  depends_on = [kind_cluster.mesh_cluster]
  provisioner "local-exec" {
    command = <<EOF
kubectl get configmap coredns -n kube-system --context kind-mesh-cluster -o yaml | sed 's/ready/ready\n        hosts {\n          10.10.0.10 vault.ops.${var.root_domain}\n          fallthrough\n        }/' | kubectl apply --context kind-mesh-cluster -f -
kubectl rollout restart deployment coredns -n kube-system --context kind-mesh-cluster
EOF
  }
}

resource "null_resource" "install_gateway_api" {
  depends_on = [kind_cluster.mesh_cluster]
  provisioner "local-exec" {
    command = "kubectl apply --context kind-mesh-cluster -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml"
  }
}

# --- 4. MetalLB & Cert-Manager ---

provider "helm" {
  kubernetes {
    host                   = kind_cluster.mesh_cluster.endpoint
    client_certificate     = kind_cluster.mesh_cluster.client_certificate
    client_key             = kind_cluster.mesh_cluster.client_key
    cluster_ca_certificate = kind_cluster.mesh_cluster.cluster_ca_certificate
  }
}

provider "kubernetes" {
  host                   = kind_cluster.mesh_cluster.endpoint
  client_certificate     = kind_cluster.mesh_cluster.client_certificate
  client_key             = kind_cluster.mesh_cluster.client_key
  cluster_ca_certificate = kind_cluster.mesh_cluster.cluster_ca_certificate
}

resource "helm_release" "metallb" {
  name             = "metallb"
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  version          = "0.14.3"
  depends_on       = [kind_cluster.mesh_cluster]
}

resource "null_resource" "metallb_config" {
  depends_on = [helm_release.metallb]
  provisioner "local-exec" {
    command = <<EOF
sleep 15
kubectl apply --context kind-mesh-cluster -f - <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.10.0.100-10.10.0.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
YAML
EOF
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.14.4"
  depends_on       = [kind_cluster.mesh_cluster]
  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "null_resource" "apply_vault_issuer" {
  depends_on = [helm_release.cert_manager, vault_pki_secret_backend_root_cert.root, vault_approle_auth_backend_role_secret_id.cert_manager]

  triggers = {
    role_id   = vault_approle_auth_backend_role.cert_manager.role_id
    secret_id = vault_approle_auth_backend_role_secret_id.cert_manager.secret_id
    ca_cert   = sha1(vault_pki_secret_backend_root_cert.root.certificate)
  }

  provisioner "local-exec" {
    command = <<CMD
kubectl wait --for=condition=Ready pods --all -n cert-manager --timeout=300s --context kind-mesh-cluster

kubectl apply --context kind-mesh-cluster -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: cert-manager-approle
  namespace: cert-manager
type: Opaque
stringData:
  secretId: "${vault_approle_auth_backend_role_secret_id.cert_manager.secret_id}"
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: https://vault.ops.${var.root_domain}:443
    path: pki/sign/istio
    caBundle: "${base64encode(vault_pki_secret_backend_root_cert.root.certificate)}"
    auth:
      appRole:
        path: approle
        roleId: "${vault_approle_auth_backend_role.cert_manager.role_id}"
        secretRef:
          name: cert-manager-approle
          key: secretId
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer-istio
spec:
  vault:
    server: https://vault.ops.${var.root_domain}:443
    path: pki_istio/sign/istio
    caBundle: "${base64encode(vault_pki_secret_backend_root_cert.root.certificate)}"
    auth:
      appRole:
        path: approle
        roleId: "${vault_approle_auth_backend_role.cert_manager.role_id}"
        secretRef:
          name: cert-manager-approle
          key: secretId
YAML
CMD
  }
}

# --- 5. Istio Ambient Mesh & istio-csr ---

resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = "istio-system"
  }
  depends_on = [kind_cluster.mesh_cluster]
}

resource "kubernetes_secret" "istio_root_ca" {
  metadata {
    name      = "istio-root-ca"
    namespace = "cert-manager"
  }
  data = {
    "ca.pem" = vault_pki_secret_backend_root_cert.root.certificate
  }
  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "istio_csr" {
  name       = "cert-manager-istio-csr"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager-istio-csr"
  namespace  = "cert-manager"
  version    = "v0.12.0"
  depends_on = [null_resource.apply_vault_issuer, kubernetes_secret.istio_root_ca]
  set {
    name  = "app.server.caTrustedNodeAccounts"
    value = "istio-system/ztunnel\\,kube-system/ztunnel"
  }
  set {
    name  = "app.certmanager.issuer.group"
    value = "cert-manager.io"
  }
  set {
    name  = "app.certmanager.issuer.kind"
    value = "ClusterIssuer"
  }
  set {
    name  = "app.certmanager.issuer.name"
    value = "vault-issuer-istio"
  }
  set {
    name  = "app.certmanager.preserveCertificateRequests"
    value = "true"
  }
  set {
    name  = "app.server.maxCertificateDuration"
    value = "48h"
  }
  set {
    name  = "app.tls.certificateDuration"
    value = "24h"
  }
  set {
    name  = "app.tls.istiodCertificateDuration"
    value = "24h"
  }
  set {
    name  = "app.tls.rootCAFile"
    value = "/var/run/secrets/istio-csr/ca.pem"
  }
  set {
    name  = "volumeMounts[0].name"
    value = "root-ca"
  }
  set {
    name  = "volumeMounts[0].mountPath"
    value = "/var/run/secrets/istio-csr"
  }
  set {
    name  = "volumeMounts[0].readOnly"
    value = "true"
  }
  set {
    name  = "volumes[0].name"
    value = "root-ca"
  }
  set {
    name  = "volumes[0].secret.secretName"
    value = "istio-root-ca"
  }
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = "istio-system"
  version    = "1.21.2"
  depends_on = [helm_release.istio_csr, kubernetes_namespace.istio_system]
}

resource "helm_release" "istio_cni" {
  name       = "istio-cni"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "cni"
  namespace  = "istio-system"
  version    = "1.21.2"
  depends_on = [helm_release.istio_base]
  set {
    name  = "profile"
    value = "ambient"
  }
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.21.2"
  depends_on = [helm_release.istio_base]
  set {
    name  = "profile"
    value = "ambient"
  }
  set {
    name  = "global.caAddress"
    value = "cert-manager-istio-csr.cert-manager.svc:443"
  }
  set {
    name  = "pilot.env.ENABLE_CA_SERVER"
    value = "false"
  }
  set {
    name  = "pilot.env.ENABLE_LEGACY_FS_CERT_AUTHORIZATION"
    value = "false"
  }
}

resource "helm_release" "ztunnel" {
  name       = "ztunnel"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "ztunnel"
  namespace  = "istio-system"
  version    = "1.21.2"
  depends_on = [helm_release.istiod, helm_release.istio_cni]
  set {
    name  = "caAddress"
    value = "cert-manager-istio-csr.cert-manager.svc:443"
  }
}

# --- 6. Application Routing ---

resource "kubernetes_namespace" "apps" {
  metadata {
    name   = "apps"
    labels = { "istio.io/dataplane-mode" = "ambient" }
  }
  depends_on = [helm_release.istiod]
}

resource "kubernetes_deployment" "httpbin" {
  metadata {
    name      = "httpbin"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "httpbin" } }
    template {
      metadata { labels = { app = "httpbin" } }
      spec {
        service_account_name = "httpbin"
        container {
          name  = "httpbin"
          image = "kennethreitz/httpbin"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service_account" "httpbin" {
  metadata {
    name      = "httpbin"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }
}

resource "kubernetes_service" "httpbin" {
  metadata {
    name      = "httpbin"
    namespace = kubernetes_namespace.apps.metadata[0].name
  }
  spec {
    selector = { app = "httpbin" }
    port {
      port        = 8000
      target_port = 80
      name        = "http"
    }
  }
}

resource "null_resource" "deploy_gateway_routes" {
  depends_on = [
    helm_release.ztunnel,
    kubernetes_service.httpbin,
    null_resource.install_gateway_api
  ]
  provisioner "local-exec" {
    command = <<CMD
kubectl apply --context kind-mesh-cluster -f - <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: httpbin-cert
  namespace: apps
spec:
  secretName: httpbin-cert
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: "app1.ops.${var.root_domain}"
  dnsNames:
  - "app1.ops.${var.root_domain}"
  - "app2.ops.${var.root_domain}"
  - "app3.ops.${var.root_domain}"
  - "app4.ops.${var.root_domain}"
  - "app5.ops.${var.root_domain}"
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: httpbin-gateway
  namespace: apps
spec:
  gatewayClassName: istio
  listeners:
  - name: https
    hostname: "*.ops.${var.root_domain}"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: httpbin-cert
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin-route
  namespace: apps
spec:
  parentRefs:
  - name: httpbin-gateway
  hostnames:
  - "*.ops.${var.root_domain}"
  rules:
  - backendRefs:
    - name: httpbin
      port: 8000
YAML

# Wait for the gateway deployment to be created by the controller
echo "Waiting for httpbin-gateway-istio deployment..."
for i in {1..30}; do
  if kubectl get deployment httpbin-gateway-istio -n apps --context kind-mesh-cluster >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# Patch the deployment with hostPort: 443
kubectl patch deployment httpbin-gateway-istio -n apps --context kind-mesh-cluster -p '{"spec":{"template":{"spec":{"containers":[{"name":"istio-proxy","ports":[{"name":"https","containerPort":443,"hostPort":443,"protocol":"TCP"}]}]}}}}'
CMD
  }
}

output "root_domain" {
  value       = var.root_domain
  description = "The root domain name used for the environment."
}
