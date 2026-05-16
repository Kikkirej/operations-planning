#!/bin/sh
# setup-hosts.sh — Add ops.local hostnames to /etc/hosts (idempotent).
# Requires sudo/root to modify /etc/hosts.
# Usage: sudo ./setup-hosts.sh

HOSTS_FILE="/etc/hosts"
TARGET_IP="127.0.0.1"

ENTRIES="
auth.ops.local
admin.ops.local
config.ops.local
"

added=0
for host in $ENTRIES; do
    if grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+.*\b${host}\b" "$HOSTS_FILE"; then
        echo "  already present: $host"
    else
        printf '%s\t%s\n' "$TARGET_IP" "$host" >> "$HOSTS_FILE"
        echo "  added:           $host"
        added=$((added + 1))
    fi
done

if [ "$added" -gt 0 ]; then
    echo "Done. $added entry/entries added to $HOSTS_FILE."
else
    echo "Done. Nothing to add — all hosts already present."
fi
