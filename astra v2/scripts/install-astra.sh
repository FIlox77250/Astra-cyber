#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
#                        ASTRA DEFENSE ENGINE v3.1
#         Advanced Stealth Threat Response Architecture
#                    Installation Automatique - GitHub Release
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Configuration
readonly SCRIPT_VERSION="2.1.0"
readonly REPO_URL="https://github.com/FIlox77250/Astra-cyber.git"
readonly INSTALL_DIR="/opt/astra"
readonly CONFIG_DIR="/etc/astra"
readonly LOG_DIR="/var/log/astra"
readonly BINARY_PATH="/usr/local/bin/astra"

# Couleurs et style
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

# Symboles
readonly CHECK="✓"
readonly CROSS="✗"
readonly ARROW="→"
readonly STAR="★"
readonly SHIELD="🛡️"
readonly ROCKET="🚀"
readonly GEAR="⚙️"
readonly PACKAGE="📦"
readonly WARNING="⚠️"
readonly SUCCESS="🎉"

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           FONCTIONS UTILITAIRES                            │
# └─────────────────────────────────────────────────────────────────────────────┘

show_banner() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "    ░█████╗░░██████╗████████╗██████╗░░█████╗░"
    echo "    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗"
    echo "    ███████║╚█████╗░░░░██║░░░██████╔╝███████║"
    echo "    ██╔══██║░╚═══██╗░░░██║░░░██╔══██╗██╔══██║"
    echo "    ██║░░██║██████╔╝░░░██║░░░██║░░██║██║░░██║"
    echo "    ╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝"
    echo -e "${RESET}"
    
    echo -e "${CYAN}${BOLD}    ┌─────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}${BOLD}    │${RESET} ${WHITE}${BOLD}Advanced Stealth Threat Response Architecture${RESET} ${CYAN}${BOLD}│${RESET}"
    echo -e "${CYAN}${BOLD}    │${RESET} ${GRAY}           Installation Automatique v${SCRIPT_VERSION}           ${RESET} ${CYAN}${BOLD}│${RESET}"
    echo -e "${CYAN}${BOLD}    │${RESET} ${GRAY}              Powered by BRCloud.fr              ${RESET} ${CYAN}${BOLD}│${RESET}"
    echo -e "${CYAN}${BOLD}    └─────────────────────────────────────────────────────────┘${RESET}"
    echo
}

print_step() {
    echo -e "${CYAN}${BOLD}${ARROW} $1${RESET}"
}

print_success() {
    echo -e "${GREEN}${BOLD}  ${CHECK} $1${RESET}"
}

print_error() {
    echo -e "${RED}${BOLD}  ${CROSS} $1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}${BOLD}  ${WARNING} $1${RESET}"
}

print_info() {
    echo -e "${BLUE}${BOLD}  ${STAR} $1${RESET}"
}

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /tmp/astra_install.log
}

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

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                          VÉRIFICATIONS SYSTÈME                             │
# └─────────────────────────────────────────────────────────────────────────────┘

