# Proposal: Integrating SPIFFE/SPIRE into the SSH CA Infrastructure

## Executive Summary

This document evaluates the viability of replacing or augmenting the current hand-rolled SSH Certificate Authority (CA) infrastructure with **SPIFFE (Secure Production Identity Framework For Everyone)** and its reference implementation **SPIRE (SPIFFE Runtime Environment)**. SPIFFE is a CNCF-graduated standard specifically designed to solve the workload identity problem that this infrastructure currently addresses — without reinventing the wheel.

---

## Current Architecture: What We've Built

Our current system establishes:

| Component | Implementation |
| :--- | :--- |
| Root of Trust | Two self-managed CAs (`host_ca`, `user_ca`) as Ed25519 keypairs on disk |
| Host Identity | SSH host certificates signed on boot, auto-rotated at 80% TTL |
| User Identity | Short-lived (1hr) SSH user certificates issued via password-authed CA connection |
| Trust Distribution | Volume-mounted CA public keys; `/etc/ssh/ssh_known_hosts` for global trust |
| Rotation | Custom `rotate-host-cert.sh` using `SIGHUP` to reload `sshd` |
| Privileged Port Assertion | Enforced via `socat`; proves requests originate from root-level processes |

This works well for a closed Docker Compose environment. However, many of the above components are **re-implementations of hard solved problems in identity and secrets management**.

---

## What is SPIFFE/SPIRE?

SPIFFE is a **framework specification** for cryptographic workload identity. SPIRE is the server + agent daemon that implements it.

Key concepts:

- **SVID (SPIFFE Verifiable Identity Document)**: An X.509 certificate or JWT encoding a `spiffe://` URI (e.g., `spiffe://example.org/target-server`).
- **SPIRE Server**: The trust root. Issues SVIDs to registered workloads.
- **SPIRE Agent**: Runs on each node (host or container). Attests the workload and delivers its SVID via a Unix domain socket (`/run/spire/sockets/agent.sock`).
- **Workload API**: A gRPC API accessed by workloads to receive and watch their SVIDs in real-time.

---

## Opportunities

### 1. Eliminate Custom CA Management
SPIRE is a production-grade X.509 CA. It manages root bundle distribution, rotation, and trust federation natively. Our `host_ca`, `user_ca`, and `provision_key` concepts map directly to SPIRE's `trust-bundle` and `registration entries`.

### 2. Automated, Cryptographic Workload Attestation
Currently, the `target-server` uses a `provision_key` (pre-shared secret) to prove its identity to the CA. SPIRE replaces this with **cryptographic node attestation** using platform-native mechanisms:
- **Docker Workload Attestor**: Attests containers by inspecting Docker socket labels/env vars.
- **Kubernetes PSAT Attestor**: Uses Kubernetes service account tokens.
- **AWS/GCP/Azure Attestors**: Uses cloud platform APIs for hardware-rooted identity.

This eliminates the need for the `provision_key` entirely.

### 3. Short-TTL SVIDs with Automatic Rotation (via Workload API)
SPIRE delivers SVIDs with short TTLs (configurable, e.g., 1 hour) and **pushes renewals automatically** to any listening workload via the Workload API. Our `rotate-host-cert.sh` is a partial reimplementation of this capability. With SPIRE, rotation becomes a subscription rather than a polling loop.

### 4. SSH Certificates as a First-Class SPIRE Use Case
The **SPIFFE SSH helper** project and HashiCorp Vault's SSH Secrets Engine (backed by SPIRE) can issue SSH certificates directly from SVIDs. The flow becomes:
```
Workload obtains SVID from SPIRE → Presents SVID to SSH CA intermediary → Receives SSH cert
```
This is architecturally identical to our current design, but with SPIRE as the trust anchor instead of our custom CA.

### 5. Federation Across Environments
SPIRE supports **trust bundle federation** across multiple trust domains (e.g., different clusters, clouds, or environments). Our current infrastructure is scoped to a single Docker network.

---

## Improvement Areas

### 1. Replace `provision_key` with Node Attestation
The `provision_key` is a static, pre-shared secret that must be rotated manually (currently never). SPIRE's node attestation would replace this with ephemeral, verifiable proofs of identity.

### 2. Replace `/etc/ssh/ssh_known_hosts` Distribution
Currently, the Host CA public key is volume-mounted. SPIRE's trust bundle distribution API handles this automatically and for multiple trust domains.

### 3. Replace `socat` Privileged Port Trick
We use `socat` + port < 1024 to cryptographically assert that the requester is root. With SPIRE's workload attestor, workload identity is proven through the OS (pid/uid/label inspection), making port-number tricks unnecessary.

### 4. Certificate Transparency & Auditability
SPIRE integrates with upstream certificate transparency and audit logs. Our current issuance has no audit trail beyond container logs.

### 5. Replace Username/Password CA Issuance
Our issuance channel (Port 22, password=username) is operationally convenient but architecturally weak. Replacing it with SPIRE-issued SVIDs presented to the SSH issuance channel would make the "who is this user" question cryptographically answerable rather than password-based.

---

## Risks & Challenges

### 1. Architectural Complexity
SPIRE requires a server + agent deployed on every node. For our current Docker Compose setup, this adds substantial operational overhead and would require a proper orchestration platform (Kubernetes, Nomad) to be practical.

### 2. SSH Native Certificate Format vs. X.509
SPIRE issues **X.509 SVIDs**, not SSH certificates. SSH still needs its own CA to issue SSH-format certificates. The integration point (an intermediary that accepts SPIRE SVIDs and issues SSH certs) must be built or sourced separately (e.g., using Vault's SSH Secrets Engine as that intermediary).

### 3. SPIRE Has No Native SSH Principal Mapping
The `npc → user`, `mc → sudo`, `god → root` principal mapping we built is SSH-specific. SPIRE would manage the SVID, but SSH principal mapping would still need to be customized as an application-level concern.

### 4. Bootstrap Problem Still Exists
SPIRE solves workload attestation but still requires the SPIRE Agent itself to be bootstrapped securely (join tokens, etc.). This shifts rather than eliminates the bootstrap trust problem.

### 5. Operational Dependency
Our current infrastructure is self-contained and has no external dependencies. SPIRE introduces a new critical-path component: if the SPIRE server is unavailable, no new SVIDs can be issued and all workloads will eventually lose their identity as their TTLs expire.

---

## Recommended Integration Path

| Phase | Action | Benefit |
| :--- | :--- | :--- |
| **Phase 1** | Deploy SPIRE Server + Agent in Docker Compose | Establishes root of trust |
| **Phase 2** | Use SPIRE to attest `target-server` via Docker attestor | Eliminates `provision_key` |
| **Phase 3** | Bridge SPIRE SVID → SSH Certificate via Vault SSH Secrets Engine | Replaces custom CA issuance |
| **Phase 4** | Use SPIRE's bundle distribution API to replace volume-mounted CA keys | Eliminates manual trust distribution |
| **Phase 5** | Deprecate custom `rotate-host-cert.sh` | Workload API handles rotation natively |

---

## Conclusion

Our current implementation is an excellent learning vehicle and a clear, self-contained prototype. However, for any production or multi-node deployment, SPIFFE/SPIRE addresses nearly every component of this system in a more robust, auditable, and scalable way. The most pragmatic approach is a **staged migration**, using SPIRE as the identity substrate while retaining the SSH-specific layer (issuance policy, principal mapping) on top of it.
