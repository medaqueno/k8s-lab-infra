# Kubernetes Resource Naming & Labeling Conventions

This document defines the naming conventions for all Kubernetes resources. It distinguishes between **Physical Naming** (the resource name) and **Logical Tiering** (labels).

## 1. General Principles

1.  **Labels over Prefixes**: Use labels to categorize resources (Tiers, Environments, Owners) instead of adding long prefixes to their names.
2.  **Standard Names**: For system and platform tools, use their standard community names (`istio-system`, `argocd`, `prometheus`) to ensure compatibility with Helm charts and documentation.
3.  **Consistency**: Follow the same pattern across all user applications.
4.  **K8s Compliance**: Max 63 characters, lowercase alphanumeric and hyphens only.

---

## 2. Tiers vs. Namespaces

In this lab, **Tiers** are logical metadata categories, not part of the physical name of the namespace.

| Physical Name (Namespace) | Logical Tier (Label: `tier`) | Description |
| :--- | :--- | :--- |
| `istio-system` | `platform` | Mesh infrastructure. |
| `argocd` | `platform` | GitOps delivery tools. |
| `platform-tools` | `platform` | Generic management utilities. |
| `dev-demo-app` | `applications` | Development user workload. |
| `prod-demo-app` | `applications` | Production user workload. |

---

## 3. Resource Naming Patterns

### 3.1 Namespaces
**Pattern**: `<environment>-<app-name>` (for apps) or `<app-name>` (for platform).

**Examples**:
- `dev-demo-app`
- `istio-system`
- `argocd`

### 3.2 Resources (Deployments, Services, etc.)
**Pattern**: `<app-name>-<resource-type>`

**Examples**:
- `demo-app-deploy`
- `redis-service`
- `postgres-config`

---

## 4. Labeling Strategy (The "Tier" Logic)

Every resource must carry standard labels to allow logical filtering.

### 4.1 System Labels
| Key | Example Value |
| :--- | :--- |
| `app.kubernetes.io/name` | `demo-app` |
| `app.kubernetes.io/part-of` | `k8s-lab` |
| `app.kubernetes.io/managed-by` | `argocd` |

### 4.2 Tier Labels (Mandatory)
Used to distinguish between platform tools and user apps.
- **Key**: `tier`
- **Values**: `platform`, `applications`, `system`

### 4.3 Environment Labels
- **Key**: `environment`
- **Values**: `development`, `staging`, `production`

---

## 5. Summary Table (Naming vs. Tiers)

| Resource | Name Example | Tier Label | Environment Label |
| :--- | :--- | :--- | :--- |
| ArgoCD Server | `argocd-server` | `platform` | `production` |
| Istiod | `istiod` | `platform` | `system` |
| Python App Pod | `python-api-pod` | `applications` | `development` |

---

## 6. Best Practices

1.  **Avoid Redundancy**: Don't name something `argocd-platform-namespace`. Use `argocd` and label it `tier=platform`.
2.  **Standard Suffixes**: Use short suffixes for clarity: `-deploy`, `-svc`, `-config`, `-secret`.
3.  **No Dots or Underscores**: Always use hyphens (`-`).