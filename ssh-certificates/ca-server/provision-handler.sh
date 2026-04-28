#!/bin/bash
CMD="$SSH_ORIGINAL_COMMAND"
CLIENT_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
CLIENT_PORT=$(echo $SSH_CONNECTION | awk '{print $2}')

case "$CMD" in
    get_user_ca)
        sudo cat /etc/ssh/ca/user_ca.pub
        ;;
    get_host_ca)
        sudo cat /etc/ssh/ca/host_ca.pub
        ;;
    sign_host_key\ *)
        echo "CA: Received signature request from $CLIENT_IP:$CLIENT_PORT" >&2
        if [ "$CLIENT_PORT" -ge 1024 ]; then
            echo "CA: REJECTED - Request did not originate from a privileged port ($CLIENT_PORT)." >&2
            exit 1
        fi
        HOSTNAME=$(echo "$CMD" | awk '{print $2}')
        PUBKEY=$(echo "$CMD" | cut -d' ' -f3-)
        TEMP_DIR=$(mktemp -d)
        echo "$PUBKEY" > "$TEMP_DIR/key.pub"
        sudo ssh-keygen -q -s /etc/ssh/ca/host_ca -I "host-cert-${HOSTNAME}" -h -n "${HOSTNAME},${CLIENT_IP}" -V +90s "$TEMP_DIR/key.pub" 2>/dev/null
        echo "CA: Issued host certificate for $HOSTNAME ($CLIENT_IP) [SIMULATION MODE: 90s]" >&2
        ssh-keygen -L -f "$TEMP_DIR/key-cert.pub" >&2
        cat "$TEMP_DIR/key-cert.pub"
        rm -rf "$TEMP_DIR"
        ;;
    *)
        echo "Unknown command"
        exit 1
        ;;
esac
