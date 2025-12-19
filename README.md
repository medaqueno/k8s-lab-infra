# Kubernetes Lab con Talos Linux

Guía para montar un clúster Kubernetes de aprendizaje usando Talos Linux en un nodo local.

## Prerequisitos

- Talos Linux instalado en un PC en red local
- Acceso a la red donde está el nodo
- Permisos de administración en tu máquina local

## 1. Instalación de herramientas CLI

### macOS con Homebrew

```bash
brew install siderolabs/tap/talosctl
brew install kubectl

# Verificar instalación
talosctl version --client
```

### Linux con curl

```bash
curl -sL https://talos.dev/install | sh
sudo mv talosctl /usr/local/bin/
```

## 2. Configuración inicial del clúster

1. Instalación de ArgoCD (vía GitOps)

Para seguir tu estructura, instalaremos ArgoCD en el namespace infra-tools y nos aseguraremos de que sus pods se ejecuten únicamente en los nodos etiquetados para infraestructura.

Comandos iniciales (Bootstrap):

```bash

# 1. Crear el namespace dedicado

kubectl create namespace infra-tools

# 2. Instalación estándar de ArgoCD

kubectl apply -n infra-tools -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Parche de Kustomize para el Tier infra-tools: Para que ArgoCD respete tu jerarquía de nodos, crea en tu repo k8s-gitops/system/argocd/kustomization.yaml:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Forzamos a que todos los componentes de Argo vayan al hierro de gestión
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: add
        path: /spec/template/spec/nodeSelector
        value:
          node-role.kubernetes.io/tier: "infra-tools"
```

---

2. Istio Ambient

Aquí es donde resolvemos el hacer pública tu API de forma profesional. Istio Ambient no usa sidecars (es más ligero) y utiliza un componente llamado Ztunnel y Gateway.
A. Instalación de Istio Ambient

Usaremos istioctl (instálalo en tu máquina local primero). El perfil ambient es el que necesitas:

```bash
istioctl install --set profile=ambient --set values.global.hub=docker.io/istio --namespace infra-tools -y
```

B. El Gateway (Tu nueva IP pública)

En lugar de NodePort, crearemos un Gateway. Este objeto de Istio levantará un balanceador (o escuchará en los puertos 80/443 del nodo) y redirigirá el tráfico.

k8s-gitops/system/istio/gateway.yaml

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: infra-tools
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All # Permite que apps de otros namespaces se conecten
```

C. Conectando la API: HTTPRoute

Ahora le decimos a Istio: "Si alguien viene por el puerto 80, envíalo al servicio de mi API".

k8s-gitops/apps/python-api-1/overlays/prod/httproute.yaml

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: python-api-route
  namespace: python-api-1-prod
spec:
  parentRefs:
    - name: main-gateway
      namespace: infra-tools
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: python-api-1-svc
          port: 80
```

3. ¿Cómo queda el flujo ahora?

   Tráfico: Llega a la IP de tu nodo físico (tier normal o infra-tools según configures el Gateway).

   Istio Gateway: Recibe la petición en el puerto 80.

   HTTPRoute: Mira la regla y dice: "Esto va para el servicio python-api-1-svc".

   Ztunnel (Ambient): Transporta el tráfico de forma segura dentro del clúster hasta el pod de la aplicación.

---

Para que ArgoCD pueda desplegar la aplicación, necesitamos que los manifiestos en el repositorio de GitOps sean definitivos y sigan el estándar de Istio Ambient (sin NodePorts).

Aquí tienes el contenido de los archivos que faltan para python-api-1, estructurados para que el desarrollador no tenga que tocarlos y tú los gestiones vía GitOps.

1. Los Manifiestos de la Aplicación (Repo GitOps)

Ubicación: k8s-gitops/apps/python-api-1/
A. Base: base/deployment.yaml

Este es el esqueleto. Fíjate en el nodeSelector que comentamos para forzar el tier normal.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-api-1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: python-api-1
  template:
    metadata:
      labels:
        app: python-api-1
    spec:
      nodeSelector:
        node-role.kubernetes.io/tier: "normal"
      containers:
        - name: app
          image: app-image # Kustomize reemplazará esto automáticamente
          ports:
            - containerPort: 8000
          envFrom:
            - configMapRef:
                name: python-api-1-config
```
