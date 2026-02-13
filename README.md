# Step-by-Step Installation Guide: Kubernetes Lab "From Scratch" (Single Node)

This guide covers bootstrapping a single-node Kubernetes cluster using Talos Linux and OpenTofu on a physical machine with 4GB RAM.

> [!TIP]
> Antes de empezar, revisa la **[Arquitectura del Sistema](architecture_overview.md)** y las **[Convenciones de Nombres](NAMING_CONVENTIONS.md)** que rigen este cluster.

## 1. Prerequisites (Management Machine)

You need a workstation (Mac or Linux) to manage the cluster.

### 1.1 Install Tools

#### MacOS
```bash
brew install opentofu kubectl talosctl istioctl argocd helm
```

---

## 2. Design Rationale: Local Lab vs. Cloud/Production

### 2.1 Why a Single Node for this Lab?
This lab is optimized for **resource-constrained physical hardware** (4GB RAM).
- **Memory Efficiency**: Running 3 Virtual Machines (VMs) on 4GB of RAM would lead to extreme swapping and instability. A single-node OS installation leaves ~3.5GB for Kubernetes and applications.
- **Sidecarless Architecture**: We use **Istio Ambient Mesh**. This saves ~50MB of RAM per pod compared to traditional sidecar meshes, which is vital in a small-memory environment.
- **Simplicity**: For internal learning, a single node reduces networking complexity while still allowing you to learn the Kubernetes API, GitOps, and Mesh logic.

### 2.2 Recommendations for Cloud/Production
In a Production or Cloud environment (AWS, GCP, Azure), you should **never** use a single-node setup. Recommended patterns include:

| Feature | Local Lab (This setup) | Cloud / Production |
| :--- | :--- | :--- |
| **High Availability** | Single Node (Single Point of Failure) | 3 Control Plane nodes + Auto-scaling Workers. |
| **Isolation** | Logical (Namespaces) | Physical (Dedicated Node Groups for System/Apps). |
| **Ingress** | Local Istio Gateway on the same node | Cloud Load Balancer (ALB/NLB) with multiple IPs. |
| **Storage** | Local Disk (Ephemeral) | Persistent CSI Drivers (EBS, Persistent Disks, EFS). |
| **Managed Services** | Manual Talos management | Use EKS, GKE, or AKS to offload Control Plane management. |

---

## 3. Cluster Architecture (Single Node Logic)

Separation is achieved through **Namespaces** instead of physical nodes.

- **System**: `kube-system`, `talos-system` (Core OS & K8s)
- **Platform**: `argocd`, `istio-system` (Management tools)
- **Applications**: `dev-demo-app`, `prod-demo-app` (Your workloads)

---

## 4. Bootstrapping the Node

The entire cluster lifecycle — from generating secrets to obtaining the kubeconfig — is managed by a single `tofu apply` command. No manual `talosctl` steps are needed.

### 4.1 Clean Previous State (if applicable)
If you have a previous installation, clean up before proceeding:
```bash
rm -f ~/.talos/config
rm -rf _generated/
tofu destroy  # only if there is previous Tofu state
```

### 4.2 Prepare the Node
Ensure the target machine is booted in **Talos maintenance mode** (e.g. from the Talos USB installer). The node must be reachable at the IP configured in `main.tofu` (by default `192.168.1.35`).

### 4.3 Apply Configuration
From the cluster directory, run:
```bash
cd clusters/main-cluster
tofu init

tofu plan

tofu apply
```

OpenTofu will execute the following resources in order:

1. `talos_machine_secrets` — generates certificates and secrets.
2. `talos_machine_configuration` — builds the controlplane config with kubelet resource reservations.
3. `talos_client_configuration` — generates the talosconfig for CLI access.
4. `talos_machine_configuration_apply` — pushes the config to the node. **The server will reboot and install Talos to disk.**
5. ⏳ Automatic wait — Tofu waits until the node is available again.
6. `talos_machine_bootstrap` — bootstraps the Kubernetes cluster.
7. `talos_cluster_kubeconfig` — retrieves the kubeconfig.
8. `local_file` / `local_sensitive_file` — writes `talosconfig`, `controlplane.yaml` and `kubeconfig` to `_generated/`.

