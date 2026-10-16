#!/bin/bash
set -e

NGINX_CONFIG=/etc/nginx/sites-available/default

# User detection: scripts run under sudo, so SUDO_USER points to real user
CUSER="${SUDO_USER:-$(id -un)}"
CHOME="$(getent passwd "$CUSER" | cut -d: -f6)"
if [ -z "$CHOME" ]; then
  CHOME="/home/$CUSER"
fi
echo "Configuring Nginx for user: $CUSER ($CHOME)"

# User passed environment variables
if [ -z "$CUSTOM_WS_PORT" ] && [ -f "$CHOME/.config/selkies/selkies.env" ]; then
  cws_from_file=$(grep "^CUSTOM_WS_PORT=" "$CHOME/.config/selkies/selkies.env" | cut -d= -f2- | tr -d ' "\r')
  [ -n "$cws_from_file" ] && CUSTOM_WS_PORT="$cws_from_file"
fi
CPORT="${CUSTOM_PORT:-3000}"
CHPORT="${CUSTOM_HTTPS_PORT:-3001}"
CWS="${CUSTOM_WS_PORT:-8082}"
SFOLDER="${SUBFOLDER:-/}"
DISABLE_IPV6="${DISABLE_IPV6:-true}"
DASHBOARD="${DASHBOARD:-selkies-dashboard}"
SELKIES_FILE_TRANSFERS="${SELKIES_FILE_TRANSFERS:-upload,download}"
HARDEN_DESKTOP="${HARDEN_DESKTOP:-false}"
PELORUS="${PELORUS:-true}"
SELKIES_TAG="${SELKIES_TAG:-debiantrixie-c5555162-ls138}"

# 1. Obtain default.conf template from rootfs, local cache, or fallback git clone
if [ -n "$SELKIES_ROOTFS" ] && [ -f "$SELKIES_ROOTFS/defaults/default.conf" ]; then
  echo "Using default.conf template from rootfs image: $SELKIES_ROOTFS/defaults/default.conf"
  cp "$SELKIES_ROOTFS/defaults/default.conf" "${NGINX_CONFIG}"
elif [ -f "./docker-baseimage-selkies/root/defaults/default.conf" ]; then
  echo "Using default.conf template from local repository cache"
  cp "./docker-baseimage-selkies/root/defaults/default.conf" "${NGINX_CONFIG}"
else
  echo "Cloning default.conf template from upstream linuxserver tag ${SELKIES_TAG}..."
  git clone --depth 1 --branch "${SELKIES_TAG}" https://github.com/linuxserver/docker-baseimage-selkies.git /tmp/selkies-nginx-template
  cp /tmp/selkies-nginx-template/root/defaults/default.conf "${NGINX_CONFIG}"
  rm -rf /tmp/selkies-nginx-template
fi

# 2. Self-signed certificate - use snakeoil certificates
sed -i "s|/config/ssl/cert.pem|/etc/ssl/certs/ssl-cert-snakeoil.pem|g" "${NGINX_CONFIG}"
sed -i "s|/config/ssl/cert.key|/etc/ssl/private/ssl-cert-snakeoil.key|g" "${NGINX_CONFIG}"

# 3. Ports, subfolder, and paths substitution
sed -i "s/3000/$CPORT/g" "${NGINX_CONFIG}"
sed -i "s/3001/$CHPORT/g" "${NGINX_CONFIG}"
sed -i "s/CWS/$CWS/g" "${NGINX_CONFIG}"
sed -i "s|SUBFOLDER|$SFOLDER|g" "${NGINX_CONFIG}"
sed -i "s|REPLACE_DOWNLOADS_PATH|$CHOME/Desktop|g" "${NGINX_CONFIG}"
sed -i "s|REPLACE_HOME|$CHOME|g" "${NGINX_CONFIG}"

# 4. Disable IPv6 if configured
if [ "$DISABLE_IPV6" = "true" ]; then
  sed -i '/listen \[::\]/d' "${NGINX_CONFIG}"
fi

# 5. Basic Authentication
if [ -n "$PASSWORD" ]; then
  printf '%s:%s\n' "$CUSER" "$(openssl passwd -apr1 "$PASSWORD")" > /etc/nginx/.htpasswd
  sed -i 's/#auth_basic/auth_basic/g' "${NGINX_CONFIG}"
fi

# 6. Dev mode handling
if [ -n "$DEV_MODE" ]; then
  sed -i \
    -e 's:location / {:location /null {:g' \
    -e 's:location /devmode:location /:g' \
    "${NGINX_CONFIG}"
fi

# 7. Remove 'files' location if downloads are disabled or desktop is hardened
if [[ "$SELKIES_FILE_TRANSFERS" != *"download"* ]] || [ "$HARDEN_DESKTOP" = "true" ]; then
  sed -i '/files {/,/^[[:space:]]*}/d' "${NGINX_CONFIG}" 2>/dev/null || true
fi

# 8. Pelorus location handling: remove pelorus block ONLY if PELORUS is not true
if [ "${PELORUS,,}" != "true" ]; then
  echo "Pelorus disabled - removing pelorus block from Nginx configuration..."
  awk '
  /location [^ ]*pelorus\// {
    in_block = 1
    depth = 0
  }
  in_block {
    depth += gsub(/\{/, "{") - gsub(/\}/, "}")
    if (depth <= 0) {
      in_block = 0
    }
    next
  }
  { print }
  ' "${NGINX_CONFIG}" > "${NGINX_CONFIG}.tmp" && mv "${NGINX_CONFIG}.tmp" "${NGINX_CONFIG}"
fi

# 9. Dashboard and web assets
if [ -d "/usr/share/selkies/$DASHBOARD" ]; then
  rm -rf /usr/share/selkies/web
  cp -a "/usr/share/selkies/$DASHBOARD" /usr/share/selkies/web
fi

# Favicon / icon setup
if [ -f /usr/share/selkies/www/icon.png ]; then
  mkdir -p /usr/share/selkies/web
  cp /usr/share/selkies/www/icon.png /usr/share/selkies/web/favicon.ico 2>/dev/null || true
  cp /usr/share/selkies/www/icon.png /usr/share/selkies/web/icon.png 2>/dev/null || true
fi

# Fix for Download Files button (if location files exists and footer.html exists)
FOOTER=/usr/share/selkies/web/nginx/footer.html
if grep -q 'location .*files' "${NGINX_CONFIG}" 2>/dev/null && [ -f "$FOOTER" ]; then
  setfacl -m u:www-data:--x "$CHOME" 2>/dev/null || true
  setfacl -m u:www-data:--x "$CHOME/Desktop" 2>/dev/null || true
  sed -i "s|const diskPathPrefix = '/config/Desktop/';|const diskPathPrefix = '$CHOME/Desktop/';|" "$FOOTER"
fi

# Fix permissions so www-data can read static assets
chmod -R a+rX /usr/share/selkies 2>/dev/null || true

# 10. Verify nginx syntax and reload
echo "Testing Nginx configuration syntax..."
if nginx -t; then
  systemctl reload nginx 2>/dev/null || true
  echo "Nginx configuration updated and reloaded successfully."
else
  echo "ERROR: Nginx configuration syntax test failed!" >&2
  exit 1
fi
