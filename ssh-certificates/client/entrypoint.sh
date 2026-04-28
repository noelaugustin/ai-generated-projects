#!/bin/bash
# Wait for CA server to be up
sleep 3

# Configure global host trust (affects all users including root)
echo "@cert-authority * $(cat /etc/ssh/host_ca.pub)" > /etc/ssh/ssh_known_hosts

# Execute as 'user'
su - user -c "
# Configure user 'user' environment
mkdir -p /home/user/.ssh
cp /etc/ssh/user_identity /home/user/.ssh/id_ed25519
chown -R user:user /home/user/.ssh
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/id_ed25519

# Provide the demo instruction
cat << 'EOF' > /home/user/demo.sh
#!/bin/bash
set -e
echo \"=== SSH Certificates Demo (Dual CA & Principal Refactor) ===\"
echo \"Starting ssh-agent...\"
eval \$(ssh-agent)

echo \"\"
echo \"Identity: NPC (Normal User)\"
echo \"Requesting a certificate from the CA as user 'npc' (password: npc):\"
SSHPASS=npc sshpass -e ssh -p 22 -A npc@ca-server

echo \"\"
echo \"Attempting to SSH into target-server as npc:\"
ssh npc@target-server \"echo 'SUCCESS: I am npc! Whoami: \$(whoami)'\"

echo \"\"
echo \"Identity: MC (Main Character / Sudo User)\"
echo \"Requesting a certificate from the CA as user 'mc' (password: mc):\"
SSHPASS=mc sshpass -e ssh -p 22 -A mc@ca-server

echo \"\"
echo \"Attempting to SSH into target-server as mc and running sudo:\"
ssh mc@target-server \"sudo whoami\" | grep root && echo 'SUCCESS: mc has sudo access!'

echo \"\"
echo \"Identity: GOD (Root User)\"
echo \"Requesting a certificate from the CA as user 'god' (password: god):\"
SSHPASS=god sshpass -e ssh -p 22 -A god@ca-server

echo \"\"
echo \"Attempting to SSH into target-server as root (god principal):\"
ssh root@target-server \"echo 'SUCCESS: I am GOD! Whoami: \$(whoami)'\"

echo \"\"
echo \"Demo complete.\"
EOF
chmod +x /home/user/demo.sh
"

# Keep the container alive
tail -f /dev/null