> **Note:** After the node reboots, make sure the USB installer is removed (or that BIOS boot priority favors the internal disk). If the node boots from USB again, remove it and restart manually.

### 4.4 Configure Local Environment
Once `tofu apply` completes, all generated files are already in `_generated/`. Export the environment variables so your local tools can reach the cluster:

```bash
export TALOSCONFIG=$(pwd)/_generated/talosconfig
export KUBECONFIG=$(pwd)/_generated/kubeconfig
```

Verify connectivity:
```bash
kubectl get nodes -o wide
```

Process might take some minutes until all nodes become accesible. You can check the progress of the bootstrap process with:
```bash
talosctl health --nodes 192.168.1.35 --talosconfig _generated/talosconfig
```
---

## 5. Verification: OS & Base Cluster

Before installing the platform, ensure the foundation is solid.

### 5.1 Real-time Node Monitoring
Open a new terminal and keep this dashboard running:
```bash
talosctl dashboard --nodes 192.168.1.35
```

### 5.2 Kubernetes Health Check
```bash
# Check node status
kubectl get nodes -o wide

# Check core system pods
kubectl get pods -n kube-system

# Check for any errors in the cluster
kubectl get events --sort-by='.lastTimestamp' -A
```

### 5.3 Allow Scheduling on Single Node (Required)
By default, the control plane node has a taint that prevents scheduling normal workloads since this is a single-node lab. It is already removed by our configuration in `main.tofu` but we can ensure that no taint exists:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

If there would be any taint, we must remove it:
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### 5.4 Definir los nodos y endpoints por defecto 
Para evitar tener que poner --talosconfig  --nodes y --endpoint todo el tiempo:

```bash
talosctl config node 192.168.1.35 --talosconfig ./_generated/talosconfig
talosctl config endpoint 192.168.1.35 --talosconfig ./_generated/talosconfig
```

Hacer que talosctl use ese archivo automáticamente: Para no tener que poner --talosconfig ./talosconfig todo el tiempo, lo ideal es moverlo a la ubicación por defecto de la herramienta o usar una variable de entorno:

- Opción A: Copia el archivo a ~/.talos/config.

- Opción B: Exporta la variable: export TALOSCONFIG=$(pwd)/talosconfig.

---


## 6. Handover to GitOps (Platform Bootstrap)

Once the OS and Kubernetes base are ready, we hand over control to **ArgoCD**. This follows the GitOps pattern where the desired state of the platform is defined in git.

### 6.1 Install ArgoCD
We install the GitOps engine first:

```bash
# Create namespace
kubectl create namespace argocd

# Label it for the architecture
kubectl label namespace argocd tier=platform

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 6.2 Install Gateway API CRDs
Istio Ambient Mesh (our network layer) requires these CRDs to be present before it boots.
You can check new versions in: https://github.com/kubernetes-sigs/gateway-api/releases
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

### 6.3 Ignite the Platform
We apply a single "Bootstrap" application that tells ArgoCD to read the configuration from our GitOps repository.

```bash
kubectl apply -f https://raw.githubusercontent.com/medaqueno/k8s-lab-gitops/main/bootstrap/bootstrap.yaml
```

---

## 7. What's Next?
Your cluster is now bootstrapping itself. It will automatically download and install:
- Istio Ambient Mesh (Ztunnel, Istiod, CNI)
- Ingress Gateways
- Application Workloads

### 🛑 Stop Here!
This repository (`k8s-lab-infra`) has done its job: you have a running cluster. 

For **Access Credentials**, **Dashboards**, **Deploying Applications** and **Verifying the Platform**, please proceed to the **GitOps Repository**:

👉 **[k8s-lab-gitops/README.md](https://github.com/medaqueno/k8s-lab-gitops)**

