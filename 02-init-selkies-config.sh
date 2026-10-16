#!/bin/bash
set -e

# JS log setup
touch /tmp/selkies_js.log
chmod 777 /tmp/selkies_js.log

# Device permissions if mapped into container
for i in $(seq 0 3); do
  if [ -e "/dev/input/js$i" ]; then
    chmod 777 "/dev/input/js$i"
  fi
  if [ -e "/dev/input/event$((1000+i))" ]; then
    chmod 777 "/dev/input/event$((1000+i))"
  fi
done

# Manifest creation for web app
MANIFEST_CONTENT='{
  "name": "Selkies",
  "short_name": "Selkies",
  "manifest_version": 2,
  "version": "1.0.0",
  "display": "fullscreen",
  "background_color": "#000000",
  "theme_color": "#000000",
  "icons": [
    {
      "src": "icon.png",
      "type": "image/png",
      "sizes": "180x180"
    }
  ],
  "start_url": "/"
}'

if [ -d "/usr/share/selkies/web" ]; then
  echo "$MANIFEST_CONTENT" > /usr/share/selkies/web/manifest.json
fi

if [ -d "/usr/share/selkies/www" ]; then
  echo "$MANIFEST_CONTENT" > /usr/share/selkies/www/manifest.json
fi

echo "Selkies configuration initialization completed successfully."
