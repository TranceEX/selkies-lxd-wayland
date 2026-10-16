#!/usr/bin/env python3
"""
kwin-xwayland wrapper for Selkies nested session.
Binds a fixed UNIX socket in /tmp/.X11-unix/X<num> and passes it to kwin_wayland
via --xwayland-fd so that X11 applications can deterministically connect to DISPLAY.
"""
import os
import socket
import sys

display_env = os.environ.get("DISPLAY", ":1")
display_num = display_env.lstrip(":")
path = f"/tmp/.X11-unix/X{display_num}"

os.makedirs("/tmp/.X11-unix", exist_ok=True)
if os.path.exists(path):
    try:
        os.remove(path)
    except OSError as e:
        sys.stderr.write(f"Warning: could not remove existing {path}: {e}\n")

has_fd = False
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.listen(128)
    fd = s.fileno()
    os.set_inheritable(fd, True)
    has_fd = True
except Exception as e:
    sys.stderr.write(f"Warning: failed to bind {path}: {e}\n")

if has_fd:
    args = [
        "kwin_wayland",
        "--no-lockscreen",
        "--xwayland",
        f"--xwayland-display=:{display_num}",
        f"--xwayland-fd={fd}",
    ]
else:
    args = [
        "kwin_wayland",
        "--no-lockscreen",
        "--xwayland",
    ]

try:
    os.execlp("kwin_wayland", *args)
except Exception as exc:
    sys.stderr.write(f"Failed to exec kwin_wayland: {exc}\n")
    sys.exit(1)
