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

---

## 6. Namespace Strategy Setup

Create the logical separation:
```bash
# Platform Management (ArgoCD)
kubectl create namespace argocd
kubectl label namespace argocd tier=platform

# Sample Application
kubectl create namespace dev-demo-app
kubectl label namespace dev-demo-app app.kubernetes.io/part-of=applications
kubectl label namespace dev-demo-app istio.io/dataplane-mode=ambient
```

---

## 7. Install Istio Ambient (Sidecarless Mesh)

### 7.1 Installation
Install Istio with the ambient profile to save memory:
```bash
istioctl install --set profile=ambient \
  --set components.ingressGateways[0].enabled=true \
  --set components.ingressGateways[0].name=istio-ingressgateway \
  --namespace istio-system \
  --create-namespace \
  -y
```

### 7.2 Verification: Mesh Infrastructure
```bash
# Verify Istiod and Ztunnel (Node Agent)
kubectl get pods -n istio-system

# Check Ztunnel logs for connectivity
kubectl logs -n istio-system -l app=ztunnel --tail 20
```

---

## 8. Install ArgoCD (GitOps Controller)

### 8.1 Installation
Install ArgoCD in its standard namespace:
```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 8.2 Verification: ArgoCD
```bash
# Check pods
kubectl get pods -n argocd

# Retrieve the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI (Local Port Forward)
# kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

## 9. Configure Istio Gateway

Expose the cluster services:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: istio-system
spec:
  gatewayClassName: istio
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF
```

### 9.1 Verification: Ingress Gateway
```bash
# Check if the Gateway resource exists
kubectl get gateway -n istio-system

# Check the address assigned to the Gateway
kubectl get service -n istio-system istio-ingressgateway
```

---

## 10. Final Verification Checklist

- [x] **OS Layer**: `talosctl health` returns all healthy.
- [x] **K8s Layer**: Node `192.168.1.35` is in `Ready` state.
- [x] **Scheduling**: `kubectl describe node` shows no "NoSchedule" taints.
- [x] **Mesh Layer**: `ztunnel` pod is running in `istio-system`.
- [x] **GitOps Layer**: `argocd-server` is reachable.
- [x] **Namespace Policy**: `dev-demo-app` has `istio.io/dataplane-mode=ambient` label.

---

## Next Steps
1. Create your application manifests in the **k8s-lab-gitops** repo.
2. Link the repo to ArgoCD.
3. Deploy!