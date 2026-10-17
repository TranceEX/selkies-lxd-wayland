# selkies-lxd-wayland (Wayland + Pelorus)

Installation and setup scripts for Selkies in native **Wayland** mode with **Pelorus** AI navigator for **LXC/LXD** containers. Supports **KDE Plasma** and **XFCE**.

Based on [Selkies Base Images from LinuxServer.io](https://github.com/linuxserver/docker-baseimage-selkies), but runs natively inside an LXC container under `systemd --user` control without requiring Docker.

---

## Architecture Overview

- **Pixelflux (Smithay)**: In-process Wayland compositor inside the Selkies daemon listening on socket `wayland-1` (WebRTC / HTTPS streaming).
- **Nested Wayland Compositor**:
  - **KDE Plasma**: Uses **KWin Wayland** (nested client to `wayland-1`, hosting `wayland-0` and XWayland).
  - **XFCE**: Uses **Labwc** (wlroots-based stacking compositor nested to `wayland-1`, hosting `wayland-0` and XWayland).
- **XWayland**: Provides compatibility for legacy X11 applications.
- **Pelorus**: AI navigation agent (FastAPI on port 5100, proxied via Nginx at `/pelorus/`), collecting window state and accessibility trees via AT-SPI2 / D-Bus, dispatching input actions to the Pixelflux Computer Use API (port 5000).
- **PulseAudio**: Audio handling with virtual null-sinks `output` and `input`.

---

## Requirements

1. **LXC/LXD Container** (Debian 13 Trixie or compatible)
2. **Supported Architectures**: `x86_64` or `aarch64`.
3. **Optional GPU Acceleration**:
   - By default, software rendering is enabled (`KWIN_COMPOSE=Q`).
   - If GPU passthrough is configured from the LXD host:
     ```bash
     lxc config device add <container_name> gpu gpu
     ```
     Set `KWIN_COMPOSE=O2` (OpenGL) in `~/.config/selkies/selkies.env`.

---

## Installation

Inside the LXC container (as a regular user with `sudo` privileges):

```bash
git clone https://github.com/TranceEX/selkies-lxd-wayland.git
cd selkies-lxd-wayland
bash setup.sh
```

You can select the Desktop Environment interactively during setup, or specify it via argument or environment variable:

```bash
# Install with XFCE (Wayland + Labwc)
DESKTOP_ENV=xfce bash setup.sh
# or
bash setup.sh xfce

# Install with KDE Plasma (default)
DESKTOP_ENV=kde bash setup.sh
# or
bash setup.sh kde
```

The script will automatically:

- Verify CPU architecture (`x86_64` or `aarch64`).
- Install system packages for the chosen desktop environment (KDE Plasma or XFCE + Labwc), Nginx, PulseAudio, and utilities.
- Pull the Selkies image via udocker and extract the input interposer (`selkies_input_interposer.so`), `/lsiopy`, and web assets.
- Configure Nginx with SSL certificates and Pelorus reverse proxy.
- Install and enable `systemd --user` services (`pulseaudio`, `selkies`, `desktop`).

---

## Configuration (`~/.config/selkies/selkies.env`)

The main environment configuration file is installed at `~/.config/selkies/selkies.env`. Changes take effect after restarting user services (`systemctl --user restart selkies desktop`).

Key environment variables:
- `DESKTOP_ENVIRONMENT=kde` - Target desktop: `kde` (KDE Plasma) or `xfce` (XFCE + Labwc).
- `PIXELFLUX_WAYLAND=true` - Enables Wayland mode in Pixelflux.
- `PIXELFLUX_CU=5000` - Pixelflux Computer Use API port (required by Pelorus).
- `PELORUS=true` - Activates the Pelorus agent and web UI.
- `PELORUS_PROVIDER` - LLM provider (`ollama`, OpenAI-compatible, or `gemini`).
- `PELORUS_ENDPOINT` - Model API endpoint URL (e.g. `http://localhost:11434`).
- `PELORUS_MODEL` - Model name (e.g. `gemma4:12b`).
- `PELORUS_API_KEY` - Optional API key.
- `KWIN_COMPOSE=Q` - Compositor backend (`Q` for software rendering, `O2` for OpenGL with GPU passthrough).

Pelorus server configurations are stored in `/config/agent/config.toml` and can also be modified at runtime via the `/pelorus/` web interface.

---

## Security Notice

> [!WARNING]
> The **Pelorus** agent listens on port `5100` without built-in authentication, and Pixelflux Computer Use listens on port `5000`. This grants full desktop control to anyone who can connect to these ports.

Security recommendations:
1. **Never expose ports 5000 or 5100 directly to external networks.**
2. Access Pelorus solely via Nginx at `https://<ip>:3001/pelorus/`.
3. To enable HTTP Basic Authentication, set the `PASSWORD` variable before running `setup.sh`:
   ```bash
   PASSWORD="your_secure_password" bash setup.sh
   ```
4. LLM provider API keys are saved in `/config/agent/config.toml` - ensure proper user file permissions.

---

## Joystick / Gamepad Setup

To use game controllers inside the container, execute the following script on the **LXD host** before starting the container session:

```bash
bash 00-lxd-host-joystick.sh <container_name>
```

This creates `/dev/input/js0-3` and `/dev/input/event1000-1003` device nodes and passes them into the specified container.

---

## Access URLs

- **Selkies Desktop (HTTPS)**: `https://<container_ip>:3001/`
- **Selkies Desktop (HTTP)**: `http://<container_ip>:3000/`
- **Pelorus AI Interface**: `https://<container_ip>:3001/pelorus/`
- **Pelorus OpenAPI Docs**: `https://<container_ip>:3001/pelorus/docs`

---

## Verification & Troubleshooting

Check services and logs after installation:

```bash
# 1. Check user systemd services status
systemctl --user status pulseaudio selkies desktop

# 2. Check Selkies logs (look for: "Socket listening on: wayland-1")
journalctl --user -u selkies -n 80 --no-pager

# 3. Check desktop session and KWin/Pelorus logs
journalctl --user -u desktop -n 80 --no-pager

# 4. Check Wayland sockets (wayland-1 and wayland-0 should both exist)
ls -l "$XDG_RUNTIME_DIR"/wayland-*

# 5. Check open listening ports
ss -ltnp | grep -E ':(3000|3001|5000|5100|8082)\b'

# 6. Test Nginx configuration and HTTPS response
sudo nginx -t && curl -skI https://localhost:3001/ | head -n 5

# 7. Verify Pelorus window detection
curl -s http://127.0.0.1:5100/api/windows
```

### Common Issues:

- **Black screen in browser**: Ensure `KWIN_COMPOSE=Q` is set in `~/.config/selkies/selkies.env` (for non-GPU LXC), then restart the desktop: `systemctl --user restart desktop`.
- **502 Bad Gateway under `/pelorus/`**: Check that the desktop service spawned the Pelorus process (`pgrep -a pelorus`) and verify `PIXELFLUX_CU=5000` is present in `selkies.service`.

## License & Acknowledgements

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for details.

### Acknowledgements
This project is based on, adapts, or utilizes components developed by the [LinuxServer.io](https://www.linuxserver.io/) team, specifically:
- **Pelorus** ([docker-pelorus](https://github.com/linuxserver/docker-pelorus))
- **Selkies** ([docker-selkies](https://github.com/linuxserver/docker-selkies))

Special thanks to LinuxServer.io and the respective upstream contributors for their open-source work.
