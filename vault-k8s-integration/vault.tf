

resource "docker_image" "vault" {
  name         = "hashicorp/vault:1.15.5"
  keep_locally = true
}

resource "docker_container" "vault" {
  name  = "vault"
  image = docker_image.vault.image_id
  
  ports {
    internal = 8200
    external = 8282
  }
  
  env = [
    "VAULT_DEV_ROOT_TOKEN_ID=root",
    "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200"
  ]
  
  network_mode = "kind"
  
  # Placeholder for "local storage" requirement
  volumes {
    host_path      = "${abspath(path.module)}/vault_data"
    container_path = "/vault/file"
  }
  

  
  # Ensure the kind clusters exist, so the 'kind' docker network also exists.
  depends_on = [
    kind_cluster.cluster1, 
    kind_cluster.cluster2
  ]
}

resource "time_sleep" "wait_for_vault" {
  depends_on      = [docker_container.vault]
  create_duration = "10s"
}
