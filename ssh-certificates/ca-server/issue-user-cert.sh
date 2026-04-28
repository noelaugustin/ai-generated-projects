#!/bin/bash
# CA ForceCommand script

if [ -z "$SSH_AUTH_SOCK" ]; then
    echo "Error: SSH Agent Forwarding is required. Please use 'ssh -A'."
    exit 1
fi

USER_NAME=$(whoami)
case "$USER_NAME" in
    npc)
        PRINCIPALS="npc"
        ;;
    mc)
        PRINCIPALS="mc"
        ;;
    god)
        PRINCIPALS="god"
        ;;
    *)
        echo "Error: Unknown identity mapping for $USER_NAME"
        exit 1
        ;;
esac

TEMP_DIR=$(mktemp -d)
KEY_FILE="$TEMP_DIR/id_ed25519"

# Generate new key
ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q

# Sign key
sudo ssh-keygen -q -s /etc/ssh/ca/user_ca -I "${USER_NAME}@ca" -n "$PRINCIPALS" -V +1h "$KEY_FILE.pub"
echo "CA: Issued user certificate for $USER_NAME (principals: $PRINCIPALS)" >&2
ssh-keygen -L -f "$KEY_FILE-cert.pub" >&2

# Add to agent
ssh-add "$KEY_FILE" >/dev/null 2>&1

# Clean up
rm -rf "$TEMP_DIR"

echo "Successfully issued SSH certificate for user '$USER_NAME' with principals '$PRINCIPALS'."
echo "The key and certificate have been automatically added to your SSH agent."
