#!/bin/bash

set -e

echo "Installing Helm Repos"

helm repo add argo https://argoproj.github.io/argo-helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

echo "Creating namespaces"


kubectl create namespace argocd || true
kubectl create namespace monitoring || true

echo "Installing ArgoCD"

helm install argocd argo/argo-cd -n argocd

echo "Installing Prometheus"

helm install prometheus prometheus-community/prometheus -n monitoring

echo "Installing Grafana"

helm install grafana grafana/grafana -n monitoring


