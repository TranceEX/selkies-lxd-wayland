#!/bin/bash
set -eo pipefail

echo "=== Starting Selkies (Wayland) + Pelorus installation on LXC ==="

# 1. Set variables
export PATH="$HOME/.local/bin:$PATH"
echo "[OK] Variables Set"

# 2. Create required directories
mkdir -p ~/.config/rclone ~/.config/selkies ~/.config/systemd/user "$HOME/Desktop"
sudo mkdir -p /root/.config/rclone
touch ~/.config/rclone/rclone.conf
sudo touch /root/.config/rclone/rclone.conf

# 3. Install system packages
echo "--- Updating repositories and installing system packages ---"
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -yq \
  acl curl git libepoxy0 libnginx-mod-http-fancyindex locales-all nginx pipx pulseaudio ssl-cert unzip \
  x11-xkb-utils xcvt xdotool xclip xsel \
  kde-plasma-desktop kwin-wayland xwayland qt6-wayland polkit-kde-agent-1 at-spi2-core dbus-user-session \
  wl-clipboard libkf6config-bin libkf6service-bin python3 python3-pip \
  python3-gi python3-gi-cairo gir1.2-atspi-2.0 gir1.2-gtk-3.0
sudo apt clean

# 4. Install rclone (if not present)
if ! command -v rclone >/dev/null 2>&1; then
  echo "--- Installing rclone ---"
  curl -fsSL https://rclone.org/install.sh | sudo bash
fi

# 5. Add user to audio and video groups
sudo usermod -aG audio,video "$USER"

# 6. Pull and extract Selkies components via udocker
echo "--- Pulling Selkies image via udocker ---"
pipx install udocker 2>/dev/null || pipx upgrade udocker 2>/dev/null || true
SELKIES_IMAGE="${SELKIES_IMAGE:-lsiobase/selkies:debiantrixie-c5555162-ls138}"
export SELKIES_TAG="${SELKIES_IMAGE#*:}"
udocker pull "$SELKIES_IMAGE"
udocker create --name=selkies_tmp "$SELKIES_IMAGE"

export SELKIES_ROOTFS="$(find ~/.udocker -name selkies_input_interposer.so | sed 's|/usr/lib/selkies_input_interposer.so||' | head -n 1)"
if [ -z "$SELKIES_ROOTFS" ] || [ ! -d "$SELKIES_ROOTFS" ]; then
  echo "ERROR: Could not find SELKIES_ROOTFS in ~/.udocker!" >&2
  exit 1
fi
echo "Located image rootfs: $SELKIES_ROOTFS"

