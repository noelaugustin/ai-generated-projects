#!/bin/bash
set -e

# Create keys directory
rm -rf keys
mkdir -p keys
echo "Initializing fresh keys directory..."

# 1. Generate Root CAs
echo "Generating Root CAs..."
ssh-keygen -t ed25519 -f keys/host_ca -N "" -q -C "Host Root CA"
ssh-keygen -t ed25519 -f keys/user_ca -N "" -q -C "User Root CA"

# 2. Generate management and identity keys
echo "Generating provision and user identity keys..."
ssh-keygen -t ed25519 -f keys/provision_key -N "" -q -C "Provision Key"
ssh-keygen -t ed25519 -f keys/user_identity -N "" -q -C "User Identity Key"

# 3. Generate and Sign CA Server Host Key
echo "Generating and signing CA host key..."
ssh-keygen -t ed25519 -f keys/ca_host_key -N "" -q -C "CA Host Identity"
ssh-keygen -s keys/host_ca -I "ca-server-host" -h -n "ca-server" keys/ca_host_key.pub

echo "Key generation complete. All keys are stored in the 'keys/' directory."
