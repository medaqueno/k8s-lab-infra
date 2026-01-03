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

### 4.1 Generate Configuration
Navigate to the cluster directory:
```bash
cd clusters/main-cluster
tofu init
tofu plan
tofu apply
```

This generates `_generated/controlplane.yaml` (the single node config) and `_generated/talosconfig`.

### 4.2 Apply Configuration
Set the talosconfig environment variable and apply the config to your machine (`192.168.1.35`):

```bash
export TALOSCONFIG=$(pwd)/_generated/talosconfig
talosctl apply-config --insecure --nodes 192.168.1.35 --file _generated/controlplane.yaml
```

### 4.3 Initialize Cluster
Run the bootstrap command once on the node:
```bash
talosctl bootstrap --nodes 192.168.1.35
```

### 4.4 Retrieve Kubeconfig
```bash
talosctl kubeconfig _generated/ --nodes 192.168.1.35
export KUBECONFIG=$(pwd)/_generated/kubeconfig
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
By default, the control plane node has a taint that prevents scheduling normal workloads. Since this is a single-node lab, we must remove it:
```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

---

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

### 6.3 Verify Platform
ArgoCD will automatically:
1.  Create `istio-system`, `dev-demo-app` namespaces with correct labels.
2.  Install Istio Gateway and Ztunnel.

Check the progress:
```bash
kubectl get applications -n argocd
kubectl get pods -n istio-system
```

### 6.4 Access ArgoCD UI
1. **Retrieve the admin password**:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
   ```
2. **Port-forward to the server**:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
3. Open `https://localhost:8080` and login with user `admin`.

---

## 7. Operational Verification

### 7.1 Namespace & Multi-Tenancy
Ensure namespaces were created with the correct labels for the architecture:
```bash
# Check for Ambient Mesh label on workload namespaces
kubectl get namespaces -L istio.io/dataplane-mode

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

### 7.3 GitOps Reconciliation
Check the "App of Apps" status:
```bash
# Ensure all apps are Synced and Healthy
argocd app list
```

---

## 10. Final Verification Checklist

- [ ] **OS Layer**: `talosctl health` returns all healthy.
- [ ] **K8s Layer**: Node `192.168.1.35` is in `Ready` state.
- [ ] **Scheduling**: Node is "untainted" (Section 5.3).
- [ ] **Mesh Layer**: `ztunnel` pod is running in `istio-system`.
- [ ] **GitOps Layer**: `argocd-server` is reachable and `bootstrap` app is Synced.
- [ ] **Namespace Policy**: `dev-demo-app` has `istio.io/dataplane-mode=ambient` label.

---

## Next Steps
1. Create your application manifests in the **k8s-lab-gitops** repo.
2. Link the repo to ArgoCD.
3. Deploy!