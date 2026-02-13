terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
    }
  }
}

############################
# VARIABLES
############################

variable "cluster_name" {
  type    = string
  default = "home-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "v1.31.0"
}

variable "talos_version" {
  type    = string
  default = "v1.6.0"
}

variable "node_ip" {
  description = "IP address of the Talos node in the local network"
  type        = string
  default     = "192.168.1.35"
}

############################
# LOCALS
############################

locals {
  controlplane_endpoint = "https://${var.node_ip}:6443"
}

############################
# TALOS SECRETS
############################

resource "talos_machine_secrets" "this" {}

############################
# SINGLE NODE CONFIG
############################

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.controlplane_endpoint
  machine_type       = "controlplane"
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version

  machine_secrets = talos_machine_secrets.this.machine_secrets

  # Optimised to a baremetal with 16gb RAM
  # And allow scheduling so pods/workloads can be in the same node than controlplane, no taints
  config_patches = [
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }),
    yamlencode({
      machine = {
        kubelet = {
          extraArgs = {
            "max-pods"        = "110"
            "pods-per-core"   = "0"
            "event-qps"       = "5"
            "kube-reserved"   = "cpu=100m,memory=512Mi,ephemeral-storage=1Gi"
            "system-reserved" = "cpu=100m,memory=2Gi,ephemeral-storage=1Gi"
          }
        }
      }
    })
  ]
}


############################
# TALOS CLIENT CONFIG
############################

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [var.node_ip]
}

############################
# APPLY TALOS CONFIGURATION (same as talosctl apply-config)
############################


resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.node_ip
}

############################
# BOOTSTRAP TALOS (same as talosctl bootstrap)
############################

resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
}


############################
# GENERATE KUBECONFIG
############################

resource "talos_cluster_kubeconfig" "this" {
  node                 = var.node_ip
  client_configuration = data.talos_client_configuration.this.client_configuration
}


############################
# OUTPUTS
############################

output "machine_configuration" {
  value     = data.talos_machine_configuration.controlplane.machine_configuration
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

############################
# GENERATE LOCAL FILES
############################

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "./_generated/talosconfig"
}

resource "local_file" "controlplane_yaml" {
  content  = data.talos_machine_configuration.controlplane.machine_configuration
  filename = "./_generated/controlplane.yaml"
}

resource "local_sensitive_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "./_generated/kubeconfig"
}
