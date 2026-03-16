#!/usr/bin/env bash
pkill -f "port-forward" 2>/dev/null || true
minikube delete --profile management-cluster
minikube delete --profile workload-cluster
echo "Torn down."
