#!/bin/bash

# Wait for CA server to be up
sleep 2

# Check if host key exists, generate if not
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    echo "BOOTSTRAP: Generating new host key..."
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" -q
fi
echo "BOOTSTRAP: Local Host Key Fingerprint: $(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)"

# Configure global host trust (affects all users including root)
echo "BOOTSTRAP: Configuring global trust for Host CA..."
echo "@cert-authority * $(cat /etc/ssh/host_ca.pub)" > /etc/ssh/ssh_known_hosts

# Ensure proper permissions on the provision key (mounted via docker-compose)
mkdir -p /root/.ssh
cp /etc/ssh/provision_key /root/.ssh/id_ed25519
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_ed25519

# Request certificate from CA
echo "BOOTSTRAP: Requesting host certificate from CA..."
echo "BOOTSTRAP: Hostname: $(hostname), Requested Principals: $(hostname), IP Verification Required."
PUB_KEY=$(cat /etc/ssh/ssh_host_ed25519_key.pub)
RANDOM_PORT=$((500 + RANDOM % 500))
SSHPASS=provision sshpass -e ssh -o ProxyCommand="socat TCP4:ca-server:22,bind=:${RANDOM_PORT} -" provision@ca-server "sign_host_key $(hostname) $PUB_KEY" > /etc/ssh/ssh_host_ed25519_key-cert.pub

echo "Host certificate received. Details:"
ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub

# Ensure proper permissions on the mounted User CA public key
chmod 644 /etc/ssh/user_ca.pub

# Configure authorized principals
mkdir -p /etc/ssh/auth_principals
echo "npc" > /etc/ssh/auth_principals/npc
echo "mc" > /etc/ssh/auth_principals/mc
echo "god" > /etc/ssh/auth_principals/root

# Setup and start background rotation monitor
chmod +x /usr/local/bin/rotate-host-cert.sh
/usr/local/bin/rotate-host-cert.sh &

# Start sshd with PID tracking
/usr/sbin/sshd -D -e -p 22 -o "PidFile=/var/run/sshd.pid"
