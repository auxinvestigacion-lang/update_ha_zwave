#!/bin/bash
set -e

echo "=== 1. Instalación de Cloudflare ==="
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg>/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# Se ignora la comprobación de vigencia de firmas/fechas de los repositorios
sudo apt-get update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false && sudo apt-get install -y cloudflared

echo "=== 3. Configuración de configuration.yaml ==="
cat << 'EOF'> /home/cat/config/configuration.yaml
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

echo "=== 4. Limpieza de componentes antiguos e Instalación de Custom Components ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/hacs
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc

# REEMPLAZA con la URL RAW exacta de tu ZIP en GitHub
URL_ZIP="https://raw.githubusercontent.com/auxinvestigacion-lang/update_ha_zwave/main/plugin_service_v1.4.zip"

curl -sSL "$URL_ZIP" -o /tmp/componente.zip

if unzip -t /tmp/componente.zip >/dev/null 2>&1; then
    unzip -o /tmp/componente.zip -d /home/cat/config/custom_components/
    rm -f /tmp/componente.zip
    echo "Componente personalizado instalado exitosamente."
else
    echo "ERROR: No se pudo descargar un archivo ZIP válido desde GitHub."
    echo "Revisa que la URL ($URL_ZIP) sea pública y correcta."
    rm -f /tmp/componente.zip
    exit 1
fi

echo "=== 5. Limpieza y Liberación de Espacio ==="
sudo apt-get clean
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache /home/cat/*.zip /home/cat/config/config
sudo journalctl --vacuum-time=1d
docker image prune -f
df -h /

echo "=== 6. Remoción de la Versión Antigua ==="
docker stop homeassistant || true
docker rm homeassistant || true
docker images
docker rmi -f f0baa7922ece || true
docker system prune -f
docker builder prune -af
df -h /

echo "=== 7. Despliegue de la Versión Nueva ==="
cd /home/cat
docker compose up -d --pull always
docker ps
docker exec homeassistant hass --version
cd ~

echo "=== 8. Actualización de Z-Wave UI ==="
sudo systemctl stop zwave-ui.service
sudo npm install -g zwave-js-ui@latest --unsafe-perm
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache
sudo systemctl restart zwave-ui.service
sudo systemctl status zwave-ui.service

echo "=== 9. Verificación Final y Reinicio de Home Assistant ==="
docker restart homeassistant || true
df -h /
docker ps
sudo systemctl is-active zwave-ui.service
du -m /home/cat/config/home-assistant_v2.db || true

echo "--- Versiones e Instalación Finalizadas ---"
cloudflared --version
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~

echo "=== 10. Instalación de Nexxo LED Manager ==="
wget -qO- https://raw.githubusercontent.com/jse-che/nexxo-led-manager/main/install.sh | sh
