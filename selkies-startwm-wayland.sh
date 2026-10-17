#!/usr/bin/env bash
# selkies-startwm-wayland.sh
# Startup script for KDE Plasma Wayland session with Selkies and Pelorus.

ulimit -c 0 2>/dev/null || true

# Load environment configuration if present
if [ -f "${HOME}/.config/selkies/selkies.env" ]; then
  set -a
  . "${HOME}/.config/selkies/selkies.env"
  set +a
fi

# 1. Re-exec within a private D-Bus session if not already in one
if [ -z "${SELKIES_DBUS_SESSION}" ]; then
  export SELKIES_DBUS_SESSION=1
  exec dbus-run-session bash "$0" "$@"
fi

# 2. Wait for Pixelflux Wayland socket (wayland-1)
SOCKET_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIXELFLUX_SOCKET="${SOCKET_DIR}/${WAYLAND_DISPLAY:-wayland-1}"

echo "[selkies-session] Waiting for Selkies Wayland socket at ${PIXELFLUX_SOCKET}..."
FOUND_SOCKET=false
for _ in $(seq 1 100); do
  if [ -S "${PIXELFLUX_SOCKET}" ]; then
    FOUND_SOCKET=true
    break
  fi
  sleep 0.2
done

if [ "$FOUND_SOCKET" != "true" ]; then
  echo "[selkies-session] Error: Selkies Wayland socket not found at ${PIXELFLUX_SOCKET}" >&2
  exit 1
fi
echo "[selkies-session] Connected to Selkies Wayland compositor on ${PIXELFLUX_SOCKET}"

# 3. Detect Desktop Environment
DESKTOP_ENVIRONMENT="${DESKTOP_ENVIRONMENT:-kde}"
DESKTOP_ENV_LOWER="${DESKTOP_ENVIRONMENT,,}"
echo "[selkies-session] Target desktop environment: ${DESKTOP_ENV_LOWER}"

# Disable screen blanking / powerdown
setterm blank 0 2>/dev/null || true
setterm powerdown 0 2>/dev/null || true

# Prepare shared X11 directory
mkdir -p /tmp/.X11-unix 2>/dev/null || true
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

# 4. Desktop-specific configuration and environment
if [ "${DESKTOP_ENV_LOWER}" = "xfce" ]; then
  # XFCE configuration and directories
  mkdir -p "${HOME}/.config/xfce4/labwc" "${HOME}/.config/autostart" 2>/dev/null || true

  # Seed labwc default configuration for XFCE if not present
  if [ ! -f "${HOME}/.config/xfce4/labwc/rc.xml" ] && [ -f /usr/share/xfce4/labwc/labwc-rc.xml ]; then
    cp -p /usr/share/xfce4/labwc/labwc-rc.xml "${HOME}/.config/xfce4/labwc/rc.xml" 2>/dev/null || true
  fi
  if [ ! -f "${HOME}/.config/xfce4/labwc/environment" ] && [ -f /usr/share/xfce4/labwc/labwc-environment ]; then
    cp -p /usr/share/xfce4/labwc/labwc-environment "${HOME}/.config/xfce4/labwc/environment" 2>/dev/null || true
  fi

  # XFCE Wayland session environment
  export XDG_CURRENT_DESKTOP=XFCE
  export XDG_SESSION_DESKTOP=xfce
  export XDG_SESSION_TYPE=wayland
  export DESKTOP_SESSION=xfce
  export GDK_BACKEND="wayland,x11"
  export QT_QPA_PLATFORM=wayland
  export CLUTTER_BACKEND=gdk
  export SDL_VIDEODRIVER=wayland
  export MOZ_ENABLE_WAYLAND=1
  export LABWC_UPDATE_ACTIVATION_ENV=1
  export WLR_NO_HARDWARE_CURSORS=1

  # Software rendering fallback for LXC without GPU passthrough
  if [ "${KWIN_COMPOSE}" = "Q" ] || [ "${KWIN_COMPOSE}" = "QPainter" ]; then
    export WLR_RENDERER=pixman
  fi
