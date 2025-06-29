#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                        ASTRA DEFENSE ENGINE v2.1
#         Advanced Stealth Threat Response Architecture
#                    Installation Complète et Fiable
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

# Configuration
REPO_URL="https://github.com/FIlox77250/Astra-cyber.git"
INSTALL_DIR="/opt/astra"
CONFIG_DIR="/etc/astra"
LOG_DIR="/var/log/astra"
BINARY_PATH="/usr/local/bin/astra"

# Fonctions utilitaires
print_banner() {
    clear
    echo -e "${PURPLE}"
    echo "    ░█████╗░░██████╗████████╗██████╗░░█████╗░"
    echo "    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗"
    echo "    ███████║╚█████╗░░░░██║░░░██████╔╝███████║"
    echo "    ██╔══██║░╚═══██╗░░░██║░░░██╔══██╗██╔══██║"
    echo "    ██║░░██║██████╔╝░░░██║░░░██║░░██║██║░░██║"
    echo "    ╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝"
    echo -e "${RESET}"
    echo -e "${CYAN}    Advanced Stealth Threat Response Architecture${RESET}"
    echo -e "${WHITE}    Installation Automatique - Garantie Fonctionnelle${RESET}"
    echo
}

print_step() {
    echo -e "${CYAN}[ÉTAPE]${RESET} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${RESET} $1"
}

print_error() {
    echo -e "${RED}[✗]${RESET} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${RESET} $1"
}

# Vérifications préalables
check_system() {
    print_step "Vérification du système..."
    
    # Root check
    if [ "$EUID" -ne 0 ]; then
        print_error "Privilèges root requis"
        echo "Exécutez: sudo bash $0"
        exit 1
    fi
    print_success "Privilèges root OK"
    
    # OS check
    if ! grep -qi 'debian\|ubuntu' /etc/os-release; then
        print_error "Système non supporté (Debian/Ubuntu requis)"
        exit 1
    fi
    
    OS_INFO=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    print_success "Système compatible: $OS_INFO"
    
    # Connexion internet
    if ping -c 1 google.com &>/dev/null; then
        print_success "Connexion internet OK"
    else
        print_warning "Connexion internet limitée"
    fi
    
    echo
}

# Installation des dépendances
install_dependencies() {
    print_step "Installation des dépendances système..."
    
    # Mise à jour
    echo "Mise à jour des paquets..."
    apt update &>/dev/null
    print_success "Cache mis à jour"
    
    # Paquets requis
    PACKAGES="curl wget git build-essential libpcap-dev pkg-config libssl-dev net-tools iptables"
    
    echo "Installation des paquets..."
    for package in $PACKAGES; do
        if ! dpkg -l | grep -q "^ii.*$package "; then
            echo "  → Installation de $package..."
            apt install -y "$package" &>/dev/null
        else
            echo "  → $package déjà installé"
        fi
    done
    
    print_success "Toutes les dépendances installées"
    echo
}

# Installation de Rust
install_rust() {
    print_step "Installation de Rust..."
    
    if command -v cargo &>/dev/null; then
        RUST_VERSION=$(rustc --version | awk '{print $2}')
        print_success "Rust déjà installé: v$RUST_VERSION"
    else
        echo "Téléchargement et installation de Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null
        print_success "Rust installé"
    fi
    
    # Charger l'environnement Rust
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Vérifier que Rust fonctionne
    if ! command -v cargo &>/dev/null; then
        print_error "Rust n'est pas accessible après installation"
        exit 1
    fi
    
    RUST_VERSION=$(rustc --version | awk '{print $2}')
    print_success "Rust opérationnel: v$RUST_VERSION"
    echo
}

