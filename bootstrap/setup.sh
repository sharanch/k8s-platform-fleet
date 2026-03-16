#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }

step "Starting management cluster"
minikube start --profile management-cluster --cpus 2 --memory 3072 --driver docker
ok "management-cluster ready"

step "Starting workload cluster"
minikube start --profile workload-cluster --cpus 2 --memory 2048 --driver docker
ok "workload-cluster ready"

step "Connecting cluster networks"
docker network connect management-cluster workload-cluster 2>/dev/null || true
docker network connect workload-cluster management-cluster 2>/dev/null || true
ok "Networks connected"

step "Installing ArgoCD on management cluster"
kubectl config use-context management-cluster
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml \
  --server-side --force-conflicts
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
kubectl rollout status deployment/argocd-applicationset-controller -n argocd --timeout=180s
ok "ArgoCD ready"

step "Setting up port-forward"
pkill -f "port-forward.*argocd" 2>/dev/null || true
sleep 2
kubectl port-forward svc/argocd-server -n argocd 8080:443 \
  --context management-cluster &>/dev/null &
sleep 5
ok "Port-forward active"

step "Logging into ArgoCD"
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd --context management-cluster \
  -o jsonpath='{.data.password}' | base64 -d)
argocd login localhost:8080 \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure
ok "Logged in (password: $ARGOCD_PASSWORD)"

step "Registering workload cluster"
argocd cluster add workload-cluster --insecure --yes
ok "workload-cluster registered"

step "Deploying ApplicationSet"
kubectl apply -f applicationsets/sample-app.yaml --context management-cluster
ok "ApplicationSet deployed"

step "Setting up app port-forwards"
sleep 15
kubectl port-forward svc/sample-app 8081:80 -n sample-app \
  --context management-cluster &>/dev/null &
kubectl port-forward svc/sample-app 8082:80 -n sample-app \
  --context workload-cluster &>/dev/null &
sleep 3

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  k8s-platform-fleet deployed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  ArgoCD UI      →  https://localhost:8080  (admin / $ARGOCD_PASSWORD)"
echo "  Management app →  http://localhost:8081"
echo "  Workload app   →  http://localhost:8082"
echo ""
