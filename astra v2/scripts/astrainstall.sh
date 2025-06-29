#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                        ASTRA DEFENSE ENGINE
#         Advanced Stealth Threat Response Architecture
#                    Installation Automatique
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                              CONFIGURATION                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

# Couleurs avancées
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# Symboles Unicode
readonly CHECKMARK="✓"
readonly CROSS="✗"
readonly ARROW="→"
readonly STAR="★"
readonly SHIELD="🛡️"
readonly ROCKET="🚀"
readonly GEAR="⚙️"
readonly PACKAGE="📦"
readonly WARNING="⚠️"
readonly SUCCESS="🎉"

# Configuration
readonly REPO_URL="https://github.com/FIlox77250/Astra-cyber.git"
readonly INSTALL_DIR="/opt/astra"
readonly CONFIG_DIR="/etc/astra"
readonly LOG_DIR="/var/log/astra"
readonly BINARY_PATH="/usr/local/bin/astra"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           FONCTIONS UTILITAIRES                            │
# └─────────────────────────────────────────────────────────────────────────────┘

# Animation de chargement
loading_animation() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "${CYAN}[%c]${RESET}" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    printf "   \b\b\b"
}

# Messages stylisés
print_header() {
    echo -e "\n${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${PURPLE}║${RESET}${BOLD}${WHITE}                              $1                              ${RESET}${PURPLE}║${RESET}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}\n"
}

print_step() {
    echo -e "${CYAN}${BOLD}${ARROW} $1${RESET}"
}

print_success() {
    echo -e "${GREEN}${BOLD}  ${CHECKMARK} $1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}${BOLD}  ${WARNING} $1${RESET}"
}

print_error() {
    echo -e "${RED}${BOLD}  ${CROSS} $1${RESET}"
}

print_info() {
    echo -e "${BLUE}${BOLD}  ${STAR} $1${RESET}"
}

# Progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}["
    printf "%*s" "$filled" | tr ' ' '█'
    printf "%*s" "$empty" | tr ' ' '░'
    printf "] %d%% (%d/%d)${RESET}" "$percentage" "$current" "$total"
}

# Bannière ASCII avec animation
show_banner() {
    clear
    echo -e "${PURPLE}${BOLD}"
    sleep 0.1
    echo "    ░█████╗░░██████╗████████╗██████╗░░█████╗░"
    sleep 0.1
    echo "    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗"
    sleep 0.1
    echo "    ███████║╚█████╗░░░░██║░░░██████╔╝███████║"
    sleep 0.1
    echo "    ██╔══██║░╚═══██╗░░░██║░░░██╔══██╗██╔══██║"
    sleep 0.1
    echo "    ██║░░██║██████╔╝░░░██║░░░██║░░██║██║░░██║"
    sleep 0.1
    echo "    ╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝"
    echo -e "${RESET}"
    sleep 0.2
    
    echo -e "${CYAN}${BOLD}    ┌─────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}${BOLD}    │${RESET} ${WHITE}${BOLD}Advanced Stealth Threat Response Architecture${RESET} ${CYAN}${BOLD}│${RESET}"
    echo -e "${CYAN}${BOLD}    │${RESET} ${GRAY}           Installation Automatique v2.1           ${RESET} ${CYAN}${BOLD}│${RESET}"
    echo -e "${CYAN}${BOLD}    │${RESET} ${GRAY}              Powered by BRCloud.fr              ${RESET} ${CYAN}${BOLD}│${RESET}"
    echo -e "${CYAN}${BOLD}    └─────────────────────────────────────────────────────────┘${RESET}"
    echo
    sleep 0.3
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                          FONCTIONS PRINCIPALES                             │
# └─────────────────────────────────────────────────────────────────────────────┘

check_requirements() {
    print_header "VÉRIFICATION DU SYSTÈME"
    
    local checks=0
    local total_checks=4
    
    # Vérification root
    progress_bar $((++checks)) $total_checks
    if [ "$EUID" -ne 0 ]; then
        echo
        print_error "Privilèges root requis"
        echo -e "${YELLOW}${BOLD}   Exécutez: ${WHITE}sudo bash $0${RESET}"
        exit 1
    fi
    print_success "Privilèges root détectés"
    
    # Vérification OS
    progress_bar $((++checks)) $total_checks
    if ! grep -qi 'debian\|ubuntu' /etc/os-release; then
        echo
        print_error "Système non supporté"
        print_info "Debian/Ubuntu requis"
        exit 1
    fi
    local os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    print_success "Système compatible: $os_name"
    
    # Vérification connexion
    progress_bar $((++checks)) $total_checks
    if ! ping -c 1 google.com &> /dev/null; then
        echo
        print_warning "Connexion internet limitée"
    else
        print_success "Connexion internet OK"
    fi
    
    # Vérification espace disque
    progress_bar $((++checks)) $total_checks
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 2097152 ]; then  # 2GB en KB
        echo
        print_warning "Espace disque faible (< 2GB disponible)"
    else
        print_success "Espace disque suffisant"
    fi
    
    echo
    sleep 1
}

