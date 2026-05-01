# -----------------------------------------------------------------------------
# Shared Docker Network
# -----------------------------------------------------------------------------
# The Kind cluster nodes will be connected to this network so that
# MetalLB L2 ARP announcements are visible to the nodes and the host.
# -----------------------------------------------------------------------------

resource "docker_network" "shared" {
  name   = var.shared_network_name
  driver = "bridge"

  ipam_config {
    subnet  = var.docker_network_subnet
    gateway = var.shared_network_gateway
  }

  # Prevent Docker from automatically connecting random containers
  internal = false
}
