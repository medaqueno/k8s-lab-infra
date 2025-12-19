# Kubernetes Lab Blueprint: GitOps & Bare Metal (Talos + OpenTofu)

Este documento detalla la configuración integral del clúster, desde el aprovisionamiento de hardware físico hasta la exposición de aplicaciones mediante Istio Ambient, manteniendo a los desarrolladores aislados de la complejidad del CI/CD.

1. Estructura de Repositorios
   A. infra-provisioning (DevOps)

Finalidad: Gestión del hierro y configuración de Talos Linux mediante OpenTofu.

```plaintext

infra/
├── modules/ # Módulos de red y cómputo
├── talos-files/ # Tus archivos YAML base
│ ├── controlplane.yaml
│ ├── worker.yaml
│ └── talosconfig
├── main.tf # Definición de Tiers (normal, infra-tools, internal)
└── providers.tf # Configuración de OpenTofu
```

B. k8s-lab-gitops (DevOps - Single Source of Truth)

Finalidad: Definición declarativa del estado del clúster y plantillas de CI.

```plaintext

k8s-lab-gitops/
├── system/
│ ├── argocd/ # Kustomization + Parche de Tier
│ └── istio/ # Gateway API + Ambient Mesh
├── apps/
│ └── python-api-1/ # Organización por App
│ ├── base/ # Deployment, Svc (ClusterIP), ConfigMap
│ └── overlays/ # dev/ y prod/ (Patches + HTTPRoutes)
├── argo-apps/ # Definiciones de Application para ArgoCD
└── workflow-templates/ # Reusable GitHub Actions
```

C. app-python-api-1 (Desarrollador)

Finalidad: Código fuente. El desarrollador no gestiona el despliegue.

```plaintext

repo-app/
├── src/
├── Dockerfile
└── .github/workflows/
└── main.yml # Llamada remota al template de GitOps
```

2. Guía de Instalación "From Scratch"
   Paso 1: Instalación de herramientas

Instala OpenTofu y las utilidades de gestión en tu máquina de control:
Bash

# OpenTofu (Linux)

curl -fsSL https://get.opentofu.org/opentofu.gpg | sudo tee /etc/apt/keyrings/opentofu.gpg
echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg] https://packages.opentofu.org/opentofu/opentofu/any/ any main" | sudo tee /etc/apt/sources.list.d/opentofu.list
sudo apt update && sudo apt install tofu

# Herramientas K8s

brew install kubectl talosctl istioctl

Paso 2: Aprovisionamiento de Nodos

Configura las etiquetas de los nodos físicos para separar cargas:
Bash

cd infra-provisioning/
tofu init
tofu apply -auto-approve

# Generar acceso al clúster

talosctl kubeconfig -n <IP_CONTROL_PLANE>

Paso 3: Despliegue del Plano de Control (ArgoCD + Istio)

Instalamos las herramientas en el Tier infra-tools:
Bash

# 1. ArgoCD con parche de nodo

kubectl create namespace infra-tools
kubectl apply -k k8s-lab-gitops/system/argocd/

# 2. Istio Ambient

istioctl install --set profile=ambient --namespace infra-tools -y
kubectl apply -f k8s-lab-gitops/system/istio/gateway.yaml

Paso 4: Despliegue de Aplicaciones (Dev & Prod)
Bash

kubectl apply -f k8s-lab-gitops/argo-apps/python-api-1-dev.yaml
kubectl apply -f k8s-lab-gitops/argo-apps/python-api-1-prod.yaml

3. Flujo Operativo del Día a Día

   Desarrollo: El programador hace git push.

   CI (Centralizado): GitHub Actions construye la imagen y actualiza automáticamente el tag en el repositorio de GitOps.

   Sincronización: ArgoCD detecta el cambio y aplica el Deployment en los nodos del Tier normal.

   Acceso: El tráfico llega al puerto 80 del nodo físico. Istio lo recibe y lo encamina al pod a través de la HTTPRoute.

4. Verificación del Sistema

Para confirmar que la arquitectura "Zero NodePort" funciona:
Bash

# Obtener IP de un nodo del Tier 'normal'

curl -I http://<IP_NODO_FISICO>/health

Resultado esperado: HTTP/1.1 200 OK
