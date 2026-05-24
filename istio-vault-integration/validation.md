# Validation & Local Access Guide

This guide details how to configure your local machine (macOS) to securely access the Vault instance and the Istio-protected applications running inside the Kind cluster using their proper domain names.

## 1. Network Routing (macOS Docker limitation)
By default, Docker Desktop for Mac runs in a lightweight VM, meaning host-to-container IP routing is not natively supported. To route traffic from your Mac directly to the `mesh-network` (`10.10.0.0/16`), you need to use `docker-mac-net-connect`.

If you haven't already installed it, run:
```bash
# Install the tool
brew install chipmk/tap/docker-mac-net-connect

# Start the service to automatically configure routing
sudo brew services start chipmk/tap/docker-mac-net-connect
```
*This allows your Mac to ping and access IPs like `10.10.0.10` (Vault) and `10.10.0.100` (Istio Gateway) directly.*

## 2. DNS Resolution (/etc/hosts)
To access the services using their subdomains, your machine needs to know which IP addresses to connect to. First, make sure you have exported your root domain:
```bash
export ROOT_DOMAIN="yourdomain.com" # e.g. ratlab.dev
```

Add the following entries to your `/etc/hosts` file (requires `sudo`), replacing `${ROOT_DOMAIN}` with your actual domain value:

```text
# Istio & Vault Integration Environment
10.10.0.10   vault.ops.${ROOT_DOMAIN}
10.10.0.100  app1.ops.${ROOT_DOMAIN} app2.ops.${ROOT_DOMAIN} app3.ops.${ROOT_DOMAIN} app4.ops.${ROOT_DOMAIN} app5.ops.${ROOT_DOMAIN}
```

## 3. Trust the Root CA
All endpoints are secured via TLS certificates issued by our Vault PKI. To prevent your browser from showing security warnings ("Your connection is not private"), you must add the Root CA to your macOS System Keychain.

Run the following command to download and trust the certificate:
```bash
# Download root CA from Vault
curl -s http://10.10.0.10:80/v1/pki_root/ca/pem > root-ca.crt

# Trust the Root CA
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain root-ca.crt

# Clean up local file
rm root-ca.crt
```

## 4. Validating the Setup

Now that networking, DNS, and TLS trust are fully configured, you can reach the services seamlessly from your browser or terminal!

### Accessing Vault
- **Browser:** Navigate to `https://vault.ops.${ROOT_DOMAIN}:443` (substitute your configured root domain)
- You should see the Vault UI securely load with a green padlock.
- *Login Info:* The Root token is saved in `certs/vault_root_token.txt`.

### Accessing Applications (Istio Gateway)
- **Browser:** Navigate to `https://app1.ops.${ROOT_DOMAIN}` (substitute your configured root domain)
- You should see the `httpbin` Swagger UI/JSON response load over a secure connection!
- **Terminal (curl):**
  ```bash
  curl -sS https://app2.ops.${ROOT_DOMAIN}/headers
  ```
  *(You should get a JSON response without any `curl -k` or `--cacert` flags because the root CA is now trusted by your system!)*

---

### Clean Up / Teardown
When you are done testing, you can tear everything down by navigating to `terraform/single-setup` and running:
```bash
terraform destroy -auto-approve
```

To remove the Root CA trust from your macOS System Keychain, run:
```bash
# Retrieve Root CA again if needed to target it for removal
curl -s http://10.10.0.10:80/v1/pki_root/ca/pem > root-ca.crt
sudo security remove-trusted-cert -d root-ca.crt
rm root-ca.crt
```
*(If you want to completely delete the certificate from the keychain instead of just removing the trust, run `sudo security delete-certificate -c "${ROOT_DOMAIN} Root CA" /Library/Keychains/System.keychain`)*
