#!/bin/bash
set -e

# LXD Host script for mapping joystick devices to the container
CONTAINER="${1:-selkies}"

echo "Configuring joysticks on LXD host for container: $CONTAINER"
mkdir -pm1777 /dev/input
for i in $(seq 0 3); do
  [ -e "/dev/input/js$i" ] || mknod "/dev/input/js$i" c 13 "$i"
  chmod 777 "/dev/input/js$i"
  lxc config device add "$CONTAINER" "js$i" unix-char path="/dev/input/js$i" 2>/dev/null || true
done
for i in $(seq 0 3); do
  [ -e "/dev/input/event$((1000+i))" ] || mknod "/dev/input/event$((1000+i))" c 13 "$((1064+i))"
  chmod 777 "/dev/input/event$((1000+i))"
  lxc config device add "$CONTAINER" "event$((1000+i))" unix-char path="/dev/input/event$((1000+i))" 2>/dev/null || true
done

echo "Joystick device mapping for container '$CONTAINER' completed."
