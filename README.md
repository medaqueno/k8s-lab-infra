# Kubernetes Lab con Talos Linux

Guía para montar un clúster Kubernetes de aprendizaje usando Talos Linux en un nodo local.

## Prerequisitos

-   Talos Linux instalado en un PC en red local
-   Acceso a la red donde está el nodo
-   Permisos de administración en tu máquina local

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

Al arrancar desde la ISO, Talos entra en **Maintenance Mode**. En este estado el sistema está esperando recibir configuración. No hay servicios activos ni contraseñas configuradas por defecto.

**Primer paso:** Anota la IP que ha recibido el nodo por DHCP, por ejemplo `192.168.1.40`.

### Generar y aplicar configuración base

```bash
# Genera la configuración del clúster
talosctl gen config mi-cluster https://192.168.1.40:6443

# Integra la configuración en tu entorno local
talosctl config merge talosconfig

# Configura el endpoint y el nodo por defecto
talosctl config endpoint 192.168.1.40
talosctl config node 192.168.1.40
```

### Inicializar el clúster

```bash
# Bootstrap: arranca etcd y Kubernetes
talosctl bootstrap
```

Este proceso puede tardar un par de minutos. Es normal que salgan errores de autorización al principio. El resultado correcto final mostrará:

-   Stage: **Running**
-   Ready: **true**
-   Todos los componentes: **Healthy**

### Configurar kubectl

```bash
# Genera el kubeconfig para operar el clúster
talosctl kubeconfig > ~/.kube/config
```

## 3. Configuración de red estática

Por defecto Talos usa DHCP. Para asignar una IP fija:

### Identificar la interfaz de red

```bash
talosctl -n 192.168.1.40 ls /sys/class/net
```

Esto te devolverá el nombre de la interfaz, por ejemplo `enp3s0`.

### Modificar controlplane.yaml

Edita el archivo `controlplane.yaml` y añade esta configuración de red:

```yaml
machine:
    network:
        interfaces:
            - interface: enp3s0 # Usar el nombre que obtuviste antes
              dhcp: false
              addresses:
                  - 192.168.1.40/24
              routes:
                  - network: 0.0.0.0/0
                    gateway: 192.168.1.1
```

### Aplicar la nueva configuración

```bash
talosctl apply-config --file controlplane.yaml
```

## 4. Permitir workloads en el control plane

En un clúster de un solo nodo, el control plane tiene un taint que impide ejecutar workloads. Hay que eliminarlo:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
```

## 5. Desplegar aplicaciones de prueba

### Desplegar servidor echo

```bash
# Despliega un nginx que responde con código 200
kubectl apply -f echo-server.yaml
```

### Probar conectividad

```bash
# Lanza un pod temporal con curl para verificar
kubectl run curl-test --image=curlimages/curl -it --rm -- \
  curl -v echo-server-svc
```

### Desplegar cliente Python

```bash
# Despliega un cliente que llama al echo-server cada 5 segundos
kubectl apply -f python-client.yaml

# Ver los logs en tiempo real
kubectl logs -f deployment/python-client-deploy
```

Tras instalar las librerías necesarias, el cliente empezará a hacer peticiones cada 5 segundos y verás las respuestas 200 del nginx.

---

## Cheat sheet de comandos

### Talosctl - Gestión del clúster

```bash
# Estado general del clúster
talosctl dashboard

# Health check completo
talosctl health

# Ver versión
talosctl version

# Listar nodos
talosctl get members

# Ver logs del sistema
talosctl logs --tail

# Ver configuración aplicada
talosctl get machineconfig

# Reiniciar nodo
talosctl reboot

# Apagar nodo
talosctl shutdown

# Ejecutar comando en nodo
talosctl -n <IP> ls /path

# Ver servicios del sistema
talosctl services

# Ver estado de un servicio específico
talosctl service <nombre>
```

### Kubectl - Gestión de Kubernetes

```bash
# Estado del clúster
kubectl cluster-info
kubectl get nodes
kubectl get all --all-namespaces

# Trabajar con pods
kubectl get pods
kubectl get pods -o wide
kubectl describe pod <nombre>
kubectl logs <pod-name>
kubectl logs -f <pod-name>  # Seguir logs en tiempo real
kubectl exec -it <pod-name> -- /bin/sh

# Deployments
kubectl get deployments
kubectl describe deployment <nombre>
kubectl scale deployment <nombre> --replicas=3
kubectl rollout status deployment/<nombre>
kubectl rollout restart deployment/<nombre>

# Services
kubectl get services
kubectl describe service <nombre>

# Namespaces
kubectl get namespaces
kubectl create namespace <nombre>
kubectl config set-context --current --namespace=<nombre>

# Aplicar manifiestos
kubectl apply -f <archivo.yaml>
kubectl delete -f <archivo.yaml>

# Recursos
kubectl top nodes
kubectl top pods

# Debug
kubectl get events
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl describe node <nombre>

# Port forwarding
kubectl port-forward <pod-name> <local-port>:<pod-port>

# Eliminar recursos
kubectl delete pod <nombre>
kubectl delete deployment <nombre>
kubectl delete all --all  # Cuidado: borra todo en el namespace actual
```

### Talosctl - Configuración

```bash
# Cambiar contexto
talosctl config context <nombre>

# Ver configuración actual
talosctl config info

# Añadir endpoint
talosctl config endpoint <IP>

# Añadir nodo
talosctl config node <IP>

# Generar kubeconfig
talosctl kubeconfig
talosctl kubeconfig -f

# Actualizar configuración de máquina
talosctl apply-config --file <config.yaml>
```

## Troubleshooting

### El bootstrap no termina o da errores

-   Espera 2-3 minutos, es normal que tarde
-   Verifica que la IP sea accesible: `ping 192.168.1.40`
-   Comprueba el estado: `talosctl health`

### No puedo hacer kubectl

-   Verifica que el kubeconfig se haya generado: `cat ~/.kube/config`
-   Comprueba conectividad: `kubectl cluster-info`
-   Regenera el kubeconfig: `talosctl kubeconfig -f`

### Los pods quedan en Pending

-   Verifica el taint del control plane (paso 4)
-   Comprueba recursos: `kubectl describe node`
-   Revisa eventos: `kubectl get events`
