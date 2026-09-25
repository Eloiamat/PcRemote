#!/bin/bash

set -e

# ============================================================
# PcRemote - Instalador automático para Ubuntu
# ============================================================

PROJECT_DIR="$HOME/PcRemote"
SERVICE_NAME="pcremote"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PORT="5000"
DEFAULT_PIN="123456"

echo ""
echo "=============================================="
echo "          PcRemote - Instalador"
echo "=============================================="
echo ""

# ------------------------------------------------------------
# 1. Comprobar Ubuntu
# ------------------------------------------------------------
if [ ! -f /etc/os-release ]; then
    echo "[ERROR] No se ha podido detectar el sistema operativo."
    exit 1
fi

. /etc/os-release

if [ "$ID" != "ubuntu" ]; then
    echo "[ERROR] Este instalador está preparado para Ubuntu."
    echo "Sistema detectado: $PRETTY_NAME"
    exit 1
fi

echo "[OK] Ubuntu detectado: $PRETTY_NAME"

# ------------------------------------------------------------
# 2. Comprobar sudo
# ------------------------------------------------------------
if ! sudo -v; then
    echo "[ERROR] Se necesitan permisos sudo."
    exit 1
fi

echo "[OK] Permisos sudo disponibles."

# ------------------------------------------------------------
# 3. Instalar herramientas necesarias
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "       Comprobando herramientas necesarias"
echo "=============================================="

sudo apt-get update

PACKAGES=()

if ! command -v curl >/dev/null 2>&1; then
    PACKAGES+=("curl")
fi

if ! command -v python3 >/dev/null 2>&1; then
    PACKAGES+=("python3")
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
    PACKAGES+=("python3-venv")
fi

if ! command -v ufw >/dev/null 2>&1; then
    PACKAGES+=("ufw")
fi

