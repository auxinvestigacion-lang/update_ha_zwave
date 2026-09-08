#!/bin/bash
set -e

echo "=== 1. Limpieza y Liberación de Espacio ==="
sudo apt-get clean  
sudo npm cache clean --force  
sudo rm -rf /root/.npm/_cacache /home/cat/*.zip /home/cat/config/config  
sudo journalctl --vacuum-time=1d  
docker image prune -f  
df -h /

echo "=== 2. Remoción de la Versión Antigua ==="
docker stop homeassistant || true
docker rm homeassistant || true
docker images  
docker rmi -f f0baa7922ece || true
docker system prune -f  
docker builder prune -af  
df -h /

echo "=== 3. Despliegue de la Versión Nueva ==="
cd /home/cat  
docker compose up -d --pull always  
docker ps  
docker exec homeassistant hass --version
cd ~

echo "=== 4. Actualización de Z-Wave UI ==="
sudo systemctl stop zwave-ui.service  
sudo npm install -g zwave-js-ui@latest --unsafe-perm  
sudo npm cache clean --force  
sudo rm -rf /root/.npm/_cacache  
sudo systemctl restart zwave-ui.service  
sudo systemctl status zwave-ui.service

echo "=== 5. Verificación Final y Cierre ==="
df -h /  
docker ps  
sudo systemctl is-active zwave-ui.service  
du -m /home/cat/config/home-assistant_v2.db

echo "--- Versiones Instaladas ---"
docker exec homeassistant hass --version
npm list -g zwave-js-ui
cd ~