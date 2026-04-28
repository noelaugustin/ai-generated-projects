# Hardened SSH Certificate Authority Infrastructure

This repository implements a production-ready, SSH-native Certificate Authority (CA) infrastructure. It utilizes a Dual-Root CA architecture, protocol isolation via dual SSH processes, and principal-based identity mapping to eliminate password reliance and Host Key (TOFU) prompts.

## Architecture Overview

The system consists of three primary components:

### 1. CA Server (`ca-server`)
The trusted authority. It runs two independent `sshd` processes:
*   **Issuance Port (22)**: Dedicated to signing certificates.
    *   **Auth**: Password only (`username=password`).
    *   **Restricted**: Users are locked into issuance scripts via `ForceCommand`.
    *   **Harden**: Only presents a CA-signed host certificate.
*   **Management Port (2222)**: Dedicated to administrative maintenance.
    *   **Auth**: Public Key only (using `user_identity`).
    *   **Access**: Full shell access to the container.

### 2. Target Server (`target-server`)
The managed compute node.
*   **Native Trust**: Trust for the `user_ca.pub` is pre-baked.
*   **Host Identity**: Automatically generates a host key and requests a Host Certificate from the CA during boot.
*   **Role Mapping**: Maps certificate principals to local accounts (`npc` -> standard, `mc` -> sudo, `god` -> root).

### 3. Client (`client`)
The user workstation.
*   **Global Trust**: Pre-configured to trust the `host_ca.pub` for all domains, ensuring no "Unknown Host" prompts.

---

## Security Model

*   **Dual-Root CA**: Separate Root CAs are used for `Host` verification (so clients trust servers) and `User` verification (so servers trust users).
*   **Privileged Port Assertion**: Host certificates are only signed if the request originates from a privileged port (< 1024), preventing unprivileged users from impersonating servers.
*   **Short-Lived Identities**: User certificates are typically issued with a 1-hour TTL, enforcing frequent re-authentication.
*   **Zero-Interaction Trust**: By using `@cert-authority` in `known_hosts`, the entire fleet is trusted natively without manual fingerprint confirmation.

---

## Getting Started

### 1. Initialize Infrastructure Keys
Run the setup script to generate your Root CAs and administrative identities. These keys are ignored by Git for security.
```bash
./setup-keys.sh
```

### 2. Launch the Infrastructure
```bash
docker compose up -d --build
```

---

## Manual Verification Guide (Human-Friendly)

Follow these steps to experience the certificate-based workflow manually.

### 1. Enter the Client Workstation
Open a shell inside the client container:
```bash
docker exec -it client bash
```

### 2. Initialize your Authentication Agent
Inside the client container, start the SSH agent. This agent will store the short-lived certificates issued by the CA.
```bash
eval $(ssh-agent)
```

### 3. Request your Identity Certificate
Connect to the CA's issuance port (Port 22) using your **password** (which is the same as your username). You MUST use the `-A` flag to forward your agent so the CA can inject the certificate back into it.

**For a standard user (`npc`):**
```bash
# Password: npc
ssh -A npc@ca-server
```

**For a sudo-enabled user (`mc`):**
```bash
# Password: mc
ssh -A mc@ca-server
```

### 4. Access the Target Infrastructure
Now that your agent has a valid certificate (verify with `ssh-add -L`), you can log into any target server seamlessly without a password or host warnings.

```bash
# Connect as npc
ssh npc@target-server

# Connect as mc and verify sudo escalation
ssh mc@target-server "sudo whoami"
```

---

## Automated Host Certificate Rotation

The infrastructure includes a self-healing identity mechanism on the `target-server`:
*   **Rotation Monitor**: A background script (`rotate-host-cert.sh`) analyzes the current host certificate's validity range.
*   **80% Threshold**: When 80% of the certificate's lifetime has passed, the server automatically generates a new key and requests a fresh signature from the CA.
*   **Zero-Downtime Reload**: The script signals `sshd` via `SIGHUP` to pick up the new identity without dropping active connections.

You can monitor rotation events in the container logs:
```bash
docker compose logs -f target-server
```

---

## Administrative Access (Advanced)

To manage the CA server itself, use the pre-baked management key on the administrative port (**2222**). This port strictly forbids passwords and requires the `user_identity` key.

```bash
# From within the client container:
ssh -i /home/user/.ssh/id_ed25519 -p 2222 npc@ca-server
```

---

## Cleanup
```bash
docker compose down --volumes
```
