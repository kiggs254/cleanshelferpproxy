#!/bin/sh
# Drop-in script executed by nginx:alpine's entrypoint before nginx starts
# (files in /docker-entrypoint.d/*.sh are run in lexical order, and must be
# executable).
#
# Translates the ALLOW_CIDRS env var — comma-separated CIDRs — into an
# `allow ...; deny all;` include file. When ALLOW_CIDRS is empty or unset,
# writes a deny-all rule so nginx rejects every source IP (fail closed) — this
# proxy republishes a possibly-unauthenticated ERP, so "no allow-list" must
# never mean "allow the whole internet".
set -eu

OUT=/etc/nginx/conf.d/allow-list.conf
: > "$OUT"

CIDRS="${ALLOW_CIDRS:-}"
if [ -z "$CIDRS" ]; then
    # No allow-list configured — fail CLOSED. Deny every source IP and warn
    # loudly so the misconfiguration is obvious in the container logs.
    echo "WARNING: ALLOW_CIDRS is empty/unset — failing closed, denying ALL source IPs." >&2
    echo "         Set ALLOW_CIDRS to the egress CIDR(s) allowed to reach this proxy." >&2
    echo "# ALLOW_CIDRS was empty/unset — failing closed (deny all)." >> "$OUT"
    echo "deny all;" >> "$OUT"
    exit 0
fi

echo "# Generated from ALLOW_CIDRS — do not edit by hand." >> "$OUT"
# POSIX-portable comma split
OLD_IFS="$IFS"
IFS=','
for cidr in $CIDRS; do
    # Trim surrounding whitespace without bash-isms.
    cidr_trimmed=$(echo "$cidr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$cidr_trimmed" ]; then
        echo "allow $cidr_trimmed;" >> "$OUT"
    fi
done
IFS="$OLD_IFS"
echo "deny all;" >> "$OUT"
