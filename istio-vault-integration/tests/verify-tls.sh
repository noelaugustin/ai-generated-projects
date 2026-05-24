#!/bin/bash
set -e

# Force the user to set the ROOT_DOMAIN environment variable
if [ -z "$ROOT_DOMAIN" ]; then
  echo "ERROR: The ROOT_DOMAIN environment variable is not set."
  echo "Please set it before running this script. Example:"
  echo "  export ROOT_DOMAIN=\"yourdomain.com\""
  exit 1
fi
echo "Using Root Domain: $ROOT_DOMAIN"
DIR="$(dirname "$0")"

CA_CERT_TEMP=$(mktemp)
trap 'rm -f "$CA_CERT_TEMP"' EXIT
curl -sS http://10.10.0.10:80/v1/pki_root/ca/pem > "$CA_CERT_TEMP"
CA_CERT="$CA_CERT_TEMP"

echo "======================================"
echo " Verifying Vault TLS "
echo "======================================"
curl -sS --cacert "$CA_CERT" https://vault.ops.$ROOT_DOMAIN:443/v1/sys/health --resolve vault.ops.$ROOT_DOMAIN:443:10.10.0.10 | jq . || echo "Failed to connect to Vault"

echo "======================================"
echo " Verifying Application Subdomains TLS"
echo "======================================"
# Get the LoadBalancer IP of the Gateway
LB_IP=$(kubectl get svc -n apps httpbin-gateway-istio -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --context kind-mesh-cluster || echo "")

if [ -z "$LB_IP" ]; then
  echo "LoadBalancer IP not found. Is the gateway ready?"
  exit 1
fi

echo "Gateway LoadBalancer IP: $LB_IP"

for i in {1..5}; do
  DOMAIN="app$i.ops.$ROOT_DOMAIN"
  echo "Testing https://$DOMAIN directly from host..."
  
  # Thanks to docker-mac-net-connect, we can reach LB_IP directly
  curl -sS --cacert "$CA_CERT" --resolve $DOMAIN:443:$LB_IP https://$DOMAIN/get | grep "url" || echo "Failed for $DOMAIN"
  echo "Success for $DOMAIN!"
done
