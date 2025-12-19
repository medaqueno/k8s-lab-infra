terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "1.11.5"
    }
  }
}

provider "talos" {}

# Definición del Cluster
resource "talos_machine_secrets" "this" {}

# Configuración para el Control Plane
resource "talos_machine_configuration_controlplane" "cp" {
  cluster_name     = "k8s-lab"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  # Usamos tu archivo como base
  config_patches = [
    file("${path.module}/talos-files/controlplane.yaml")
  ]
}

# Configuración para los Workers (aquí aplicamos los Tiers/Labels)
resource "talos_machine_configuration_worker" "worker" {
  cluster_name     = "k8s-lab"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    file("${path.module}/talos-files/worker.yaml"),
    # Patch para añadir etiquetas de nodo según tu diseño
    yamlencode({
      machine = {
        nodeLabels = {
          "topology.kubernetes.io/zone" = "rack-1"
          "node-role.kubernetes.io/tier" = "normal" # O internal/infra-tools
        }
      }
    })
  ]
}