if [ ${#PACKAGES[@]} -gt 0 ]; then
    echo "[INFO] Instalando: ${PACKAGES[*]}"
    sudo apt-get install -y "${PACKAGES[@]}"
else
    echo "[OK] Todas las herramientas necesarias están instaladas."
fi

# ------------------------------------------------------------
# 4. Comprobar archivos de PcRemote
# ------------------------------------------------------------
if [ ! -f "./app.py" ]; then
    echo "[ERROR] No se encuentra app.py."
    echo "Ejecuta este instalador desde la carpeta de PcRemote."
    exit 1
fi

if [ ! -f "./requirements.txt" ]; then
    echo "[ERROR] No se encuentra requirements.txt."
    exit 1
fi

if [ ! -d "./static" ] || [ ! -d "./templates" ]; then
    echo "[ERROR] Faltan las carpetas static/ o templates/."
    exit 1
fi

# ------------------------------------------------------------
# 5. Copiar proyecto a ~/PcRemote
# ------------------------------------------------------------
CURRENT_DIR="$(pwd)"

if [ "$CURRENT_DIR" != "$PROJECT_DIR" ]; then
    echo ""
    echo "[INFO] Copiando PcRemote a $PROJECT_DIR..."

    mkdir -p "$PROJECT_DIR"

    cp -r app.py requirements.txt static templates "$PROJECT_DIR/"

    for FILE in manifest.json sw.js offline.html; do
        if [ -e "$FILE" ]; then
            cp -r "$FILE" "$PROJECT_DIR/"
        fi
    done
else
    echo "[OK] Proyecto ubicado en $PROJECT_DIR."
fi

cd "$PROJECT_DIR"

# ------------------------------------------------------------
# 6. Instalar Tailscale
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "              Configurando Tailscale"
echo "=============================================="

if ! command -v tailscale >/dev/null 2>&1; then
    echo "[INFO] Tailscale no está instalado."
    echo "[INFO] Instalándolo..."

    curl -fsSL https://tailscale.com/install.sh | sh

    if ! command -v tailscale >/dev/null 2>&1; then
        echo "[ERROR] Tailscale no se ha podido instalar."
        exit 1
    fi

    echo "[OK] Tailscale instalado."
else
    echo "[OK] Tailscale ya está instalado."
fi

# ------------------------------------------------------------
# 7. Registrar el PC en Tailscale
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "          REGISTRO DE TAILSCALE"
echo "=============================================="
echo ""
echo "Se va a registrar este PC en Tailscale."
echo ""
echo "Cuando aparezca un enlace:"
echo "  1. Ábrelo en el navegador."
echo "  2. Inicia sesión."
echo "  3. Autoriza este dispositivo."
echo ""
echo "IMPORTANTE: utiliza la misma cuenta que usarás"
echo "en el móvil. No utilices una cuenta @iesebre.cat."
echo ""

# Comprobar si ya está autenticado.
if ! sudo tailscale ip -4 >/dev/null 2>&1; then
    sudo tailscale up
fi

echo ""
echo "[INFO] Esperando a que Tailscale quede conectado..."
echo ""

TAILSCALE_IP=""

for i in {1..60}; do
    TAILSCALE_IP="$(sudo tailscale ip -4 2>/dev/null | head -n 1 || true)"

    if [[ "$TAILSCALE_IP" =~ ^100\. ]]; then
        break
    fi

    sleep 2
done

if [[ ! "$TAILSCALE_IP" =~ ^100\. ]]; then
    echo ""
    echo "[ERROR] Tailscale no se ha conectado."
    echo "Puedes comprobarlo con:"
    echo "  sudo tailscale status"
    exit 1
fi

echo "[OK] Tailscale conectado."
echo "[OK] IP Tailscale: $TAILSCALE_IP"

# ------------------------------------------------------------
# 8. Crear entorno virtual
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "          Configurando Python"
echo "=============================================="

if [ ! -d "$PROJECT_DIR/venv" ]; then
    echo "[INFO] Creando entorno virtual..."
    python3 -m venv "$PROJECT_DIR/venv"
else
    echo "[OK] El entorno virtual ya existe."
fi

source "$PROJECT_DIR/venv/bin/activate"

echo "[INFO] Actualizando pip..."
python -m pip install --upgrade pip

echo "[INFO] Instalando dependencias..."
pip install -r "$PROJECT_DIR/requirements.txt"

echo "[OK] Dependencias instaladas."

# ------------------------------------------------------------
# 9. Configurar PIN
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "                PIN de PcRemote"
echo "=============================================="
echo ""
echo "El PIN predeterminado es: $DEFAULT_PIN"
echo ""

read -r -p "¿Quieres cambiar tu PIN? [y/N]: " CHANGE_PIN
CHANGE_PIN="${CHANGE_PIN,,}"

if [[ "$CHANGE_PIN" == "y" || "$CHANGE_PIN" == "yes" || "$CHANGE_PIN" == "s" || "$CHANGE_PIN" == "si" ]]; then

    while true; do
        echo ""
        read -r -s -p "Introduce un nuevo PIN de 6 dígitos: " NEW_PIN
        echo ""

        if [[ ! "$NEW_PIN" =~ ^[0-9]{6}$ ]]; then
            echo "[ERROR] El PIN debe tener exactamente 6 números."
            continue
        fi

        read -r -s -p "Confirma el nuevo PIN: " CONFIRM_PIN
        echo ""

        if [[ "$NEW_PIN" != "$CONFIRM_PIN" ]]; then
            echo "[ERROR] Los PIN no coinciden."
            continue
        fi

        break
    done

    PIN_TO_USE="$NEW_PIN"
else
    PIN_TO_USE="$DEFAULT_PIN"
fi

python3 - "$PIN_TO_USE" <<'PY'
from pathlib import Path
import re
import sys

new_pin = sys.argv[1]
path = Path("app.py")
text = path.read_text()

new_text, count = re.subn(
    r'(?m)^\s*PIN\s*=\s*["\'][^"\']*["\']\s*$',
    f'PIN = "{new_pin}"',
    text,
    count=1
)

if count == 0:
    print("[ERROR] No se ha encontrado la línea PIN = ... en app.py")
    sys.exit(1)

path.write_text(new_text)
print("[OK] PIN guardado directamente en app.py.")
PY

# ------------------------------------------------------------
# 10. Crear servicio systemd
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "            Configurando systemd"
echo "=============================================="

sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=PcRemote
After=network-online.target tailscaled.service
Wants=network-online.target
Requires=tailscaled.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

echo "[OK] Servicio systemd creado y habilitado."

# ------------------------------------------------------------
# 11. Configurar Firewall UFW
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "             Configurando Firewall"
echo "=============================================="

# PcRemote solamente por Tailscale.
sudo ufw allow in on tailscale0 to any port "$PORT" proto tcp

# Si SSH está activo, permitirlo únicamente por Tailscale
# para evitar bloquear una sesión SSH remota.
if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
    sudo ufw allow in on tailscale0 to any port 22 proto tcp
fi

sudo ufw --force enable

echo "[OK] Firewall configurado."
echo "[OK] Puerto $PORT permitido por tailscale0."

# ------------------------------------------------------------
# 12. Iniciar PcRemote
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "             Iniciando PcRemote"
echo "=============================================="

sudo systemctl restart "$SERVICE_NAME"

sleep 2

if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "[OK] PcRemote está funcionando."
else
    echo "[ERROR] PcRemote no ha podido iniciarse."
    echo ""
    sudo systemctl status "$SERVICE_NAME" --no-pager || true
    echo ""
    echo "Últimos registros:"
    sudo journalctl -u "$SERVICE_NAME" -n 50 --no-pager || true
    exit 1
fi

# ------------------------------------------------------------
# 13. Comprobación HTTP
# ------------------------------------------------------------
echo ""
echo "[INFO] Comprobando PcRemote..."

if curl -fsS --max-time 5 "http://127.0.0.1:$PORT/" >/dev/null; then
    echo "[OK] PcRemote responde correctamente."
else
    echo "[WARN] PcRemote está activo pero la comprobación HTTP ha fallado."
fi

# ------------------------------------------------------------
# 14. Resultado final
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "        INSTALACIÓN COMPLETADA"
echo "=============================================="
echo ""
echo "Tailscale:       CONECTADO"
echo "IP Tailscale:    $TAILSCALE_IP"
echo "PcRemote:        ACTIVO"
echo "Servicio:        HABILITADO"
echo "Firewall:        CONFIGURADO"
echo "Puerto:          $PORT"
echo ""
echo "Acceso desde el móvil:"
echo ""
echo "http://$TAILSCALE_IP:$PORT"
echo ""
echo "PIN configurado correctamente."
echo ""
echo "IMPORTANTE:"
echo "- Instala Tailscale también en el móvil."
echo "- Inicia sesión con la misma cuenta de Tailscale."
echo "- No utilices una cuenta @iesebre.cat."
echo "- El PIN inicial es 123456 si no lo has cambiado."
echo "- No necesitas Tailscale Funnel."
echo ""
echo "Para comprobar el servicio:"
echo "  sudo systemctl status pcremote"
echo ""
echo "Para ver los dispositivos Tailscale:"
echo "  tailscale status"
echo ""
echo "=============================================="
echo ""

deactivate 2>/dev/null || true