# Téléchargement du code source
download_source() {
    print_step "Téléchargement du code source ASTRA..."
    
    # Créer et nettoyer le répertoire
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [ -d ".git" ]; then
        echo "Mise à jour du dépôt existant..."
        git fetch origin &>/dev/null
        git reset --hard origin/main &>/dev/null || git reset --hard origin/master &>/dev/null
    else
        echo "Suppression des anciens fichiers..."
        rm -rf ./* .git* &>/dev/null || true
        
        echo "Clonage du dépôt..."
        git clone "$REPO_URL" . &>/dev/null
    fi
    
    # Vérifier que les fichiers sont présents
    if [ ! -f "Cargo.toml" ]; then
        print_error "Fichiers source manquants"
        exit 1
    fi
    
    print_success "Code source téléchargé"
    echo
}

# Compilation d'ASTRA
compile_astra() {
    print_step "Compilation d'ASTRA..."
    
    cd "$INSTALL_DIR"
    
    # S'assurer que Rust est chargé
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Nettoyer les builds précédents
    echo "Nettoyage des builds précédents..."
    cargo clean &>/dev/null || true
    
    # Compilation
    echo "Compilation en cours (cela peut prendre plusieurs minutes)..."
    echo "Patientez..."
    
    # Compilation avec gestion d'erreur
    if ! RUST_BACKTRACE=1 cargo build --release &>/tmp/astra_build.log; then
        print_error "Échec de la compilation"
        echo "Logs de compilation:"
        tail -20 /tmp/astra_build.log
        exit 1
    fi
    
    # Vérifier que le binaire a été créé
    if [ ! -f "target/release/astra" ]; then
        print_error "Binaire ASTRA non généré"
        exit 1
    fi
    
    BINARY_SIZE=$(du -h target/release/astra | cut -f1)
    print_success "Compilation réussie (taille: $BINARY_SIZE)"
    echo
}

# Installation du binaire
install_binary() {
    print_step "Installation du binaire..."
    
    # Copier le binaire
    cp "$INSTALL_DIR/target/release/astra" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    
    # Vérifier l'installation
    if [ ! -f "$BINARY_PATH" ]; then
        print_error "Échec de la copie du binaire"
        exit 1
    fi
    
    # Test du binaire
    if ! "$BINARY_PATH" --help &>/dev/null; then
        print_error "Le binaire ASTRA ne fonctionne pas correctement"
        exit 1
    fi
    
    print_success "Binaire installé et fonctionnel: $BINARY_PATH"
    echo
}

# Configuration du système
setup_configuration() {
    print_step "Configuration du système..."
    
    # Créer les répertoires
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    # Configuration principale
    cat > "$CONFIG_DIR/config.json" << 'EOF'
{
  "system": {
    "stealth_mode": true,
    "max_memory_usage": 512,
    "max_cpu_usage": 80.0,
    "update_interval": 1,
    "auto_restart": true
  },
  "network": {
    "interfaces": ["eth0", "ens18", "ens33", "wlan0"],
    "monitor_all_interfaces": true,
    "promiscuous_mode": false,
    "capture_buffer_size": 8192,
    "packet_timeout": 100,
    "ipv6_support": false
  },
  "security": {
    "default_sensitivity": 6,
    "auto_block_enabled": true,
    "auto_block_threshold": 0.7,
    "honeypot_enabled": true,
    "counter_recon_enabled": true,
    "threat_intel_enabled": true,
    "whitelist_ips": [
      "127.0.0.1", "::1",
      "192.168.0.0/16",
      "10.0.0.0/8",
      "172.16.0.0/12"
    ],
    "blacklist_ips": []
  },
  "logging": {
    "log_level": "INFO",
    "log_file": "/var/log/astra/astra.log",
    "max_log_size": 100,
    "log_retention_days": 30,
    "syslog_enabled": true,
    "json_format": false,
    "audit_trail": true
  },
  "modules": {
    "tcp_guard": {
      "enabled": true,
      "sensitivity": 6,
      "scan_threshold": 3,
      "time_window": 10,
      "syn_flood_threshold": 10,
      "stealth_ports": [22, 23, 25, 53, 80, 110, 143, 443, 993, 995, 135, 139, 445, 1433, 3389, 21, 69, 161, 162, 514, 873, 5060, 5061],
      "honeypot_responses": true
    },
    "sip_shield": {
      "enabled": true,
      "sensitivity": 6,
      "monitored_ports": [5060, 5061],
      "attack_threshold": 10,
      "registration_monitoring": true,
      "invite_flood_threshold": 20,
      "brute_force_threshold": 5
    }
  },
  "firewall": {
    "enabled": true,
    "default_policy": "DROP",
    "custom_rules": [],
    "auto_rules": true,
    "backup_rules": true,
    "iptables_path": "/sbin/iptables"
  }
}
EOF
    
    chmod 600 "$CONFIG_DIR/config.json"
    chown root:root "$CONFIG_DIR/config.json"
    print_success "Configuration créée"
    
    # Service systemd
    cat > /etc/systemd/system/astra.service << EOF
[Unit]
Description=ASTRA Defense Engine - Advanced Stealth Threat Response Architecture
Documentation=https://github.com/FIlox77250/Astra-cyber
After=network.target iptables.service
Wants=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$BINARY_PATH
ExecReload=/bin/kill -HUP \$MAINPID
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30
KillMode=process
WorkingDirectory=$INSTALL_DIR

# Environment
Environment=RUST_LOG=info
Environment=ASTRA_CONFIG=$CONFIG_DIR/config.json

# Logging
StandardOutput=append:$LOG_DIR/astra.log
StandardError=append:$LOG_DIR/error.log

# Security
NoNewPrivileges=false
ProtectSystem=false
ProtectHome=false

# Capabilities pour les opérations réseau
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_ADMIN
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE

# Limites de ressources
LimitNOFILE=65536
MemoryMax=1G

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Service systemd configuré"
    
    # Rotation des logs
    cat > /etc/logrotate.d/astra << 'EOF'
/var/log/astra/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload astra || true
    endscript
}
EOF
    
    print_success "Rotation des logs configurée"
    echo
}

# Démarrage du service
start_service() {
    print_step "Démarrage du service ASTRA..."
    
    # Recharger systemd
    systemctl daemon-reload
    
    # Activer le service
    systemctl enable astra &>/dev/null
    print_success "Service activé au démarrage"
    
    # Démarrer le service
    if systemctl start astra; then
        print_success "Service démarré"
    else
        print_error "Échec du démarrage du service"
        echo "Logs d'erreur:"
        journalctl -u astra --no-pager -l -n 10
        exit 1
    fi
    
    # Attendre et vérifier
    sleep 3
    
    if systemctl is-active --quiet astra; then
        print_success "ASTRA fonctionne correctement"
    else
        print_warning "Le service a des difficultés"
        echo "Statut du service:"
        systemctl status astra --no-pager -l
    fi
    
    echo
}

# Tests post-installation
run_tests() {
    print_step "Tests post-installation..."
    
    # Test du binaire
    if "$BINARY_PATH" --help &>/dev/null; then
        print_success "Binaire fonctionnel"
    else
        print_error "Problème avec le binaire"
    fi
    
    # Test de la configuration
    if [ -f "$CONFIG_DIR/config.json" ]; then
        print_success "Configuration présente"
    else
        print_error "Configuration manquante"
    fi
    
    # Test du service
    if systemctl is-enabled --quiet astra; then
        print_success "Service activé"
    else
        print_error "Service non activé"
    fi
    
    # Test des logs
    if [ -d "$LOG_DIR" ]; then
        print_success "Répertoire de logs créé"
    else
        print_error "Problème avec les logs"
    fi
    
    echo
}

# Affichage final
show_summary() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}                    🛡️  INSTALLATION TERMINÉE 🛡️                    ${RESET}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${RESET}"
    echo
    echo -e "${CYAN}📍 Informations système:${RESET}"
    echo "   • Binaire: $BINARY_PATH"
    echo "   • Configuration: $CONFIG_DIR/config.json"
    echo "   • Logs: $LOG_DIR/"
    echo "   • Service: astra.service"
    echo
    echo -e "${CYAN}🔧 Commandes utiles:${RESET}"
    echo "   • Statut:      systemctl status astra"
    echo "   • Redémarrer:  systemctl restart astra"
    echo "   • Logs:        tail -f $LOG_DIR/astra.log"
    echo "   • Config:      nano $CONFIG_DIR/config.json"
    echo
    echo -e "${CYAN}🛡️ Modules activés:${RESET}"
    echo "   • TCP Guardian (protection scans)"
    echo "   • SIP Shield (protection VoIP)"
    echo "   • Firewall intelligent"
    echo "   • Mode furtif"
    echo "   • Honeypots"
    echo
    
    # Statut final
    if systemctl is-active --quiet astra; then
        echo -e "${GREEN}✅ ASTRA Defense Engine est OPÉRATIONNEL !${RESET}"
    else
        echo -e "${YELLOW}⚠️  ASTRA installé mais nécessite une vérification${RESET}"
        echo "   Vérifiez avec: systemctl status astra"
    fi
    
    echo
    echo -e "${WHITE}Installation terminée le $(date '+%Y-%m-%d à %H:%M:%S')${RESET}"
    echo
}

# ═══════════════════════════════════════════════════════════════════════════════
#                                MAIN FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    # Gestion des interruptions
    trap 'echo -e "\n${RED}Installation interrompue${RESET}"; exit 1' INT TERM
    
    print_banner
    check_system
    install_dependencies
    install_rust
    download_source
    compile_astra
    install_binary
    setup_configuration
    start_service
    run_tests
    show_summary
}

# Lancement du script
main "$@"
