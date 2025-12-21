Guía Operacional: Pipeline CI/CD + GitOps con ArgoCD

Esta guía cubre el proceso completo de despliegue automatizado de la aplicación python-api-1 usando GitHub Actions (CI/CD) y ArgoCD (GitOps) en el clúster.

1. Acceso y Setup Inicial de ArgoCD

ArgoCD es nuestro motor GitOps. Necesita permisos para leer el clúster y las definiciones de la aplicación para existir.

1.1 Obtener la Contraseña de Administrador

La contraseña inicial se obtiene del Secreto de Kubernetes (asumiendo que ArgoCD está en el namespace infra-tools):

kubectl -n infra-tools get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

1.2 Acceder a la Interfaz Web (UI)

Crea un túnel seguro desde tu máquina local al servicio de ArgoCD.

# Ejecutar en segundo plano

kubectl port-forward svc/argocd-server -n infra-tools 8080:443 &

Luego, accede a https://localhost:8080 e inicia sesión con el usuario admin y la contraseña obtenida.

1.3 Solucionar Error de Permisos (RBAC)

Si ArgoCD muestra un error UnknownError: failed to list resources (debido a falta de permisos para listar ConfigMaps o Secrets), debes otorgar el rol cluster-admin al controlador de aplicaciones:

kubectl create clusterrolebinding argocd-controller-admin-binding \
 --clusterrole=cluster-admin \
 --serviceaccount=infra-tools:argocd-application-controller

2. Configuración de Manifiestos Base (Kustomize)

La base del manifiesto debe estar alineada para que Kustomize pueda parchear la imagen que viene de CI/CD.

2.1 Asegurar la Alineación de la Imagen Base

El archivo apps/python-api-1/base/deployment.yaml debe usar el nombre completo de la imagen sin el tag, que debe coincidir con el campo name en el kustomization.yaml.

# En apps/python-api-1/base/deployment.yaml

      containers:
        - name: app
          # Nombre base que Kustomize reemplazará
          image: ghcr.io/medaqueno/k8s-lab-apps-python-api-1
          # ...

3. Activación del Despliegue GitOps (Aplicación ArgoCD)

La aplicación ArgoCD le indica al motor qué repositorio, ruta y destino debe monitorear.

3.1 Aplicar la Definición de la Aplicación

Asegúrate de que el manifiesto de la aplicación (k8s-lab-gitops/argo-apps/python-api-1-dev.yaml) contenga el campo obligatorio project: default y apunte al namespace correcto (infra-tools).

# Aplicar la definición de la aplicación al clúster

kubectl apply -f k8s-lab-gitops/argo-apps/python-api-1-dev.yaml

Nota: Una vez aplicado, ArgoCD debe aparecer en la UI y pasar a Synced / Healthy.

4. Verificación y Debugging Post-Despliegue

4.1 Comprobar la Versión de la Imagen Desplegada

Para confirmar que el ciclo CI/CD -> GitOps -> Kubernetes está completo, verifica que el tag (SHA del commit) en los pods coincide con el último tag actualizado por GitHub Actions.

# 1. Muestra la imagen que realmente se está ejecutando en el namespace de desarrollo

kubectl get pods -n python-api-1-dev -o jsonpath="{.items[*].spec.containers[*].image}"

# Resultado esperado: ghcr.io/medaqueno/k8s-lab-apps-python-api-1:<último-SHA>

4.2 Acceder a la API para Pruebas (Port-Forwarding)

Para probar la API de Python sin usar el HTTPRoute de Istio (que requiere DNS y configuración externa), puedes crear un túnel directo al servicio de Kubernetes.

# Redirige el puerto 8081 de tu máquina al puerto 80 del Service en el clúster.

kubectl port-forward svc/python-api-1-svc -n python-api-1-dev 8081:80 &

Puedes acceder a la API desde http://localhost:8081/.

4.3 Verificación de la Sincronización en la UI de ArgoCD

Una vez que GitHub Actions hace el push del nuevo tag al repositorio GitOps, la aplicación en ArgoCD debería mostrar esta secuencia:

Estado: Pasa a OutOfSync (ArgoCD detecta el cambio en Git).

Sincronización: Pasa a Syncing (ArgoCD está aplicando Kustomize y el nuevo Deployment).

Finalización: Regresa a Synced y Healthy (El nuevo Deployment está listo).