else
  # KDE initial configuration (only if not already existing)
  mkdir -p "${HOME}/.config" "${HOME}/.local/share" "${HOME}/.config/autostart" 2>/dev/null || true

  # Configure KWin compositing & screen locking
  if [ ! -f "${HOME}/.config/kwinrc" ]; then
    if [ "${KWIN_COMPOSE}" = "O2" ] || [ "${KWIN_COMPOSE}" = "OpenGL" ]; then
      kwriteconfig6 --file "${HOME}/.config/kwinrc" --group Compositing --key Backend "OpenGL" 2>/dev/null || true
      kwriteconfig6 --file "${HOME}/.config/kwinrc" --group Compositing --key Enabled true 2>/dev/null || true
    else
      kwriteconfig6 --file "${HOME}/.config/kwinrc" --group Compositing --key Backend "QPainter" 2>/dev/null || true
      kwriteconfig6 --file "${HOME}/.config/kwinrc" --group Compositing --key Enabled false 2>/dev/null || true
    fi
  fi

  if [ ! -f "${HOME}/.config/kscreenlockerrc" ]; then
    kwriteconfig6 --file "${HOME}/.config/kscreenlockerrc" --group Daemon --key Autolock false 2>/dev/null || true
  fi

  if [ ! -f "${HOME}/.config/baloofilerc" ]; then
    kwriteconfig6 --file "${HOME}/.config/baloofilerc" --group "Basic Settings" --key "Indexing-Enabled" false 2>/dev/null || true
  fi

  # Permissive clipboard rules for wl-clipboard
  KWIN_RULES_FILE="${HOME}/.config/kwinrulesrc"
  RULE_DESC="wl-clipboard support"
  if ! grep -q "$RULE_DESC" "$KWIN_RULES_FILE" 2>/dev/null; then
    if command -v kreadconfig6 >/dev/null 2>&1 && command -v kwriteconfig6 >/dev/null 2>&1; then
      RULE_ID="wl-clipboard-rule"
      count=$(kreadconfig6 --file "$KWIN_RULES_FILE" --group General --key count --default 0 2>/dev/null || echo 0)
      count=${count:-0}
      new_count=$((count + 1))
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key count "$new_count" 2>/dev/null || true
      existing_rules=$(kreadconfig6 --file "$KWIN_RULES_FILE" --group General --key rules 2>/dev/null || true)
      if [ -z "$existing_rules" ]; then
        kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key rules "$RULE_ID" 2>/dev/null || true
      else
        kwriteconfig6 --file "$KWIN_RULES_FILE" --group General --key rules "$existing_rules,$RULE_ID" 2>/dev/null || true
      fi
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key Description "$RULE_DESC" 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key wmclass "wl-(copy|paste)" 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key wmclassmatch 3 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skiptaskbar --type bool "true" 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skiptaskbarrule 2 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skipswitcher --type bool "true" 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key skipswitcherrule 2 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key fsplevel 3 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key fsplevelrule 2 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key noborder --type bool "true" 2>/dev/null || true
      kwriteconfig6 --file "$KWIN_RULES_FILE" --group "$RULE_ID" --key noborderrule 2 2>/dev/null || true
    fi
  fi

  # Plasma session environment
  export XDG_CURRENT_DESKTOP=KDE
  export XDG_SESSION_TYPE=wayland
  export XDG_MENU_PREFIX=plasma-
  export KDE_FULL_SESSION=true
  export KDE_SESSION_VERSION=6
  export KDE_SESSION_UID="$(id -u)"
  export QT_QPA_PLATFORM=wayland
  export DISPLAY=:1
  export MOZ_ENABLE_WAYLAND=1
  export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1

  if [ -n "$KWIN_COMPOSE" ]; then
    export KWIN_COMPOSE
  fi

  # Source KDE workspace environment scripts if present
  for env_sh in /etc/xdg/plasma-workspace/env/*.sh "${HOME}"/.config/plasma-workspace/env/*.sh; do
    if [ -r "${env_sh}" ]; then
      . "${env_sh}"
    fi
  done

  # Initialize application cache
  command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 2>/dev/null || true
fi

# Accessibility flags for Pelorus AI navigator
if [ "${PELORUS,,}" = "true" ]; then
  export QT_ACCESSIBILITY=1
  export QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
  export GTK_MODULES=gail:atk-bridge
fi

# 5. Launch nested compositor (client to wayland-1, hosting wayland-0)
if [ "${DESKTOP_ENV_LOWER}" = "xfce" ]; then
  echo "[selkies-session] Starting Labwc nested compositor for XFCE..."
  LABWC_ARGS=()
  if [ -f "${HOME}/.config/xfce4/labwc/rc.xml" ]; then
    LABWC_ARGS+=(--config-dir "${HOME}/.config/xfce4/labwc" --config "${HOME}/.config/xfce4/labwc/rc.xml")
  fi
  WAYLAND_DISPLAY=wayland-1 labwc "${LABWC_ARGS[@]}" &
  COMPOSITOR_PID=$!
else
  echo "[selkies-session] Starting KWin Wayland nested compositor for KDE..."
  WAYLAND_DISPLAY=wayland-1 python3 /usr/local/bin/kwin-xwayland.py &
  COMPOSITOR_PID=$!
fi

# Wait for nested compositor socket (wayland-0)
for _ in $(seq 1 100); do
  if [ -S "${SOCKET_DIR}/wayland-0" ]; then
    break
  fi
  if ! kill -0 "$COMPOSITOR_PID" 2>/dev/null; then
    echo "[selkies-session] Error: Nested compositor process died unexpectedly!" >&2
    exit 1
  fi
  sleep 0.1
done

if [ ! -S "${SOCKET_DIR}/wayland-0" ]; then
  echo "[selkies-session] Warning: wayland-0 socket not detected yet, continuing..." >&2
fi

export WAYLAND_DISPLAY=wayland-0
command -v dbus-update-activation-environment >/dev/null 2>&1 && dbus-update-activation-environment --all 2>/dev/null || true

# 6. Desktop helper daemons and authentication agent
if [ "${DESKTOP_ENV_LOWER}" != "xfce" ]; then
  command -v kcminit_startup >/dev/null 2>&1 && kcminit_startup 2>/dev/null || true
  command -v kded6 >/dev/null 2>&1 && kded6 &
fi

# Polkit authentication agent
for polkit_agent in \
    /usr/libexec/polkit-mate-authentication-agent-1 \
    /usr/libexec/kf6/polkit-kde-authentication-agent-1 \
    /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1 \
    /usr/lib/*/libexec/polkit-kde-authentication-agent-1 \
    /usr/lib/polkit-kde-authentication-agent-1 \
    /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
    /usr/bin/lxpolkit; do
  if [ -x "$polkit_agent" ]; then
    "$polkit_agent" &
    break
  fi