check_system() {
    echo -e "${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${PURPLE}${BOLD}║${RESET}${WHITE}${BOLD}                          VÉRIFICATION DU SYSTÈME                          ${RESET}${PURPLE}${BOLD}║${RESET}"
    echo -e "${PURPLE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    local checks=0
    local total_checks=5
    
    # Vérification root
    progress_bar $((++checks)) $total_checks
    if [ "$EUID" -ne 0 ]; then
        echo
        print_error "Privilèges root requis"
        echo -e "${YELLOW}${BOLD}   Exécutez: ${WHITE}curl -sSL https://raw.githubusercontent.com/FIlox77250/Astra-cyber/main/install-astra.sh | sudo bash${RESET}"
        exit 1
    fi
    print_success "Privilèges root détectés"
    log_message "Root privileges confirmed"
    
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
    log_message "OS compatibility confirmed: $os_name"
    
    # Vérification connexion internet
    progress_bar $((++checks)) $total_checks
    if ! ping -c 1 google.com &> /dev/null; then
        echo
        print_warning "Connexion internet limitée"
        log_message "Internet connection limited"
    else
        print_success "Connexion internet OK"
        log_message "Internet connection confirmed"
    fi
    
    # Vérification espace disque
    progress_bar $((++checks)) $total_checks
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 2097152 ]; then  # 2GB en KB
        echo
        print_warning "Espace disque faible (< 2GB disponible)"
        log_message "Low disk space warning"
    else
        print_success "Espace disque suffisant"
        log_message "Disk space sufficient"
    fi
    
    # Vérification ports
    progress_bar $((++checks)) $total_checks
    local port_conflicts=0
    for port in 5060 5061; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            ((port_conflicts++))
        fi
    done
    
    if [ $port_conflicts -gt 0 ]; then
        print_warning "$port_conflicts port(s) SIP déjà en utilisation"
        log_message "Port conflicts detected: $port_conflicts"
    else
        print_success "Ports SIP disponibles"
        log_message "SIP ports available"
    fi
    
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                       INSTALLATION DES DÉPENDANCES                         │
# └─────────────────────────────────────────────────────────────────────────────┘

