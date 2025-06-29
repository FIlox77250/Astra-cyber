# Créer un script d'installation propre
cat > install-astra-clean.sh << 'EOF'
#!/bin/bash
set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${PURPLE}"
echo "    ░█████╗░░██████╗████████╗██████╗░░█████╗░"
echo "    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗"
echo "    ███████║╚█████╗░░░░██║░░░██████╔╝███████║"
echo "    ██╔══██║░╚═══██╗░░░██║░░░██╔══██╗██╔══██║"
echo "    ██║░░██║██████╔╝░░░██║░░░██║░░██║██║░░██║"
echo "    ╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝"
echo -e "${RESET}"
echo -e "${CYAN}    ASTRA Defense Engine - Installation v2.1${RESET}"
echo

# Vérifications
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Privilèges root requis${RESET}"
    exit 1
fi

if ! grep -qi 'debian\|ubuntu' /etc/os-release; then
    echo -e "${RED}❌ Debian/Ubuntu requis${RESET}"
    exit 1
fi

OS_INFO=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
echo -e "${GREEN}✓ Système compatible: $OS_INFO${RESET}"

# Installation des dépendances
echo -e "${BLUE}📦 Installation des dépendances...${RESET}"
apt update >/dev/null 2>&1
apt install -y curl wget git build-essential libpcap-dev pkg-config libssl-dev net-tools iptables >/dev/null 2>&1
echo -e "${GREEN}✓ Dépendances installées${RESET}"

# Installation Rust
echo -e "${BLUE}🦀 Installation de Rust...${RESET}"
if ! command -v cargo >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >/dev/null 2>&1
fi
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
echo -e "${GREEN}✓ Rust installé: $(rustc --version | awk '{print $2}')${RESET}"

# Téléchargement ASTRA
echo -e "${BLUE}📁 Téléchargement d'ASTRA...${RESET}"
mkdir -p /opt/astra
cd /opt/astra
rm -rf ./* 2>/dev/null || true
git clone https://github.com/FIlox77250/Astra-cyber.git . >/dev/null 2>&1
echo -e "${GREEN}✓ Code source téléchargé${RESET}"

# Compilation
echo -e "${BLUE}⚙️ Compilation d'ASTRA (patientez 3-5 minutes)...${RESET}"
source "$HOME/.cargo/env"
export PATH="$HOME/.cargo/bin:$PATH"
cargo clean >/dev/null 2>&1

echo "Compilation en cours..."
if cargo build --release >/tmp/astra_build.log 2>&1; then
    echo -e "${GREEN}✓ Compilation réussie${RESET}"
else
    echo -e "${RED}❌ Échec de compilation${RESET}"
    echo "Dernières lignes du log:"
    tail -10 /tmp/astra_build.log
    exit 1
fi

# Installation binaire
echo -e "${BLUE}📦 Installation du binaire...${RESET}"
if [ -f "target/release/astra" ]; then
    cp target/release/astra /usr/local/bin/astra
    chmod +x /usr/local/bin/astra
    echo -e "${GREEN}✓ Binaire installé${RESET}"
else
    echo -e "${RED}❌ Binaire non généré${RESET}"
    exit 1
fi

# Test du binaire
echo -e "${BLUE}🔍 Test du binaire...${RESET}"
if /usr/local/bin/astra --help >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Binaire fonctionnel${RESET}"
else
    echo -e "${RED}❌ Problème avec le binaire${RESET}"
    exit 1
fi

# Configuration
echo -e "${BLUE}🔧 Configuration du système...${RESET}"
mkdir -p /etc/astra /var/log/astra

cat > /etc/astra/config.json << 'CONFIG_END'
{
  "system": {
    "stealth_mode": true,
    "max_memory_usage": 512,
    "max_cpu_usage": 80.0
  },
  "security": {
    "default_sensitivity": 6,
    "auto_block_enabled": true,
    "honeypot_enabled": true
  },
  "logging": {
    "log_level": "INFO",
    "log_file": "/var/log/astra/astra.log"
  },
  "modules": {
    "tcp_guard": {
      "enabled": true,
      "sensitivity": 6
    },
    "sip_shield": {
      "enabled": true,
      "sensitivity": 6
    }
  }
}
CONFIG_END

# Service systemd
cat > /etc/systemd/system/astra.service << 'SERVICE_END'
[Unit]
Description=ASTRA Defense Engine
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/astra
WorkingDirectory=/opt/astra
Restart=always
RestartSec=5
User=root
Group=root
StandardOutput=append:/var/log/astra/astra.log
StandardError=append:/var/log/astra/error.log
Environment=ASTRA_CONFIG=/etc/astra/config.json
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SERVICE_END

echo -e "${GREEN}✓ Configuration créée${RESET}"

# Démarrage du service
echo -e "${BLUE}🚀 Démarrage du service...${RESET}"
systemctl daemon-reload
systemctl enable astra >/dev/null 2>&1
systemctl start astra

# Vérification finale
sleep 3
if systemctl is-active --quiet astra; then
    echo -e "${GREEN}✅ ASTRA installé et opérationnel !${RESET}"
    STATUS="ACTIF"
else
    echo -e "${YELLOW}⚠️ Service créé mais vérification nécessaire${RESET}"
    STATUS="VÉRIFICATION REQUISE"
fi

echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}                    ${GREEN}INSTALLATION TERMINÉE${RESET}                    ${CYAN}║${RESET}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║${RESET} Statut du service : $STATUS"
echo -e "${CYAN}║${RESET} Binaire          : /usr/local/bin/astra"
echo -e "${CYAN}║${RESET} Configuration    : /etc/astra/config.json"
echo -e "${CYAN}║${RESET} Logs             : /var/log/astra/"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${RESET}"
echo -e "${CYAN}║${RESET} ${YELLOW}Commandes utiles:${RESET}"
echo -e "${CYAN}║${RESET}  • systemctl status astra"
echo -e "${CYAN}║${RESET}  • tail -f /var/log/astra/astra.log"
echo -e "${CYAN}║${RESET}  • systemctl restart astra"
echo -e "${CYAN}║${RESET}  • nano /etc/astra/config.json"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
echo

systemctl status astra --no-pager -l
EOF

# Exécuter le script
chmod +x install-astra-clean.sh
./install-astra-clean.sh
