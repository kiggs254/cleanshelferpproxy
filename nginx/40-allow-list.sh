#!/bin/sh
# Drop-in script executed by nginx:alpine's entrypoint before nginx starts
# (files in /docker-entrypoint.d/*.sh are run in lexical order, and must be
# executable).
#
# Translates the ALLOW_CIDRS env var — comma-separated CIDRs — into an
# `allow ...; deny all;` include file. When ALLOW_CIDRS is empty or unset,
# writes an empty file so the `include` in default.conf is a no-op.
set -eu

OUT=/etc/nginx/conf.d/allow-list.conf
: > "$OUT"

CIDRS="${ALLOW_CIDRS:-}"
if [ -z "$CIDRS" ]; then
    # No allow-list configured — fall through to nginx default (allow all).
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
