#!/bin/bash
# Host Certificate Rotation Monitor

CERT_FILE="/etc/ssh/ssh_host_ed25519_key-cert.pub"
KEY_FILE="/etc/ssh/ssh_host_ed25519_key"
CHECK_INTERVAL=10 # 10 seconds (Simulation Mode)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ROTATION] $1"
}

get_timestamp() {
    # Extract date from ssh-keygen -L output
    # Format: 2026-04-19T02:18:00
    ssh-keygen -L -f "$CERT_FILE" | grep "Valid:" | awk -v type="$1" '{
        if (type == "from") print $3;
        else if (type == "to") print $5;
    }' | sed 's/T/ /'
}

while true; do
    if [ ! -f "$CERT_FILE" ]; then
        log "Certificate file not found. Waiting..."
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Get validity range
    FROM_STR=$(get_timestamp "from")
    TO_STR=$(get_timestamp "to")

    if [ -z "$FROM_STR" ] || [ -z "$TO_STR" ]; then
        log "Could not parse certificate validity. Retrying in $CHECK_INTERVAL..."
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # Convert to unix timestamps
    FROM_TS=$(date -d "$FROM_STR" +%s)
    TO_TS=$(date -d "$TO_STR" +%s)
    NOW_TS=$(date +%s)

    TOTAL_LIFETIME=$((TO_TS - FROM_TS))
    ELAPSED=$((NOW_TS - FROM_TS))
    
    # Calculate percentage (using scale for precision)
    if [ "$TOTAL_LIFETIME" -gt 0 ]; then
        PERCENT=$(awk "BEGIN {print ($ELAPSED / $TOTAL_LIFETIME) * 100}")
        log "Current cert validity: ${PERCENT%.*}% elapsed. (Limit: 80%)"

        # Check if 80% threshold is reached
        if (( $(echo "$PERCENT > 80" | bc -l) )); then
            log "THRESHOLD REACHED (80%). Initializing rotation..."

            TEMP_DIR=$(mktemp -d)
            NEW_KEY="$TEMP_DIR/ssh_host_ed25519_key"
            
            # 1. Generate new key
            ssh-keygen -t ed25519 -f "$NEW_KEY" -N "" -q
            
            # 2. Request new certificate
            PUB_KEY_CONTENT=$(cat "$NEW_KEY.pub")
            log "Requesting new signature from CA..."
            RANDOM_PORT=$((500 + RANDOM % 500))
            if SSHPASS=provision sshpass -e ssh -o ProxyCommand="socat TCP4:ca-server:22,bind=:${RANDOM_PORT} -" provision@ca-server "sign_host_key $(hostname) $PUB_KEY_CONTENT" > "$NEW_KEY-cert.pub"; then
                
                # 3. Swap keys atomically
                log "Rotation successful. Updating SSH server..."
                mv "$NEW_KEY" "$KEY_FILE"
                mv "$NEW_KEY.pub" "$KEY_FILE.pub"
                mv "$NEW_KEY-cert.pub" "$CERT_FILE"
                
                chmod 600 "$KEY_FILE"
                chmod 644 "$KEY_FILE.pub" "$CERT_FILE"

                # 4. Signal SSHD to reload
                if [ -f /var/run/sshd.pid ]; then
                    kill -HUP $(cat /var/run/sshd.pid)
                    log "SSHD reloaded with new identity."
                fi
            else
                log "ERROR: Failed to sign new key. Will retry next interval."
            fi
            rm -rf "$TEMP_DIR"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
