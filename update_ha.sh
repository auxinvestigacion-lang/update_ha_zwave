#!/bin/bash

set -e

echo "=== 1. Instalación de Nexxo LED Manager ==="
wget -qO- https://raw.githubusercontent.com/jse-che/nexxo-led-manager/main/install.sh | sh

echo "=== 2. Instalación de Cloudflare ==="
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg>/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

# Se ignora la comprobación de vigencia de firmas/fechas de los repositorios
sudo apt-get update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false && sudo apt-get install -y cloudflared


# --- Solicitud e Instalación de Cloudflare ---
echo "=== Configuración e Instalación del Servicio de Cloudflare ==="
read -p "Pega el comando de instalación de Cloudflare (o presiona Enter para omitir): " CLOUDFLARE_INPUT </dev/tty

# Extrae únicamente el token largo en Base64 si pegaste el comando completo
CLOUDFLARE_TOKEN=$(echo "$CLOUDFLARE_INPUT" | grep -oE 'eyJ[A-Za-z0-9+/=_-]+' | head -n 1)

# Si no es un comando con 'eyJ', toma la entrada limpia por si se ingresó el token directo
if [ -z "$CLOUDFLARE_TOKEN" ]; then
    CLOUDFLARE_TOKEN=$(echo "$CLOUDFLARE_INPUT" | tr -d "[:space:]'\"")
fi

if [ -n "$CLOUDFLARE_TOKEN" ]; then
    echo "Instalando servicio de Cloudflare con el token detectado..."
    sudo cloudflared service install "$CLOUDFLARE_TOKEN" || true
else
    echo "No se ingresó un comando/token válido. Omitiendo vinculación de Cloudflare."
fi

echo "=== 3. Configuración de configuration.yaml (Limpio para HA 2026.8+) ==="
cat << 'EOF'> /home/cat/config/configuration.yaml
# Loads default set of integrations. Do not remove.
default_config:

# Load frontend themes from the themes folder
frontend:
  themes: !include_dir_merge_named themes

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF

echo "=== 4. Limpieza de componentes antiguos e Instalación de Custom Components ==="
mkdir -p /home/cat/config/custom_components

# Borrado de carpetas específicas en custom_components
sudo rm -rf /home/cat/config/custom_components/hacs
sudo rm -rf /home/cat/config/custom_components/nodered
sudo rm -rf /home/cat/config/custom_components/webrtc


# URLs de los componentes en GitHub
URLS=(
    "https://raw.githubusercontent.com/auxinvestigacion-lang/update_ha_zwave/main/plugin_service_energy.zip"
    "https://raw.githubusercontent.com/auxinvestigacion-lang/update_ha_zwave/main/admin_network.zip"
)

# Directorio de destino de Home Assistant
DESTINO="/home/cat/config/custom_components/"

for url in "${URLS[@]}"; do
    echo "Procesando: $url..."
    curl -sSL "$url" -o /tmp/componente.zip

    if unzip -t /tmp/componente.zip >/dev/null 2>&1; then
        unzip -o /tmp/componente.zip -d "$DESTINO"
        rm -f /tmp/componente.zip
        echo " -> Instalado exitosamente."
    else
        echo " -> ERROR: No se pudo descargar un ZIP válido desde $url"
        rm -f /tmp/componente.zip
        exit 1
    fi
done

echo "Todos los componentes se instalaron correctamente."

docker restart homeassistant || true

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

echo "=== 7. Inyección de Configuración HTTP en .storage ==="
mkdir -p /home/cat/config/.storage

cat << 'EOF'> /home/cat/config/.storage/http
{
  "version": 2,
  "minor_version": 2,
  "key": "http",
  "data": {
    "stable": {
      "server_port": 8123,
      "cors_allowed_origins": [
        "https://cast.home-assistant.io",
        "https://www.horussmartenergyapp.com",
        "https://staging.horussmartenergyapp.com",
        "https://develop.horussmartenergyapp.com"
      ],
      "use_x_forwarded_for": true,
      "trusted_proxies": [
        "127.0.0.1/32",
        "::1/128"
      ],
      "login_attempts_threshold": -1,
      "ip_ban_enabled": true,
      "ssl_profile": "modern",
      "use_x_frame_options": false
    },
    "pending": null,
    "yaml_migration_done": true
  }
}
EOF

# Ajustar permisos por si se ejecuta como root
sudo chown -R cat:cat /home/cat/config/.storage/http 2>/dev/null || true
sudo chmod 644 /home/cat/config/.storage/http

echo "=== 8. Despliegue de la Versión Nueva ==="
cd /home/cat
docker compose up -d --pull always
docker ps
docker exec homeassistant hass --version
cd ~

echo "=== 9. Actualización de Z-Wave UI ==="
sudo systemctl stop zwave-ui.service
sudo npm install -g zwave-js-ui@latest
sudo npm cache clean --force
sudo rm -rf /root/.npm/_cacache
sudo systemctl restart zwave-ui.service
sudo systemctl status zwave-ui.service

echo "=== 10. Verificación Final y Reinicio de Home Assistant ==="
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