echo "--- Copying Selkies binaries and libraries ---"
sudo rclone copy -L "$SELKIES_ROOTFS/usr/lib/selkies_input_interposer.so" /usr/lib/
sudo ln -sf /usr/lib/selkies_input_interposer.so /usr/lib/selkies_joystick_interposer.so
sudo rclone copy -L "$SELKIES_ROOTFS/opt/lib/libudev.so.1.0.0-fake" /opt/lib/
sudo rclone copy -L "$SELKIES_ROOTFS/lsiopy" /lsiopy
sudo rclone copy -L "$SELKIES_ROOTFS/usr/share/selkies" /usr/share/selkies
sudo chmod -R a+rX /usr/share/selkies
sudo chmod -R a+rX /lsiopy
sudo chmod a+x /lsiopy/bin/*

# Check and install Pelorus if missing from extracted venv
echo "--- Verifying Selkies and Pelorus components ---"
if [ -f /lsiopy/bin/pelorus ]; then
  echo "[OK] Found /lsiopy/bin/pelorus in extracted image."
else
  echo "[WARNING] /lsiopy/bin/pelorus not found, installing Pelorus into /lsiopy venv..."
  sudo /lsiopy/bin/pip install git+https://github.com/linuxserver/pelorus.git || true
fi
sudo ln -sf /lsiopy/bin/selkies /usr/local/bin/selkies
sudo ln -sf /lsiopy/bin/pelorus /usr/local/bin/pelorus

# 7. Check for missing dynamic library dependencies in /lsiopy
echo "--- Checking dynamic library dependencies in /lsiopy ---"
MISSING_LIBS=$(find /lsiopy -name "*.so*" -exec ldd {} + 2>/dev/null | grep "not found" | sort -u || true)
if [ -n "$MISSING_LIBS" ]; then
  echo "WARNING: Found missing shared libraries for /lsiopy:"
  echo "$MISSING_LIBS"
else
  echo "[OK] All library dependencies in /lsiopy are satisfied."
fi

# 8. Reset capabilities on kwin_wayland (required for unprivileged LXC containers)
if command -v kwin_wayland >/dev/null 2>&1; then
  sudo setcap -r "$(command -v kwin_wayland)" 2>/dev/null || true
  echo "[OK] Removed capabilities from kwin_wayland for proper unprivileged LXC operation."
fi

# 9. Prepare configuration directory for Pelorus AI (/config/agent)
sudo install -d -m 0755 -o "$USER" -g "$(id -gn)" /config /config/agent
sudo chown -R "$USER:$(id -gn)" /config 2>/dev/null || true

# Prepare /tmp/.X11-unix directory for XWayland session
sudo mkdir -p /tmp/.X11-unix
sudo chmod 1777 /tmp/.X11-unix
sudo rm -f /tmp/.X11-unix/X*
sudo tee /etc/tmpfiles.d/x11-unix.conf > /dev/null <<EOF
d /tmp/.X11-unix 1777 root root -
EOF

# 10. Install session scripts to /usr/local/bin
echo "--- Installing Wayland session scripts ---"
sudo cp selkies-startwm-wayland.sh /usr/local/bin/selkies-startwm-wayland.sh
sudo chmod 755 /usr/local/bin/selkies-startwm-wayland.sh
sudo cp kwin-xwayland.py /usr/local/bin/kwin-xwayland.py
sudo chmod 755 /usr/local/bin/kwin-xwayland.py

# 11. Install or update environment file selkies.env
if [ ! -f ~/.config/selkies/selkies.env ]; then
  cp selkies.env ~/.config/selkies/selkies.env
  echo "[OK] Created ~/.config/selkies/selkies.env"
else
  # Ensure critical ports and settings are present in existing configuration
  for cfg_line in "CUSTOM_WS_PORT=8082" "SELKIES_PORT=8082" "SELKIES_COMPUTER_USE_BIND=5000" "SELKIES_APP_WAYLAND_DISPLAY=wayland-0"; do
    cfg_key="${cfg_line%%=*}"
    if ! grep -q "^${cfg_key}=" ~/.config/selkies/selkies.env; then
      echo "$cfg_line" >> ~/.config/selkies/selkies.env
    fi
  done
  echo "[INFO] Verified and synchronized ~/.config/selkies/selkies.env configuration."
fi

# 12. Configure PulseAudio services (null-sinks)
echo "--- Configuring PulseAudio ---"
sudo mkdir -p /etc/pulse/default.pa.d
sudo tee /etc/pulse/default.pa.d/selkies.pa > /dev/null <<EOF
load-module module-null-sink sink_name="output" sink_properties=device.description="output"
load-module module-null-sink sink_name="input" sink_properties=device.description="input"
EOF

# 13. Disable PipeWire in favor of PulseAudio
systemctl --user disable pipewire.service pipewire.socket wireplumber.service pipewire-pulse.service pipewire-pulse.socket 2>/dev/null || true
systemctl --user mask pipewire.service pipewire.socket wireplumber.service pipewire-pulse.service pipewire-pulse.socket 2>/dev/null || true

# 14. Run Nginx and Selkies initialization scripts
echo "--- Initializing Nginx and Selkies configuration ---"
export CUSTOM_WS_PORT="${CUSTOM_WS_PORT:-8082}"
sudo --preserve-env=PASSWORD,CUSTOM_PORT,CUSTOM_HTTPS_PORT,CUSTOM_WS_PORT,SUBFOLDER,DASHBOARD,DISABLE_IPV6,SELKIES_FILE_TRANSFERS,HARDEN_DESKTOP,PELORUS,SELKIES_ROOTFS,SELKIES_IMAGE,SELKIES_TAG bash 01-init-nginx.sh
sudo bash 02-init-selkies-config.sh

# 15. Remove temporary udocker container and image
udocker rm selkies_tmp 2>/dev/null || true
udocker rmi "$SELKIES_IMAGE" 2>/dev/null || true

# 16. Install systemd user units
echo "--- Installing systemd units for user session ---"
# Remove legacy xvfb service if previously active
if systemctl --user is-active --quiet xvfb 2>/dev/null || systemctl --user is-enabled --quiet xvfb 2>/dev/null; then
  systemctl --user disable --now xvfb 2>/dev/null || true
fi
rm -f ~/.config/systemd/user/xvfb.service

cp selkies.service desktop.service ~/.config/systemd/user/

# 17. Enable and start systemd user services
loginctl enable-linger "$USER"
systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable --now pulseaudio selkies desktop

echo "=== Installation completed successfully! ==="
echo "Access URLs:"
echo "  Desktop: https://<container_ip>:3001/ or http://<container_ip>:3000/"
echo "  Pelorus AI: https://<container_ip>:3001/pelorus/"
