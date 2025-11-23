Guía de Despliegue: Talos Linux & Kubernetes (Enfoque Enterprise)

Esta guía documenta la arquitectura, el provisionamiento y la validación
de un clúster de Kubernetes basado en Talos Linux.
Incluye desde el entorno de laboratorio (Single Node) hasta una
arquitectura de referencia de producción (High Availability), con
estrategias GitOps y comandos operativos.

------------------------------------------------------------------------

🛠️ Instalación de Herramientas (CLI)

Antes de interactuar con el clúster, hay que preparar la estación de
administración (Management Plane).

macOS (Homebrew)

    brew install siderolabs/tap/talosctl
    brew install kubectl

    # Comprobar versión talos
    talosctl version --client

Linux (Curl)

    curl -sL https://talos.dev/install | sh
    sudo mv talosctl /usr/local/bin/

------------------------------------------------------------------------

🏢 Arquitectura de Referencia: Entorno de Producción

En un entorno empresarial real, la arquitectura difiere radicalmente del
laboratorio en disponibilidad y separación de responsabilidades.

1. Topología Física (Bare-Metal)

Objetivo: eliminar puntos únicos de fallo (SPOF).

    graph TD
        subgraph "Control Plane (Quorum etcd)"
            CP1[Nodo CP 1]
            CP2[Nodo CP 2]
            CP3[Nodo CP 3]
        end

        subgraph "Data Plane (Workloads)"
            W1[Worker 1 - Zona A]
            W2[Worker 2 - Zona B]
            W3[Worker 3 - Zona C]
        end

        LB[Virtual IP / Load Balancer] --> CP1
        LB --> CP2
        LB --> CP3

        W1 -.-> LB
        W2 -.-> LB
        W3 -.-> LB

Componentes:

-   Control Plane (3 nodos): quórum etcd garantizado.
-   VIP (Virtual IP): IP flotante por L2/BGP.
-   Workers (N nodos): dedicados a cargas de trabajo.
-   Red: Bonding (LACP) para evitar fallos de red.

------------------------------------------------------------------------

2. Estrategia GitOps (Multi-Repositorio)

Separación clara entre infraestructura, plataforma y aplicaciones.

  ---------------------------------------------------------------------------------
  Repositorio           Responsabilidad   Contenido
  --------------------- ----------------- -----------------------------------------
  infra-talos-fleet     Equipo            Configuración OS Talos, machineconfigs,
                        Infraestructura   red física, upgrades del OS.

  platform-core         Equipo            CNI, Ingress, Cert-Manager, Storage,
                        Platform/SRE      Observabilidad.

  app-backend-billing   Equipo Desarrollo Código Python/Go + Helm chart.
                        A

  app-frontend-store    Equipo Desarrollo Código React/NextJS + manifiestos K8s.
                        B
  ---------------------------------------------------------------------------------

------------------------------------------------------------------------

🧪 Guía de Implementación (Laboratorio / Single Node)

1. Detección y Estado Inicial

Al arrancar la ISO, Talos entra en Maintenance Mode esperando la
configuración.

-   Estado: Maintenance
-   Por qué: OS inmutable sin contraseñas ni servicios.
-   Acción: Anota la IP asignada por DHCP (ej. 192.168.1.41).

------------------------------------------------------------------------

2. Generación de Identidad del Clúster

Genera certificados CA, claves y la configuración inicial.

    talosctl gen config mi-cluster https://192.168.1.41:6443

Salida:

-   controlplane.yaml
-   worker.yaml
-   talosconfig

------------------------------------------------------------------------

3. Inyección de Configuración (Apply)

    talosctl apply-config --insecure --nodes 192.168.1.41 --file controlplane.yaml

El nodo se reinicia y aplica la configuración.

------------------------------------------------------------------------

4. Configuración del Cliente Local

    talosctl config endpoint 192.168.1.41
    talosctl config node 192.168.1.41

------------------------------------------------------------------------

5. Bootstrap del Clúster

    talosctl bootstrap

Monitorización:

    talosctl dashboard

------------------------------------------------------------------------

6. Obtención del Kubeconfig

    talosctl kubeconfig > ~/.kube/config

------------------------------------------------------------------------

7. Habilitar Cargas de Trabajo (Taint Removal)

    kubectl taint node <nombre-del-nodo> node-role.kubernetes.io/control-plane:NoSchedule-

------------------------------------------------------------------------

📦 Despliegue de Aplicaciones (Validación)

echo-server.yaml

    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: echo-server-deploy
      labels:
        app: echo-server
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: echo-server
      template:
        metadata:
          labels:
            app: echo-server
        spec:
          containers:
          - name: echo-server
            image: nginx:latest
            ports:
            - containerPort: 80
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: echo-server-svc
    spec:
      selector:
        app: echo-server
      ports:
      - port: 80
        targetPort: 80
      type: ClusterIP

Prueba de Conectividad

    kubectl apply -f echo-server.yaml

    kubectl run curl-test --image=curlimages/curl -it --rm -- \
      curl -v echo-server-svc

------------------------------------------------------------------------

⚡ Cheatsheet: Comandos Esenciales

🐧 Talos (talosctl)

  ----------------------------------------------------------------------------------
  Acción      Comando                          Descripción
  ----------- -------------------------------- -------------------------------------
  Dashboard   talosctl dashboard               Métricas y logs en tiempo real.

  Listar      talosctl ps                      Procesos internos del nodo.
  procesos

  Logs del    talosctl logs <service>          Ej.: kubelet, etcd.
  sistema

  Reiniciar   talosctl reboot                  Reinicio ordenado.
  nodo

  Upgrade OS  talosctl upgrade --image <url>   Actualización atómica.

  Reset       talosctl reset                   Revierte a Maintenance Mode (⚠️
                                               destruye datos).
  ----------------------------------------------------------------------------------

------------------------------------------------------------------------

☸️ Kubernetes (kubectl)

  ---------------------------------------------------------------------------------------
  Acción      Comando                                  Descripción
  ----------- ---------------------------------------- ----------------------------------
  Estado      kubectl get nodes -o wide                IPs, versión, estado.
  nodos

  Todos los   kubectl get pods -A                      Sistema + usuario.
  pods

  Logs app    kubectl logs -f -l app=<label>           Sigue logs por etiqueta.

  Debug pod   kubectl describe pod <nombre>            Información detallada.

  Shell       kubectl exec -it <pod> -- sh             Acceso al contenedor.
  remota

  Reiniciar   kubectl rollout restart deployment/...   Recrea pods sin borrar el
  app                                                  deployment.
  ---------------------------------------------------------------------------------------
