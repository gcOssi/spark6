#!/usr/bin/env sh
set -e
: "${BASIC_AUTH_USER:?BASIC_AUTH_USER is required}"
: "${BASIC_AUTH_PASSWORD:?BASIC_AUTH_PASSWORD is required}"

# Create htpasswd file
if ! command -v htpasswd >/dev/null 2>&1; then
  apk add --no-cache apache2-utils >/dev/null
fi
htpasswd -bc /etc/nginx/.htpasswd "$BASIC_AUTH_USER" "$BASIC_AUTH_PASSWORD"

# Move our templated config
mv /tmp/default.conf /etc/nginx/conf.d/default.conf

# Start nginx
nginx -g 'daemon off;'
