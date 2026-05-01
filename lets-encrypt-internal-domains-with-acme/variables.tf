variable "cloudflare_api_token" {
  description = "Cloudflare API Token with DNS and Tunnel permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the domain"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kind cluster"
  type        = string
  default     = "ops-cluster"
}

variable "domain" {
  description = "Base domain for the project"
  type        = string
  default     = "example.com"
}

variable "subdomain" {
  description = "Subdomain for internal ops"
  type        = string
  default     = "ops.example.com"
}

variable "metallb_ip_range" {
  description = "IP range for MetalLB (MUST be within the docker_network_subnet)"
  type        = string
  default     = "172.21.255.200-172.21.255.250"
}

variable "docker_network_subnet" {
  description = "The subnet of the Docker network used by Kind (used by docker-mac-net-connect to create host routes)"
  type        = string
  default     = "172.21.0.0/16"
}

variable "shared_network_name" {
  description = "Name of the shared Docker network"
  type        = string
  default     = "kind-shared"
}

variable "shared_network_gateway" {
  description = "Gateway IP for the shared Docker network"
  type        = string
  default     = "172.21.0.1"
}

variable "acme_issuer" {
  description = "ACME Issuer to use (letsencrypt-staging or letsencrypt-prod)"
  type        = string
  default     = "letsencrypt-staging"
}

variable "acme_email" {
  description = "Email for Let's Encrypt account"
  type        = string
}
