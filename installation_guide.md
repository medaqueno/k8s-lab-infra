# Step-by-Step Installation Guide: Kubernetes Lab "From Scratch" (Single Node)

This guide covers bootstrapping a single-node Kubernetes cluster using Talos Linux and OpenTofu on a physical machine with 16GB RAM.

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
This lab is optimized for a **single physical machine** (16GB RAM).
- **Memory Efficiency**: A single-node OS installation with explicit resource reservations (2GB system + 512MB kubelet) leaves ~13GB for Kubernetes workloads.
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
By default, the control plane node has a taint that prevents scheduling normal workloads. In this single-node lab the taint is already removed by the configuration applied through `tofu apply`, but you can verify that no taint exists:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

If there would be any taint, we must remove it:
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

---


## 6. GitOps Bootstrap
Instead of manually creating namespaces and installing components, we will let ArgoCD manage the platform.

### 6.1 Install ArgoCD
```bash
# Create namespace
kubectl create namespace argocd

# Label it for the architecture
kubectl label namespace argocd tier=platform

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 6.2 Install Gateway API CRDs (Required for Istio Ambient)
These CRDs must be present before ArgoCD tries to sync the Istio Gateway:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
```

### 6.3 Apply Bootstrap App
Apply the "App of Apps" which will spin up the Platform (Istio, Namespaces) and Workloads.
```bash
kubectl apply -f https://raw.githubusercontent.com/medaqueno/k8s-lab-gitops/main/bootstrap/bootstrap.yaml
```
*Note: Ensure you have pushed your changes to `k8s-lab-gitops` before running this.*

### 6.4 Verify Platform
ArgoCD will automatically create the base infrastructure:
1.  **Create Namespaces**: `istio-system` (Platform Mesh).
2.  **Install Mesh components**: Istio Gateway, Ztunnel and CNI.

It will take a few minutes until all pods are running.

## Check the Progress

### ArgoCD Applications
Run the following command to check the status of your applications in ArgoCD:

```bash
kubectl get applications -n argocd
```

   You should see at least **two applications**:
   - The **bootstrap** app (the parent).
   - The **platform** app (created by the bootstrap app).

   Example output:

   | NAME       | SYNC STATUS | HEALTH STATUS |
   |------------|-------------|---------------|
   | bootstrap  | Synced      | Healthy       |
   | platform   | Synced      | Progressing   |

   > **Note:**
   > The `platform` app often remains in a `Progressing` state (instead of `Healthy`) because the Istio Gateway is waiting for a LoadBalancer IP that doesn't exist in a local lab environment. This is normal and can be ignored.

---

### Istio Ambient Pods
Run the following command to check the pods in the `istio-system` namespace:

```bash
kubectl get pods -n istio-system
```

   You should see the **4 core components of Istio Ambient**. Since you are on a single node, you will see **1 of each**:

   | NAME                          | READY | STATUS  | RESTARTS | AGE |
   |-------------------------------|-------|---------|----------|-----|
   | istiod-xxxxx                  | 1/1   | Running | 0        | 2m  |
   | main-gateway-istio-xxxxx      | 1/1   | Running | 0        | 2m  |
   | ztunnel-xxxxx                 | 1/1   | Running | 0        | 2m  |

   - **istiod**: The control plane of Istio.
   - **ztunnel**: The secure proxy (handling mTLS) for Ambient mesh.
   - **main-gateway-istio**: Your ingress gateway (the name may vary slightly depending on your specific Helm release name, but it usually contains "gateway").

---

## 7. Operational Verification

### 7.1 Namespace & Multi-Tenancy
Ensure namespaces were created with the correct labels for the architecture:
```bash
# Check for Tier labels
kubectl get namespaces -L tier
```

### 7.2 Istio Ambient Mesh Status
Verify that the sidecarless mesh is active:
```bash
# Verify Ztunnel (one pod per node)
kubectl get pods -n istio-system -l app=ztunnel

# Verify Istio Ingress Gateway
kubectl get pods -n istio-system -l app=istio-ingressgateway

# Check if pods in dev-demo-app are captured by the mesh
# (The output should show ztunnel log entries for the pod IP)
kubectl logs -n istio-system -l app=ztunnel | grep "adding pod"
```

---

## 8. Known Issues & Tips for Local Labs

### LoadBalancer IP Pending
Your Gateway Service will show `<pending>` because there is no Cloud Load Balancer. 
* **Impact**: ArgoCD will show the app as `Progressing` indefinitely.
* **Workaround**: You can still access the services via NodePort if you find the mapped ports:
  ```bash
  kubectl get svc -n istio-system main-gateway-istio
  ```
* **Recommended fix**: Install **MetalLB** later to manage a local pool of IPs.

### Pod Security for Istio Ambient
Ztunnel requires `privileged` host permissions. If you see `FailedCreate` errors in `istio-system`, verify that the namespace is labeled:
`pod-security.kubernetes.io/enforce=privileged`.

## 9. Next Steps: GitOps Operations

From this point forward, all application and configuration management is done through Git and ArgoCD.

**For GitOps operations (deployments, configurations, rollbacks)**, refer to the complete documentation at:
📘 **[k8s-lab-gitops Repository](https://github.com/medaqueno/k8s-lab-gitops)**

There you will find:
- How to add new applications
- ConfigMaps and Secrets management
- Multi-environment deployments (dev/prod)
- Rollbacks and troubleshooting
- ArgoCD UI access
