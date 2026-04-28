#!/bin/bash

# Setup /etc/ssh/ca directory
mkdir -p /etc/ssh/ca

# Set permissions for CA keys (mounted via docker-compose)
chmod 600 /etc/ssh/ca/* /etc/ssh/ca_host_key
chown root:root /etc/ssh/ca/* /etc/ssh/ca_host_key

# Setup provision user's authorized_keys
mkdir -p /home/provision/.ssh
cat /etc/ssh/ca/provision_key.pub > /home/provision/.ssh/authorized_keys
chown -R provision:provision /home/provision/.ssh
chmod 700 /home/provision/.ssh
chmod 600 /home/provision/.ssh/authorized_keys

# Setup npc, mc, god authorized_keys
for u in npc mc god; do
    mkdir -p /home/$u/.ssh
    cat /etc/ssh/ca/user_identity.pub > /home/$u/.ssh/authorized_keys
    chown -R $u:$u /home/$u/.ssh
    chmod 700 /home/$u/.ssh
    chmod 600 /home/$u/.ssh/authorized_keys
done

# Start SSH daemon for admin/management on Port 2222 (background)
/usr/sbin/sshd -e -f /etc/ssh/ca/sshd_config_admin

# Start SSH daemon for certificate issuance on Port 22 (foreground)
/usr/sbin/sshd -D -e -f /etc/ssh/ca/sshd_config_issue
