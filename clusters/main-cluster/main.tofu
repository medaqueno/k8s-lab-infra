terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.0"
    }
  }
}

provider "talos" {}

# Definición del Cluster
resource "talos_machine_secrets" "this" {}

# Define a local variable for common settings to avoid repeating them
locals {
  cluster_name     = "k8s-lab"
  cluster_endpoint = "https://192.168.1.35:6443"
  out_dir          = "${path.module}/_generated"
  common_machine_config = {
    machine = {
      install = {
        disk       = "/dev/sda"
        image      = "ghcr.io/siderolabs/installer:v1.12.0"
        wipe       = true
        bootloader = true
      }
      kubelet = {
        image = "ghcr.io/siderolabs/kubelet:v1.34.1"
      }
    }
  }
}

# 1. Configuration for the Control Plane (Isolated)
data "talos_machine_configuration" "cp" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = false # Enforce isolation
      }
    })
  ]
}

# 2. Configuration for Platform Workers (ArgoCD, Istio, Monitoring)
data "talos_machine_configuration" "worker_platform" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        nodeLabels = {
          "node-role.kubernetes.io/tier" = "platform"
        }
        # Taint to ensure standard apps don't land here
        nodeTaints = {
          "node-role.kubernetes.io/platform" = "NoSchedule"
        }
      }
    })
  ]
}

# 3. Configuration for standard Application Workers
data "talos_machine_configuration" "worker_app" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      machine = {
        nodeLabels = {
          "node-role.kubernetes.io/tier" = "applications"
        }
      }
    })
  ]
}
# 4. Generate Client Configuration (talosconfig)
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = ["192.168.1.35"] # Control Plane IP
  endpoints            = ["192.168.1.35"] # Control Plane IP (API Endpoint)
}

# 5. Export configurations to local files
resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${local.out_dir}/talosconfig"
}

resource "local_file" "cp_config" {
  content  = data.talos_machine_configuration.cp.machine_configuration
  filename = "${local.out_dir}/controlplane.yaml"
}

resource "local_file" "platform_config" {
  content  = data.talos_machine_configuration.worker_platform.machine_configuration
  filename = "${local.out_dir}/platform.yaml"
}

resource "local_file" "applications_config" {
  content  = data.talos_machine_configuration.worker_app.machine_configuration
  filename = "${local.out_dir}/applications.yaml"
}

# Outputs for easy access
output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "controlplane_config" {
  value     = data.talos_machine_configuration.cp.machine_configuration
  sensitive = true
}
