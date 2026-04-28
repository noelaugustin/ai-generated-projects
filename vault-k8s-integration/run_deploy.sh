#!/bin/bash
set -e

echo "Cleaning up..."
kind delete cluster --name cluster-1 || true
kind delete cluster --name cluster-2 || true
docker rm -f vault || true
rm -f terraform.tfstate*

echo "Updating terraform script..."
# Ensure ALL vault items depend on the time_sleep which depends on the container!
sed -i '' 's/resource "vault_auth_backend" "kubernetes_cluster1" {/resource "vault_auth_backend" "kubernetes_cluster1" {\n  depends_on = [time_sleep.wait_for_vault]/' vault_config.tf
sed -i '' 's/resource "vault_auth_backend" "kubernetes_cluster2" {/resource "vault_auth_backend" "kubernetes_cluster2" {\n  depends_on = [time_sleep.wait_for_vault]/' vault_config.tf

echo "Applying Terraform..."
terraform apply -auto-approve