install_dependencies() {
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}${BOLD}║${RESET}${WHITE}${BOLD}                      INSTALLATION DES DÉPENDANCES                       ${RESET}${BLUE}${BOLD}║${RESET}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    local packages=(
        "curl:Client HTTP avancé"
        "wget:Téléchargeur de fichiers"
        "git:Système de contrôle de version"
        "build-essential:Outils de compilation"
        "libpcap-dev:Bibliothèque de capture réseau"
        "pkg-config:Gestionnaire de configuration"
        "libssl-dev:Bibliothèque SSL/TLS"
        "net-tools:Outils réseau système"
        "iptables:Pare-feu Linux"
    )
    
    print_step "Mise à jour du cache des paquets..."
    if apt update &> /dev/null; then
        print_success "Cache des paquets mis à jour"
        log_message "Package cache updated successfully"
    else
        print_warning "Problème lors de la mise à jour du cache"
        log_message "Package cache update failed"
    fi
    
    local installed=0
    local total=${#packages[@]}
    
    echo
    print_step "Installation des paquets requis..."
    
    for package_info in "${packages[@]}"; do
        local package=$(echo "$package_info" | cut -d':' -f1)
        local description=$(echo "$package_info" | cut -d':' -f2)
        
        progress_bar $((++installed)) $total
        
        if ! dpkg -l | grep -q "^ii.*$package "; then
            if apt install -y "$package" &> /dev/null; then
                print_success "$description installé"
                log_message "Package installed: $package"
            else
                print_error "Échec d'installation: $package"
                log_message "Package installation failed: $package"
                exit 1
            fi
        else
            print_info "$description déjà présent"
            log_message "Package already installed: $package"
        fi
    done
    
    echo
    print_success "Toutes les dépendances sont installées"
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            INSTALLATION DE RUST                            │
# └─────────────────────────────────────────────────────────────────────────────┘

install_rust() {
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║${RESET}${WHITE}${BOLD}                           INSTALLATION DE RUST                           ${RESET}${YELLOW}${BOLD}║${RESET}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    if command -v cargo &> /dev/null; then
        local rust_version=$(rustc --version | awk '{print $2}')
        print_success "Rust déjà installé: v$rust_version"
        log_message "Rust already installed: v$rust_version"
    else
        print_step "Téléchargement et installation de Rust..."
        
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &> /dev/null; then
            print_success "Rust installé avec succès"
            log_message "Rust installation successful"
        else
            print_error "Échec de l'installation de Rust"
            log_message "Rust installation failed"
            exit 1
        fi
    fi
    
    # Charger l'environnement Rust
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Vérifier que Rust fonctionne
    if command -v cargo &> /dev/null; then
        local rust_version=$(rustc --version | awk '{print $2}')
        print_success "Rust opérationnel: v$rust_version"
        log_message "Rust operational: v$rust_version"
    else
        print_error "Rust n'est pas accessible après installation"
        log_message "Rust not accessible after installation"
        exit 1
    fi
    
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        TÉLÉCHARGEMENT DU CODE SOURCE                       │
# └─────────────────────────────────────────────────────────────────────────────┘

download_source() {
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║${RESET}${WHITE}${BOLD}                      TÉLÉCHARGEMENT DU CODE SOURCE                       ${RESET}${GREEN}${BOLD}║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    print_step "Préparation du répertoire d'installation..."
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [ -d ".git" ]; then
        print_step "Mise à jour du dépôt existant..."
        if git fetch origin &> /dev/null && (git reset --hard origin/main &> /dev/null || git reset --hard origin/master &> /dev/null); then
            print_success "Dépôt mis à jour"
            log_message "Repository updated successfully"
        else
            print_warning "Échec de la mise à jour, clonage complet..."
            rm -rf ./* .git* &> /dev/null || true
            if git clone "$REPO_URL" . &> /dev/null; then
                print_success "Dépôt cloné"
                log_message "Repository cloned successfully"
            else
                print_error "Échec du clonage"
                log_message "Repository cloning failed"
                exit 1
            fi
        fi
    else
        print_step "Clonage du dépôt ASTRA..."
        rm -rf ./* &> /dev/null || true
        
        if git clone "$REPO_URL" . &> /dev/null; then
            print_success "Dépôt cloné avec succès"
            log_message "Repository cloned successfully"
        else
            print_error "Échec du clonage du dépôt"
            log_message "Repository cloning failed"
            exit 1
        fi
    fi
    
    # Vérifier que les fichiers essentiels sont présents
    if [ ! -f "Cargo.toml" ]; then
        print_error "Fichiers source manquants (Cargo.toml)"
        log_message "Source files missing (Cargo.toml)"
        exit 1
    fi
    
    # Afficher les informations du commit
    if command -v git &> /dev/null && [ -d ".git" ]; then
        local commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local commit_date=$(git log -1 --format=%cd --date=short 2>/dev/null || echo "unknown")
        print_info "Version: $commit_hash ($commit_date)"
        log_message "Source version: $commit_hash ($commit_date)"
    fi
    
    print_success "Code source prêt pour la compilation"
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           COMPILATION D'ASTRA                              │
# └─────────────────────────────────────────────────────────────────────────────┘

compile_astra() {
    echo -e "${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${PURPLE}${BOLD}║${RESET}${WHITE}${BOLD}                           COMPILATION D'ASTRA                           ${RESET}${PURPLE}${BOLD}║${RESET}"
    echo -e "${PURPLE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    cd "$INSTALL_DIR"
    
    # S'assurer que Rust est disponible
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    print_step "Nettoyage des builds précédents..."
    if cargo clean &> /dev/null; then
        print_success "Builds précédents nettoyés"
        log_message "Previous builds cleaned"
    fi
    
    print_step "Compilation en mode optimisé..."
    echo -e "${GRAY}   ${STAR} Cela peut prendre plusieurs minutes selon votre système...${RESET}"
    
    # Compilation avec gestion d'erreur détaillée
    local build_log="/tmp/astra_build_$(date +%s).log"
    
    if RUST_BACKTRACE=1 cargo build --release > "$build_log" 2>&1; then
        if [ -f "target/release/astra" ]; then
            local binary_size=$(du -h target/release/astra | cut -f1)
            print_success "Compilation réussie (taille: $binary_size)"
            log_message "Compilation successful, binary size: $binary_size"
        else
            print_error "Binaire non généré malgré la compilation"
            log_message "Binary not generated despite successful compilation"
            exit 1
        fi
    else
        print_error "Échec de la compilation"
        echo -e "${RED}Logs de compilation (dernières lignes):${RESET}"
        tail -15 "$build_log"
        log_message "Compilation failed, check build log: $build_log"
        exit 1
    fi
    
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                          INSTALLATION DU BINAIRE                           │
# └─────────────────────────────────────────────────────────────────────────────┘

install_binary() {
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║${RESET}${WHITE}${BOLD}                         INSTALLATION DU BINAIRE                         ${RESET}${CYAN}${BOLD}║${RESET}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    print_step "Déploiement du binaire ASTRA..."
    
    # Copier le binaire
    if cp "$INSTALL_DIR/target/release/astra" "$BINARY_PATH"; then
        chmod +x "$BINARY_PATH"
        print_success "Binaire copié vers $BINARY_PATH"
        log_message "Binary deployed to $BINARY_PATH"
    else
        print_error "Échec de la copie du binaire"
        log_message "Binary deployment failed"
        exit 1
    fi
    
    # Test du binaire
    print_step "Test du binaire..."
    if "$BINARY_PATH" --help &> /dev/null; then
        print_success "Binaire fonctionnel et opérationnel"
        log_message "Binary test successful"
    else
        print_error "Le binaire ne fonctionne pas correctement"
        print_info "Vérifiez les dépendances système"
        log_message "Binary test failed"
        exit 1
    fi
    
    # Afficher les informations du binaire
    if command -v file &> /dev/null; then
        local binary_info=$(file "$BINARY_PATH" | cut -d':' -f2)
        print_info "Type: $binary_info"
    fi
    
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                         CONFIGURATION DU SYSTÈME                           │
# └─────────────────────────────────────────────────────────────────────────────┘

setup_configuration() {
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║${RESET}${WHITE}${BOLD}                        CONFIGURATION DU SYSTÈME                         ${RESET}${GREEN}${BOLD}║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    print_step "Création des répertoires système..."
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    print_success "Répertoires créés"
    
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
    print_success "Configuration principale créée"
    
    print_step "Configuration du service systemd..."
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
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                           DÉMARRAGE DU SERVICE                             │
# └─────────────────────────────────────────────────────────────────────────────┘

start_service() {
    echo -e "${BLUE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}${BOLD}║${RESET}${WHITE}${BOLD}                          DÉMARRAGE DU SERVICE                           ${RESET}${BLUE}${BOLD}║${RESET}"
    echo -e "${BLUE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    print_step "Rechargement de systemd..."
    systemctl daemon-reload
    print_success "Systemd rechargé"
    
    print_step "Activation du service au démarrage..."
    if systemctl enable astra &> /dev/null; then
        print_success "Service activé pour le démarrage automatique"
        log_message "Service enabled for auto-start"
    else
        print_warning "Problème lors de l'activation"
        log_message "Service enable failed"
    fi
    
    print_step "Démarrage d'ASTRA..."
    if systemctl start astra; then
        print_success "Commande de démarrage envoyée"
        log_message "Service start command sent"
    else
        print_error "Échec de la commande de démarrage"
        log_message "Service start command failed"
        exit 1
    fi
    
    # Attendre et vérifier le démarrage
    print_step "Vérification du démarrage..."
    sleep 3
    
    if systemctl is-active --quiet astra; then
        print_success "ASTRA fonctionne correctement"
        log_message "Service running successfully"
    else
        print_warning "Le service a des difficultés à démarrer"
        echo -e "${GRAY}Diagnostic automatique...${RESET}"
        journalctl -u astra --no-pager -l -n 5
        log_message "Service startup issues detected"
    fi
    
    echo
    sleep 1
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                            TESTS FINAUX                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

run_final_tests() {
    echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║${RESET}${WHITE}${BOLD}                           TESTS POST-INSTALLATION                        ${RESET}${YELLOW}${BOLD}║${RESET}"
    echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    local tests_passed=0
    local total_tests=6
    
    # Test 1: Binaire
    print_step "Test du binaire ASTRA..."
    if "$BINARY_PATH" --help &> /dev/null; then
        print_success "Binaire fonctionnel"
        ((tests_passed++))
        log_message "Binary test passed"
    else
        print_error "Problème avec le binaire"
        log_message "Binary test failed"
    fi
    
    # Test 2: Configuration
    print_step "Test de la configuration..."
    if [ -f "$CONFIG_DIR/config.json" ] && [ -r "$CONFIG_DIR/config.json" ]; then
        print_success "Configuration accessible"
        ((tests_passed++))
        log_message "Configuration test passed"
    else
        print_error "Configuration inaccessible"
        log_message "Configuration test failed"
    fi
    
    # Test 3: Service systemd
    print_step "Test du service systemd..."
    if systemctl is-enabled --quiet astra; then
        print_success "Service activé"
        ((tests_passed++))
        log_message "Service enabled test passed"
    else
        print_error "Service non activé"
        log_message "Service enabled test failed"
    fi
    
    # Test 4: Statut du service
    print_step "Test du statut du service..."
    if systemctl is-active --quiet astra; then
        print_success "Service actif"
        ((tests_passed++))
        log_message "Service active test passed"
    else
        print_warning "Service inactif ou en difficulté"
        log_message "Service active test failed"
    fi
    
    # Test 5: Logs
    print_step "Test des logs..."
    if [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ]; then
        print_success "Répertoire de logs opérationnel"
        ((tests_passed++))
        log_message "Logs test passed"
    else
        print_error "Problème avec les logs"
        log_message "Logs test failed"
    fi
    
    # Test 6: Rotation des logs
    print_step "Test de la rotation des logs..."
    if [ -f "/etc/logrotate.d/astra" ]; then
        print_success "Rotation des logs configurée"
        ((tests_passed++))
        log_message "Log rotation test passed"
    else
        print_error "Rotation des logs non configurée"
        log_message "Log rotation test failed"
    fi
    
    echo
    print_info "Tests réussis: $tests_passed/$total_tests"
    
    if [ $tests_passed -eq $total_tests ]; then
        print_success "Tous les tests sont passés avec succès"
        log_message "All tests passed successfully"
        return 0
    elif [ $tests_passed -ge 4 ]; then
        print_warning "Installation partiellement réussie"
        log_message "Installation partially successful"
        return 1
    else
        print_error "Installation échouée"
        log_message "Installation failed"
        return 2
    fi
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                             RAPPORT FINAL                                  │
# └─────────────────────────────────────────────────────────────────────────────┘

show_final_report() {
    local test_result=$1
    
    clear
    echo -e "${GREEN}${BOLD}"
    echo "    ╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "    ║                                                                              ║"
    
    if [ $test_result -eq 0 ]; then
        echo "    ║                    ${SUCCESS} INSTALLATION RÉUSSIE AVEC SUCCÈS ${SUCCESS}                  ║"
    elif [ $test_result -eq 1 ]; then
        echo "    ║                    ${WARNING} INSTALLATION PARTIELLEMENT RÉUSSIE ${WARNING}                ║"
    else
        echo "    ║                         ${CROSS} INSTALLATION ÉCHOUÉE ${CROSS}                          ║"
    fi
    
    echo "    ║                                                                              ║"
    echo "    ╚══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}\n"
    
    echo -e "${CYAN}${BOLD}📊 RÉSUMÉ DE L'INSTALLATION${RESET}"
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECK}${RESET} Version du script : ${WHITE}v${SCRIPT_VERSION}${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECK}${RESET} Binaire ASTRA     : ${WHITE}$BINARY_PATH${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECK}${RESET} Configuration     : ${WHITE}$CONFIG_DIR/config.json${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECK}${RESET} Logs              : ${WHITE}$LOG_DIR/${RESET}"
    echo -e "${CYAN}│${RESET} ${GREEN}${CHECK}${RESET} Service systemd   : ${WHITE}astra.service${RESET}"
    
    if systemctl is-active --quiet astra; then
        echo -e "${CYAN}│${RESET} ${GREEN}${CHECK}${RESET} Statut            : ${GREEN}${BOLD}ACTIF${RESET}"
    else
        echo -e "${CYAN}│${RESET} ${RED}${CROSS}${RESET} Statut            : ${RED}${BOLD}INACTIF${RESET}"
    fi
    
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    echo -e "${PURPLE}${BOLD}🔧 COMMANDES DE GESTION${RESET}"
    echo -e "${PURPLE}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Statut du service${RESET}     : ${WHITE}systemctl status astra${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Redémarrer ASTRA${RESET}      : ${WHITE}systemctl restart astra${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Arrêter ASTRA${RESET}         : ${WHITE}systemctl stop astra${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Logs en temps réel${RESET}    : ${WHITE}journalctl -u astra -f${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Fichier de logs${RESET}       : ${WHITE}tail -f $LOG_DIR/astra.log${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Éditer la config${RESET}      : ${WHITE}nano $CONFIG_DIR/config.json${RESET}"
    echo -e "${PURPLE}│${RESET} ${YELLOW}Désinstaller${RESET}          : ${WHITE}systemctl stop astra && rm -rf $INSTALL_DIR${RESET}"
    echo -e "${PURPLE}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    echo -e "${BLUE}${BOLD}🛡️ MODULES DE SÉCURITÉ DÉPLOYÉS${RESET}"
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}TCP Guardian${RESET}      : Protection anti-scan de ports"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}SIP Shield${RESET}        : Protection VoIP/téléphonie"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Firewall Intel${RESET}    : Pare-feu adaptatif intelligent"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Mode Stealth${RESET}      : Invisibilité totale aux scans"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Honeypots${RESET}         : Pièges automatiques"
    echo -e "${BLUE}│${RESET} ${GREEN}${SHIELD}${RESET} ${BOLD}Threat Intelligence${RESET}: IA de détection des menaces"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    echo -e "${GRAY}${BOLD}📋 INFORMATIONS TECHNIQUES${RESET}"
    echo -e "${GRAY}┌─────────────────────────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${GRAY}│${RESET} Installation    : $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${GRAY}│${RESET} Système         : $(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)"
    echo -e "${GRAY}│${RESET} Architecture    : $(uname -m)"
    echo -e "${GRAY}│${RESET} Rust Version    : $(rustc --version 2>/dev/null | awk '{print $2}' || echo 'N/A')"
    echo -e "${GRAY}│${RESET} Log d'install   : /tmp/astra_install.log"
    echo -e "${GRAY}└─────────────────────────────────────────────────────────────────────────────┘${RESET}\n"
    
    if [ $test_result -eq 0 ]; then
        echo -e "${GREEN}${BOLD}${SUCCESS} ASTRA Defense Engine est maintenant opérationnel !${RESET}"
        echo -e "${GREEN}Votre système est protégé par une défense de niveau militaire.${RESET}"
    elif [ $test_result -eq 1 ]; then
        echo -e "${YELLOW}${BOLD}${WARNING} Installation partiellement réussie${RESET}"
        echo -e "${YELLOW}Vérifiez le statut avec: systemctl status astra${RESET}"
    else
        echo -e "${RED}${BOLD}${CROSS} Installation échouée${RESET}"
        echo -e "${RED}Consultez les logs pour plus d'informations.${RESET}"
    fi
    
    echo
    echo -e "${RED}${BOLD}⚠️ AVERTISSEMENT DE SÉCURITÉ${RESET}"
    echo -e "${RED}ASTRA nécessite les privilèges root pour la surveillance réseau.${RESET}"
    echo -e "${RED}Assurez-vous de sécuriser l'accès à votre serveur.${RESET}"
    echo
    
    # Affichage du statut du service
    if systemctl is-active --quiet astra; then
        echo -e "${CYAN}📈 STATUT ACTUEL DU SERVICE:${RESET}"
        systemctl status astra --no-pager -l
    fi
    
    echo
    echo -e "${GRAY}Installation par ASTRA Defense Engine v${SCRIPT_VERSION}${RESET}"
    echo -e "${GRAY}Plus d'informations: https://github.com/FIlox77250/Astra-cyber${RESET}"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                        GESTION DES ARGUMENTS                               │
# └─────────────────────────────────────────────────────────────────────────────┘

show_help() {
    echo -e "${CYAN}${BOLD}ASTRA Defense Engine - Installation Script v${SCRIPT_VERSION}${RESET}"
    echo
    echo -e "${WHITE}${BOLD}USAGE:${RESET}"
    echo "  curl -sSL https://raw.githubusercontent.com/FIlox77250/Astra-cyber/main/install-astra.sh | sudo bash"
    echo
    echo -e "${WHITE}${BOLD}OPTIONS:${RESET}"
    echo "  --help          Afficher cette aide"
    echo "  --version       Afficher la version du script"
    echo "  --check-only    Vérifier le système uniquement"
    echo "  --force         Forcer l'installation même en cas de problèmes"
    echo
    echo -e "${WHITE}${BOLD}PRÉREQUIS:${RESET}"
    echo "  • Système: Debian 11+ ou Ubuntu 20.04+"
    echo "  • Privilèges: Root (sudo)"
    echo "  • Espace disque: 2GB minimum"
    echo "  • Connexion internet active"
    echo
    echo -e "${WHITE}${BOLD}SUPPORT:${RESET}"
    echo "  • Documentation: https://github.com/FIlox77250/Astra-cyber"
    echo "  • Issues: https://github.com/FIlox77250/Astra-cyber/issues"
    echo "  • Web: https://brcloud.fr"
    echo
}

show_version() {
    echo -e "${CYAN}${BOLD}ASTRA Defense Engine${RESET}"
    echo -e "${WHITE}Installation Script Version: ${SCRIPT_VERSION}${RESET}"
    echo -e "${GRAY}Advanced Stealth Threat Response Architecture${RESET}"
    echo -e "${GRAY}Copyright (c) 2024 BRCloud.fr${RESET}"
}

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │                              FONCTION PRINCIPALE                           │
# └─────────────────────────────────────────────────────────────────────────────┘

main() {
    # Initialiser le log
    echo "ASTRA Installation Log - $(date)" > /tmp/astra_install.log
    log_message "Installation script v${SCRIPT_VERSION} started"
    
    # Gestion des signaux
    trap 'echo -e "\n${RED}${BOLD}Installation interrompue par l\'utilisateur${RESET}"; log_message "Installation interrupted by user"; exit 130' INT TERM
    
    # Gestion des arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            show_version
            exit 0
            ;;
        --check-only)
            show_banner
            check_system
            echo -e "${GREEN}${BOLD}Vérifications terminées.${RESET}"
            exit 0
            ;;
        --force)
            export FORCE_INSTALL=true
            ;;
        "")
            # Installation normale
            ;;
        *)
            echo -e "${RED}Option inconnue: $1${RESET}"
            echo "Utilisez --help pour voir les options disponibles."
            exit 1
            ;;
    esac
    
    # Séquence d'installation principale
    show_banner
    log_message "Starting main installation sequence"
    
    # Étapes d'installation
    check_system
    install_dependencies
    install_rust
    download_source
    compile_astra
    install_binary
    setup_configuration
    start_service
    
    # Tests et rapport final
    run_final_tests
    local test_result=$?
    
    show_final_report $test_result
    
    log_message "Installation completed with result: $test_result"
    
    # Code de sortie basé sur les tests
    exit $test_result
}

# ═══════════════════════════════════════════════════════════════════════════════
#                                POINT D'ENTRÉE
# ═══════════════════════════════════════════════════════════════════════════════

# Vérification de l'environnement bash
if [ -z "$BASH_VERSION" ]; then
    echo "Erreur: Ce script nécessite Bash pour fonctionner correctement."
    exit 1
fi

# Lancement du script principal
main "$@"