install_dependencies() {
    print_header "INSTALLATION DES DÉPENDANCES"
    
    local packages=(
        "curl:Client HTTP"
        "wget:Téléchargeur"
        "git:Contrôle de version"
        "build-essential:Outils de compilation"
        "libpcap-dev:Bibliothèque réseau"
        "pkg-config:Configuration packages"
        "libssl-dev:Bibliothèque SSL"
        "net-tools:Outils réseau"
        "iptables:Pare-feu"
    )
    
    print_step "Mise à jour des paquets..."
    apt update &> /dev/null &
    loading_animation $!
    print_success "Cache des paquets mis à jour"
    
    local installed=0
    local total=${#packages[@]}
    
    for package_info in "${packages[@]}"; do
        local package=$(echo "$package_info" | cut -d':' -f1)
        local description=$(echo "$package_info" | cut -d':' -f2)
        
        progress_bar $((++installed)) $total
        
        if ! dpkg -l | grep -q "^ii.*$package"; then
            apt install -y "$package" &> /dev/null
            print_success "$description installé"
        else
            print_info "$description déjà présent"
        fi
    done
    
    echo
    sleep 1
}

install_rust() {
    print_header "INSTALLATION DE RUST"
    
    if command -v cargo &> /dev/null; then
        local rust_version=$(rustc --version | awk '{print $2}')
        print_success "Rust déjà installé: v$rust_version"
        return
    fi
    
    print_step "Téléchargement et installation de Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &> /dev/null &
    loading_animation $!
    
    source "$HOME/.cargo/env"
    export PATH="$HOME/.cargo/bin:$PATH"
    
    if command -v cargo &> /dev/null; then
        local rust_version=$(rustc --version | awk '{print $2}')
        print_success "Rust installé avec succès: v$rust_version"
    else
        print_error "Échec de l'installation de Rust"
        exit 1
    fi
    
    sleep 1
}

download_astra() {
    print_header "TÉLÉCHARGEMENT D'ASTRA"
    
    print_step "Préparation du répertoire d'installation..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [ -d ".git" ]; then
        print_step "Mise à jour du dépôt existant..."
        git pull origin main &> /dev/null &
    else
        print_step "Clonage du dépôt ASTRA..."
        rm -rf ./* &> /dev/null || true
        git clone "$REPO_URL" . &> /dev/null &
    fi
    
    loading_animation $!
    print_success "Code source ASTRA récupéré"
    
    # Afficher les informations du commit
    local commit_hash=$(git rev-parse --short HEAD)
    local commit_date=$(git log -1 --format=%cd --date=short)
    print_info "Version: $commit_hash ($commit_date)"
    
    sleep 1
}

compile_astra() {
    print_header "COMPILATION D'ASTRA"
    
    cd "$INSTALL_DIR"
    
    # S'assurer que Rust est disponible
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    print_step "Nettoyage des builds précédents..."
    cargo clean &> /dev/null
    
    print_step "Compilation en mode optimisé..."
    echo -e "${GRAY}   Cela peut prendre quelques minutes...${RESET}"
    
    # Compilation avec indicateur de progression
    RUST_BACKTRACE=1 cargo build --release &> /tmp/astra_build.log &
    local build_pid=$!
    
    # Animation pendant la compilation
    local dots=0
    while kill -0 $build_pid 2> /dev/null; do
        printf "\r${CYAN}   Compilation en cours"
        for ((i=0; i<=dots; i++)); do printf "."; done
        printf "   ${RESET}"
        dots=$(((dots + 1) % 4))
        sleep 1
    done
    
    wait $build_pid
    local build_result=$?
    
    echo
    if [ $build_result -eq 0 ] && [ -f "target/release/astra" ]; then
        local binary_size=$(du -h target/release/astra | cut -f1)
        print_success "Compilation réussie (taille: $binary_size)"
    else
        print_error "Échec de la compilation"
        echo -e "${GRAY}Logs de compilation:${RESET}"
        tail -10 /tmp/astra_build.log
        exit 1
    fi
    
    sleep 1
}

install_binary() {
    print_header "INSTALLATION DU BINAIRE"
    
    print_step "Déploiement du binaire..."
    cp "$INSTALL_DIR/target/release/astra" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    
    if [ -f "$BINARY_PATH" ]; then
        print_success "Binaire installé: $BINARY_PATH"
    else
        print_error "Échec du déploiement"
        exit 1
    fi
    
    sleep 1
}

create_configuration() {
    print_header "CONFIGURATION DU SYSTÈME"
    
    print_step "Création des répertoires..."
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    print_step "Génération de la configuration..."
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
    
    print_step "Configuration du service systemd..."
    cat > /etc/systemd/system/astra.service << 'EOF'
[Unit]
Description=ASTRA Defense Engine - Advanced Stealth Threat Response Architecture
Documentation=https://github.com/FIlox77250/Astra-cyber
After=network.target iptables.service
Wants=network.target
Requires=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/local/bin/astra
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -TERM $MAINPID
Restart=on-failure
RestartSec=5
TimeoutStartSec=30
TimeoutStopSec=30
KillMode=process
KillSignal=SIGTERM
WorkingDirectory=/opt/astra

# Environment
Environment=RUST_LOG=info
Environment=ASTRA_CONFIG=/etc/astra/config.json

# Logging
StandardOutput=append:/var/log/astra/astra.log
StandardError=append:/var/log/astra/error.log

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/astra /etc/astra /tmp
PrivateTmp=yes
PrivateDevices=false

# Capabilities
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE

# Resource limits
LimitNOFILE=65536
MemoryMax=1G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Service systemd configuré"
    
    print_step "Configuration de la rotation des logs..."
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
    sleep 1
}

start_service() {
    print_header "DÉMARRAGE DU SERVICE"
    
    print_step "Rechargement de systemd..."
    systemctl daemon-reload
    
    print_step "Activation du service au démarrage..."
    systemctl enable astra
    
    print_step "Démarrage d'ASTRA..."
    systemctl start astra
    
    # Attendre un peu pour le démarrage
    sleep 3
    
    if systemctl is-active --quiet astra; then
        print_success "ASTRA démarré avec succès"
    else
        print_warning "Problème de démarrage détecté"
        echo -e "${GRAY}Vérification des logs...${RESET}"
        journalctl -u astra --no-pager -l -n 5
    fi
    
    sleep 1
}

show_final_report() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo "    ╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "    ║                                                                              ║"
    echo "    ║                    🎉 INSTALLATION TERMINÉE AVEC SUCCÈS 🎉                  ║"
    echo "    ║                                                                              ║"
    echo "    ╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}\n"
    
    echo -e "${CYAN}${BOLD}📊 RÉSUMÉ DE L'INSTALLATION${RESET}"
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECKMARK}${RESET} Binaire ASTRA     : ${WHITE}$BINARY_PATH${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECKMARK}${RESET} Configuration     : ${WHITE}$CONFIG_DIR/config.json${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECKMARK}${RESET} Logs             : ${WHITE}$LOG_DIR/${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECKMARK}${RESET} Service systemd   : ${WHITE}astra.service${RESET}"
    
    if systemctl is-active --quiet astra; then
        echo -e "${CYAN}│${RESET} ${GREEN}${CHECKMARK}${RESET} Statut           : ${GREEN}${BOLD}ACTIF${RESET}"
    else
        echo -e "${CYAN}│${RESET} ${RED}${CROSS}${RESET} Statut           : ${RED}${BOLD}INACTIF${RESET}"
    fi
    
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    echo -e "${PURPLE}${BOLD}🔧 COMMANDES UTILES${RESET}"
    echo -e "${PURPLE}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Statut du service${RESET}     : ${WHITE}systemctl status astra${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Redémarrer ASTRA${RESET}      : ${WHITE}systemctl restart astra${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Arrêter ASTRA${RESET}         : ${WHITE}systemctl stop astra${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Logs en temps réel${RESET}    : ${WHITE}journalctl -u astra -f${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Fichier de logs${RESET}       : ${WHITE}tail -f $LOG_DIR/astra.log${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Éditer la config${RESET}      : ${WHITE}nano $CONFIG_DIR/config.json${RESET}"
    echo -e "${PURPLE}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    echo -e "${BLUE}${BOLD}🛡️ MODULES DE SÉCURITÉ ACTIVÉS${RESET}"
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}TCP Guardian${RESET}      : Protection contre les scans de ports"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}SIP Shield${RESET}        : Protection VoIP/SIP avancée"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Firewall Intel${RESET}    : Pare-feu intelligent adaptatif"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Mode Furtif${RESET}       : Invisibilité totale aux scans"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Honeypots${RESET}         : Pièges pour les attaquants"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Threat Intel${RESET}      : Intelligence artificielle des menaces"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    echo -e "${RED}${BOLD}⚠️ AVERTISSEMENT DE SÉCURITÉ${RESET}"
    echo -e "${RED}ASTRA fonctionne avec les privilèges root pour la capture réseau${RESET}"
    echo -e "${RED}Assurez-vous de sécuriser l'accès à votre serveur${RESET}\n"
    
    echo -e "${WHITE}${BOLD}${SUCCESS} ASTRA Defense Engine est maintenant opérationnel !${RESET}"
    echo -e "${GRAY}Installation terminée à $(date '+%Y-%m-%d %H:%M:%S')${RESET}\n"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                              MAIN FUNCTION                                 │
# └─────────────────────────────────────────────────────────────────────────────┘

main() {
    # Trap pour nettoyer en cas d'interruption
    trap 'echo -e "\n${RED}Installation interrompue.${RESET}"; exit 1' INT TERM
    
    show_banner
    check_requirements
    install_dependencies
    install_rust
    download_astra
    compile_astra
    install_binary
    create_configuration
    start_service
    show_final_report
}

# Lancement du script
main "$@"
