#!/bin/bash
set -e

echo "=== 1. Configuración de configuration.yaml ==="
cat << 'EOF' > /home/cat/config/configuration.yaml
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - "::1"
    - 172.16.0.0/12
    - 192.168.0.0/16
  cors_allowed_origins:
    - https://www.horussmartenergyapp.com
    - https://staging.horussmartenergyapp.com
    - https://develop.horussmartenergyapp.com
  use_x_frame_options: false
EOF

echo "=== 2. Descarga e Instalación de Custom Components ==="
mkdir -p /home/cat/config/custom_components

# REEMPLAZA 'TuUsuario', 'TuRepositorio', 'main' y el nombre del ZIP por los tuyos:
URL_ZIP="https://raw.githubusercontent.com/auxinvestigacion-lang/update_ha_zwave/main/horus-integration-nexxo-1.4.3"

curl -sSL "$URL_ZIP" -o /tmp/componente.zip
unzip -o /tmp/componente.zip -d /home/cat/config/custom_components/
rm -f /tmp/componente.zip

echo "=== 3. Limpieza y Liberación de Espacio ==="
sudo apt-get clean
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache /home/cat/*.zip /home/cat/config/config
sudo journalctl --vacuum-time=1d
docker image prune -f
df -h /

echo "=== 4. Remoción de la Versión Antigua ==="
docker stop homeassistant || true
docker rm homeassistant || true
docker images
docker rmi -f f0baa7922ece || true
docker system prune -f
docker builder prune -af
df -h /

echo "=== 5. Despliegue de la Versión Nueva ==="
cd /home/cat
docker compose up -d --pull always
docker ps
docker exec homeassistant hass --version
cd ~

echo "=== 6. Actualización de Z-Wave UI ==="
sudo systemctl stop zwave-ui.service
sudo npm install -g zwave-js-ui@latest --unsafe-perm
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache
sudo systemctl restart zwave-ui.service
sudo systemctl status zwave-ui.service

echo "=== 7. Verificación Final y Reinicio de Home Assistant ==="
docker restart homeassistant || true
df -h /
docker ps
sudo systemctl is-active zwave-ui.service
du -m /home/cat/config/home-assistant_v2.db || true

echo "--- Versiones Instaladas ---"
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~