done

# 7. Pelorus & Accessibility initialization
PELORUS_PID=""
if [ "${PELORUS,,}" = "true" ]; then
  echo "[selkies-session] Initializing accessibility and Pelorus AI navigator..."

  # Enable accessibility property on D-Bus
  dbus-send --session --dest=org.a11y.Bus --type=method_call \
    --print-reply /org/a11y/bus org.freedesktop.DBus.Properties.Set \
    string:org.a11y.Status string:IsEnabled variant:boolean:true 2>/dev/null || true

  # Start at-spi2-registryd if not already running
  if ! pgrep -x at-spi2-registryd >/dev/null 2>&1; then
    for atspi in /usr/libexec/at-spi2-registryd /usr/lib/at-spi2-core/at-spi2-registryd; do
      if [ -x "$atspi" ]; then
        "$atspi" &
        break
      fi
    done
  fi

  # Start Pelorus AI navigator
  PELORUS_BIN=""
  if [ -x /usr/local/bin/pelorus ]; then
    PELORUS_BIN="/usr/local/bin/pelorus"
  elif [ -x /lsiopy/bin/pelorus ]; then
    PELORUS_BIN="/lsiopy/bin/pelorus"
  elif command -v pelorus >/dev/null 2>&1; then
    PELORUS_BIN="$(command -v pelorus)"
  fi

  if [ -n "$PELORUS_BIN" ]; then
    "$PELORUS_BIN" > /tmp/pelorus.log 2>&1 &
    PELORUS_PID=$!
    sleep 1
    if kill -0 "$PELORUS_PID" 2>/dev/null; then
      echo "[selkies-session] Pelorus started on port ${PELORUS_PORT:-5100} (PID: $PELORUS_PID)"
    else
      echo "[selkies-session] Warning: Pelorus exited prematurely, inspect /tmp/pelorus.log" >&2
    fi
  else
    echo "[selkies-session] Warning: pelorus executable not found in PATH or /lsiopy/bin" >&2
  fi
fi

# 8. Start primary Desktop Session
if [ "${DESKTOP_ENV_LOWER}" = "xfce" ]; then
  echo "[selkies-session] Starting XFCE session (xfce4-session)..."
  xfce4-session &
  SESSION_PID=$!

  # Wait for xfce4-session to appear on D-Bus
  for _ in $(seq 1 150); do
    if dbus-send --session --print-reply --dest=org.freedesktop.DBus \
      /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
      string:org.xfce.SessionManager 2>/dev/null | grep -q true; then
      break
    fi
    sleep 0.1
  done
else
  # Tray icons proxy for Plasma
  command -v xembedsniproxy >/dev/null 2>&1 && xembedsniproxy &

  echo "[selkies-session] Starting plasmashell..."
  plasmashell &
  SESSION_PID=$!

  # Wait for plasmashell to appear on D-Bus
  for _ in $(seq 1 150); do
    if dbus-send --session --print-reply --dest=org.freedesktop.DBus \
      /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
      string:org.kde.plasmashell 2>/dev/null | grep -q true; then
      break
    fi
    sleep 0.1
  done
fi

command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update 2>/dev/null || true
command -v gmenudbusmenuproxy >/dev/null 2>&1 && gmenudbusmenuproxy &
command -v xhost >/dev/null 2>&1 && xhost +si:localuser:root 2>/dev/null || true

# Autostart desktop entries
for entry in "${HOME}"/.config/autostart/*.desktop; do
  if [ -f "${entry}" ] && ! grep -q "^Hidden=true" "${entry}"; then
    entry_cmd=$(grep -m1 "^Exec=" "${entry}" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
    if [ -n "${entry_cmd}" ]; then
      bash -c "${entry_cmd}" &
    fi
  fi
done

# Wait for primary session process to exit
wait "${SESSION_PID}"

# Cleanup
echo "[selkies-session] Desktop session terminated, cleaning up..."
kill "${COMPOSITOR_PID}" 2>/dev/null || true
[ -n "${PELORUS_PID}" ] && kill "${PELORUS_PID}" 2>/dev/null || true
