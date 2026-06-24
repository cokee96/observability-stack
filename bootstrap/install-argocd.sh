#!/usr/bin/env bash
# ==============================================================================
# bootstrap/install-argocd.sh
#
# One-time bootstrap script to install ArgoCD on a Kubernetes cluster and
# apply the root App of Apps that manages all observability components.
#
# PREREQUISITES:
#   - kubectl configured and pointing at the target cluster
#   - ENVIRONMENT variable set to one of: dev | pre | prod
#     This value is stored as an ArgoCD ConfigMap entry and consumed by
#     Applications via the $ARGOCD_ENV_environment variable in valueFiles.
#
# USAGE:
#   export ENVIRONMENT=dev   # or pre / prod
#   bash bootstrap/install-argocd.sh
#
# WHAT THIS SCRIPT DOES:
#   1. Creates the argocd namespace
#   2. Installs ArgoCD from the upstream stable manifests
#   3. Waits for the argocd-server Deployment to be fully ready
#   4. Patches the argocd-cm ConfigMap to inject the environment name
#   5. Applies the root Application (App of Apps) from bootstrap/root-app.yaml
#   6. Prints the initial admin password
#   7. Prints the port-forward command to access the ArgoCD UI
# ==============================================================================

set -euo pipefail

# ── Validate ENVIRONMENT ──────────────────────────────────────────────────────
ENVIRONMENT="${ENVIRONMENT:-}"
if [[ -z "${ENVIRONMENT}" ]]; then
  echo "ERROR: ENVIRONMENT is not set."
  echo "       Export it before running this script:"
  echo "         export ENVIRONMENT=dev   # or pre / prod"
  exit 1
fi

if [[ ! "${ENVIRONMENT}" =~ ^(dev|pre|prod)$ ]]; then
  echo "ERROR: ENVIRONMENT must be one of: dev, pre, prod (got '${ENVIRONMENT}')"
  exit 1
fi

echo "=============================================="
echo "  ArgoCD bootstrap"
echo "  Environment : ${ENVIRONMENT}"
echo "=============================================="

# ── 1. Create namespace ───────────────────────────────────────────────────────
echo ""
echo "[1/6] Creating namespace argocd ..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# ── 2. Install ArgoCD ─────────────────────────────────────────────────────────
echo ""
echo "[2/6] Installing ArgoCD (stable manifests) ..."
kubectl apply \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  -n argocd

# ── 3. Wait for argocd-server ─────────────────────────────────────────────────
echo ""
echo "[3/6] Waiting for argocd-server to be ready (this may take a few minutes) ..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s

# ── 4. Inject environment into ArgoCD ConfigMap ───────────────────────────────
echo ""
echo "[4/6] Patching argocd-cm with environment=${ENVIRONMENT} ..."
kubectl patch configmap argocd-cm \
  -n argocd \
  --type merge \
  -p "{\"data\":{\"environment\":\"${ENVIRONMENT}\"}}"

# ── 5. Apply root App of Apps ─────────────────────────────────────────────────
echo ""
echo "[5/6] Applying root Application (App of Apps) ..."
kubectl apply -f bootstrap/root-app.yaml -n argocd

# ── 6. Print initial admin password ──────────────────────────────────────────
echo ""
echo "[6/6] Retrieving initial admin password ..."
ADMIN_PASSWORD=$(
  kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath="{.data.password}" \
  | base64 -d
)

echo ""
echo "=============================================="
echo "  Bootstrap complete!"
echo "=============================================="
echo ""
echo "  ArgoCD admin credentials"
echo "  Username : admin"
echo "  Password : ${ADMIN_PASSWORD}"
echo ""
echo "  To access the ArgoCD UI, run:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo ""
echo "  TIP: Change the admin password immediately after first login:"
echo "    argocd login localhost:8080 --insecure"
echo "    argocd account update-password"
echo ""
echo "  The root App of Apps has been applied."
echo "  ArgoCD will now reconcile all observability components automatically."
echo "=============================================="
