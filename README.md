Guía de Despliegue: Talos Linux & Kubernetes (Enfoque Enterprise)

Esta guía documenta la arquitectura, el provisionamiento y la validación de un clúster de Kubernetes basado en Talos Linux.

El documento abarca desde la configuración inicial explicada paso a paso en un entorno de laboratorio (Single Node) hasta la arquitectura de referencia para producción (High Availability), incluyendo estrategias de GitOps y comandos operativos esenciales.

🛠️ Instalación de Herramientas (CLI)

Antes de interactuar con el clúster, es necesario preparar la estación de administración (Management Plane). Estas herramientas nos permitirán hablar con la API de Talos y la API de Kubernetes.

macOS (Homebrew)

```sh
brew install siderolabs/tap/talosctl
brew install kubectl

# comprobar versión talos
talosctl version --client
```

Linux (Curl)

curl -sL [https://talos.dev/install](https://talos.dev/install) | sh
# Mueve el binario al path del sistema
sudo mv talosctl /usr/local/bin/


🏢 Arquitectura de Referencia: Entorno de Producción

En un entorno empresarial real, la arquitectura difiere del laboratorio en disponibilidad y separación de responsabilidades.

1. Topología Física (Bare-Metal)

En producción, el objetivo primordial es eliminar Puntos Únicos de Fallo (SPOF).

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


Control Plane (3 Nodos): Kubernetes requiere un número impar de nodos maestros para mantener el quórum de la base de datos etcd. Si un nodo cae, los otros dos mantienen el clúster vivo y operativo.

Virtual IP (VIP): Se configura una IP flotante (VIP) en capa 2 (ARP) o BGP. Tanto los workers como los administradores apuntan a esta VIP, desacoplando el servicio de la IP física de un nodo específico.

Worker Nodos (N Nodos): Dedicados exclusivamente a ejecutar aplicaciones de negocio. Se recomienda separarlos físicamente.

Red: Se utiliza Bonding (LACP) en las interfaces de red para redundancia de cables y switches.

2. Estrategia GitOps (Multi-Repositorio)

Para escalar el desarrollo y la gobernanza, separamos la definición de la infraestructura del código de las aplicaciones.

Repositorio

Responsabilidad

Contenido

infra-talos-fleet

Equipo Infraestructura

Configuración del OS Talos (machineconfig), definición de nodos, configuración de red física y upgrades del OS.

platform-core

Equipo Platform/SRE

Componentes base del clúster: CNI (Cilium), Ingress Controller, Cert-Manager, Storage (Rook), Observabilidad.

app-backend-billing

Equipo Desarrollo A

Código fuente Python/Go + Helm Chart de la aplicación.

app-frontend-store

Equipo Desarrollo B

Código fuente React/Nextjs + Manifiestos K8s.

🧪 Guía de Implementación Detallada (Laboratorio / Single Node)

A continuación se detallan los pasos para levantar el entorno de pruebas, explicando la razón técnica de cada fase.

1. Detección y Estado Inicial

Al arrancar la ISO de Talos Linux en el hardware, el sistema se detiene y muestra una pantalla de consola.

Estado: Maintenance

¿Por qué? Talos es inmutable y seguro por defecto. No arranca con contraseñas por defecto ni servicios expuestos. Se queda esperando en un bucle infinito a que un administrador le inyecte una configuración firmada.

Acción: Mira el monitor y anota la dirección IP asignada por DHCP (ej: 192.168.1.41).

2. Generación de la Identidad del Clúster

En tu máquina local (Mac/Linux), definimos qué es este clúster. Este comando genera los certificados de autoridad (CA), las claves de encriptación y los ficheros YAML de configuración.

# 'mi-cluster' es el nombre lógico
# La URL es el endpoint donde la API escuchará peticiones
talosctl gen config mi-cluster [https://192.168.1.41:6443](https://192.168.1.41:6443)


Esto genera controlplane.yaml (para el nodo maestro), worker.yaml (para nodos futuros) y talosconfig (tu llave maestra).

3. Inyección de Configuración (Apply)

Ahora enviamos la configuración al nodo que está en espera.

# Usamos --insecure porque el nodo usa certificados temporales en modo mantenimiento.
# Una vez reciba la config, generará sus propios certificados seguros.
talosctl apply-config --insecure --nodes 192.168.1.41 --file controlplane.yaml


El nodo se reiniciará automáticamente, formateará el disco, instalará el OS en memoria y aplicará la configuración de red.

4. Configuración del Cliente Local

Para no tener que escribir la IP (--nodes) y el endpoint (--endpoints) en cada comando, los guardamos en nuestra configuración local.

talosctl config endpoint 192.168.1.41
talosctl config node 192.168.1.41


5. Bootstrap del Clúster (El Disparo de Salida)

Aunque el nodo ya tiene configuración, la base de datos etcd no arranca sola.

¿Por qué? Para prevenir "Split-Brain". Si tuvieras 3 nodos, Talos no sabe cuál debe iniciar el clúster. Debemos decirle explícitamente al primer nodo: "Tú eres el líder inicial".

talosctl bootstrap


Tras este comando, Kubernetes iniciará. Puedes monitorizarlo con talosctl dashboard.

6. Obtención de Acceso (Kubeconfig)

Talos gestiona sus propios certificados para la API de Kubernetes. Debemos extraerlos para usar kubectl.

talosctl kubeconfig > ~/.kube/config


7. Habilitar Cargas de Trabajo (Taint Removal)

⚠️ Concepto Arquitectónico: Por defecto, Kubernetes protege el plano de control aplicando un Taint (NoSchedule). Esto impide que tus aplicaciones consuman CPU/RAM reservada para el sistema.

En Lab: Como solo tenemos un nodo, debemos quitar esta protección para poder desplegar nuestras apps.

# El '-' al final indica la eliminación de la regla
kubectl taint node <nombre-del-nodo> node-role.kubernetes.io/control-plane:NoSchedule-


📦 Despliegue de Aplicaciones (Validación)

Para confirmar que la red (CNI) y el DNS funcionan, desplegamos dos servicios que se comuniquen entre sí.

echo-server.yaml (Backend)

Servidor Nginx simple escuchando en puerto 80.

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

Aplicamos el servidor y lanzamos un pod cliente temporal para probar la resolución DNS interna.

# 1. Desplegar servidor
kubectl apply -f echo-server.yaml

# 2. Validar comunicación (DNS + HTTP)
# Creamos un pod con curl, lanzamos la petición y lo borramos (--rm) al terminar
kubectl run curl-test --image=curlimages/curl -it --rm -- curl -v echo-server-svc


Éxito: Si recibes un HTTP 200 OK, tu clúster es funcional.

⚡ Cheatsheet: Comandos Esenciales

Resumen rápido para la operación diaria y resolución de problemas.

🐧 Gestión del Nodo (Talosctl)

Acción

Comando

Descripción

Dashboard

talosctl dashboard

Panel visual en terminal con métricas y logs en tiempo real.

Listar procesos

talosctl ps

Muestra procesos internos de Linux (containerd, kubelet, udevd).

Logs del sistema

talosctl logs <service>

Ej: talosctl logs kubelet o talosctl logs etcd para depurar el arranque.

Reiniciar nodo

talosctl reboot

Reinicio ordenado (drena el nodo primero si es posible).

Upgrade OS

talosctl upgrade --image <url>

Actualización atómica del sistema operativo preservando la configuración.

Reset

talosctl reset

Peligroso: Borra todo el disco y devuelve el nodo a estado de mantenimiento.

☸️ Gestión del Clúster (Kubectl)

Acción

Comando

Descripción

Estado Nodos

kubectl get nodes -o wide

IPs, Versión K8s, OS Image y estado (Ready/NotReady).

Todos los Pods

kubectl get pods -A

Ver pods de sistema (CoreDNS, CNI) y usuario a la vez.

Logs App

kubectl logs -f -l app=<label>

Sigue los logs de todos los pods con esa etiqueta.

Debug Pod

kubectl describe pod <nombre>

Fundamental para ver errores de ImagePullBackOff o falta de recursos.

Shell Remota

kubectl exec -it <pod> -- sh

Entrar dentro del contenedor para depurar red/archivos.

Reiniciar App

kubectl rollout restart deployment/<nombre>

Fuerza la recreación de los pods sin borrar el deployment.