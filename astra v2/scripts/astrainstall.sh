#!/bin/bash

# ASTRA Defense Engine - Installation Unifiée
# Advanced Stealth Threat Response Architecture
# Script d'installation automatique pour Debian/Ubuntu

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
ASTRA_REPO="https://github.com/FIlox77250/Astra-cyber.git"
INSTALL_DIR="/opt/astra"
LOG_DIR="/var/log/astra"
CONFIG_DIR="/etc/astra"

# ASCII Banner
echo -e "${PURPLE}"
cat << "EOF"
    ░█████╗░░██████╗████████╗██████╗░░█████╗░
    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗
    ███████║╚█████╗░░░░██║░░░██████╔╝███████║
    ██╔══██║░╚═══██╗░░░██║░░░██╔══██╗██╔══██║
    ██║░░██║██████╔╝░░░██║░░░██║░░██║██║░░██║
    ╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝
    
    ADVANCED STEALTH THREAT RESPONSE ARCHITECTURE
    Installation Automatique v2.0
    Installation Unifiée pour Debian/Ubuntu
EOF
echo -e "${NC}"

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Ce script doit être exécuté en tant que root (sudo su)"
        echo "Usage: sudo $0 [OPTIONS]"
        exit 1
    fi
}

# Check OS compatibility
check_os() {
    print_step "Vérification de la compatibilité du système..."
    
    if ! grep -qi 'debian\|ubuntu' /etc/os-release; then
        print_error "Ce script ne fonctionne que sur Debian/Ubuntu"
        exit 1
    fi
    
    # Get OS info
    OS_NAME=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2)
    OS_VERSION=$(grep '^VERSION=' /etc/os-release | cut -d'"' -f2)
    
    print_success "Système compatible détecté: $OS_NAME $OS_VERSION"
}

# Install system dependencies
install_dependencies() {
    print_step "Installation des dépendances système..."
    
    # Update package list
    print_status "Mise à jour des paquets..."
    apt update
    
    # Install base dependencies
    local packages=(
        "curl"
        "wget" 
        "git"
        "build-essential"
        "libpcap-dev"
        "iptables"
        "iptables-persistent"
        "pkg-config"
        "libssl-dev"
        "net-tools"
    )
    
    print_status "Installation des paquets requis..."
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            print_status "Installation de $package..."
            apt install -y "$package"
        else
            print_status "$package déjà installé"
        fi
    done
    
    print_success "Dépendances système installées"
}

# Install Rust if not present
install_rust() {
    print_step "Vérification de Rust..."
    
    if ! command -v cargo >/dev/null 2>&1; then
        print_status "Installation de Rust..."
        
        # Install Rust for root user
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        
        # Source Rust environment
        if [ -f "$HOME/.cargo/env" ]; then
            source "$HOME/.cargo/env"
        fi
        
        # Add to PATH for current session
        export PATH="$HOME/.cargo/bin:$PATH"
        
        # Verify installation
        if command -v cargo >/dev/null 2>&1; then
            RUST_VERSION=$(rustc --version)
            print_success "Rust installé: $RUST_VERSION"
        else
            print_error "Échec de l'installation de Rust"
            exit 1
        fi
    else
        RUST_VERSION=$(rustc --version)
        print_success "Rust déjà installé: $RUST_VERSION"
    fi
}

# Clone or update ASTRA repository
setup_repository() {
    print_step "Configuration du dépôt ASTRA..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [ -d ".git" ]; then
        print_status "Mise à jour du dépôt existant..."
        git pull origin main || git pull origin master
    else
        print_status "Clonage du dépôt ASTRA..."
        # Remove any existing files
        rm -rf ./*
        git clone "$ASTRA_REPO" .
    fi
    
    print_success "Dépôt ASTRA configuré dans $INSTALL_DIR"
}

# Build ASTRA
build_astra() {
    print_step "Compilation d'ASTRA..."
    
    cd "$INSTALL_DIR"
    
    # Ensure Rust is available
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Clean previous builds
    print_status "Nettoyage des builds précédents..."
    cargo clean
    
    # Build in release mode
    print_status "Compilation en mode release (optimisé)..."
    RUST_BACKTRACE=1 cargo build --release
    
    if [ $? -eq 0 ]; then
        print_success "ASTRA compilé avec succès"
        ls -lh target/release/astra
    else
        print_error "Échec de la compilation"
        exit 1
    fi
}

# Deploy ASTRA binary
deploy_binary() {
    print_step "Déploiement du binaire ASTRA..."
    
    # Copy binary to system path
    cp "$INSTALL_DIR/target/release/astra" /usr/local/bin/astra
    chmod +x /usr/local/bin/astra
    
    # Verify deployment
    if [ -f "/usr/local/bin/astra" ]; then
        print_success "Binaire ASTRA déployé dans /usr/local/bin/astra"
    else
        print_error "Échec du déploiement du binaire"
        exit 1
    fi
}

# Create configuration
create_configuration() {
    print_step "Création de la configuration..."
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    # Create default configuration
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
    "interfaces": ["eth0", "ens18", "wlan0"],
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
      "127.0.0.1",
      "::1",
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
      "stealth_ports": [
        22, 23, 25, 53, 80, 110, 143, 443, 993, 995,
        135, 139, 445, 1433, 3389,
        21, 69, 161, 162, 514, 873,
        5060, 5061
      ],
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
    
    # Set permissions
    chmod 600 "$CONFIG_DIR/config.json"
    chown root:root "$CONFIG_DIR/config.json"
    chmod 755 "$LOG_DIR"
    
    print_success "Configuration créée dans $CONFIG_DIR/config.json"
}

# Create systemd service
create_systemd_service() {
    print_step "Création du service systemd..."
    
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
StandardError=append:/var/log/astra/astra_error.log

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/astra /etc/astra /tmp
PrivateTmp=yes
PrivateDevices=false
ProtectHostname=yes
ProtectClock=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RemoveIPC=yes

# Capabilities needed for network operations
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SYS_ADMIN
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN CAP_NET_BIND_SERVICE

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096
MemoryMax=1G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Service systemd créé"
}

# Setup log rotation
setup_log_rotation() {
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
}

# Start and enable ASTRA service
start_astra_service() {
    print_step "Démarrage du service ASTRA..."
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable service for auto-start
    systemctl enable astra
    
    # Start service
    systemctl start astra
    
    # Check service status
    sleep 3
    if systemctl is-active --quiet astra; then
        print_success "Service ASTRA démarré avec succès"
    else
        print_warning "Le service ASTRA a des difficultés à démarrer"
        print_status "Vérification du statut..."
        systemctl status astra --no-pager -l
    fi
}

# Run post-installation tests
run_post_install_tests() {
    print_step "Tests post-installation..."
    
    # Test binary execution
    if /usr/local/bin/astra --help >/dev/null 2>&1; then
        print_success "Binaire ASTRA fonctionnel"
    else
        print_warning "Le binaire ASTRA pourrait avoir des problèmes"
    fi
    
    # Test configuration file
    if [ -f "$CONFIG_DIR/config.json" ]; then
        print_success "Configuration trouvée"
    else
        print_error "Configuration manquante"
    fi
    
    # Test log directory
    if [ -d "$LOG_DIR" ]; then
        print_success "Répertoire de logs créé"
    else
        print_error "Répertoire de logs manquant"
    fi
    
    # Test service status
    if systemctl is-enabled --quiet astra; then
        print_success "Service activé pour le démarrage automatique"
    else
        print_warning "Service non activé pour le démarrage automatique"
    fi
}

# Display final information
show_final_info() {
    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                     🛡️  ASTRA INSTALLÉ AVEC SUCCÈS 🛡️              ${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo
    print_success "Installation terminée !"
    echo
    echo -e "${CYAN}📍 Informations importantes:${NC}"
    echo "   • Binaire: /usr/local/bin/astra"
    echo "   • Configuration: $CONFIG_DIR/config.json"
    echo "   • Logs: $LOG_DIR/"
    echo "   • Service: astra.service"
    echo
    echo -e "${CYAN}🔧 Commandes utiles:${NC}"
    echo "   • Statut du service:     systemctl status astra"
    echo "   • Redémarrer ASTRA:     systemctl restart astra"
    echo "   • Voir les logs:        tail -f $LOG_DIR/astra.log"
    echo "   • Logs en temps réel:   journalctl -u astra -f"
    echo "   • Arrêter ASTRA:        systemctl stop astra"
    echo "   • Configuration:        nano $CONFIG_DIR/config.json"
    echo
    echo -e "${CYAN}🚨 Sécurité:${NC}"
    echo "   • Mode furtif activé"
    echo "   • Protection TCP et SIP active"
    echo "   • Firewall intelligent déployé"
    echo "   • Détection d'intrusion en temps réel"
    echo
    echo -e "${YELLOW}⚠️  Note: ASTRA fonctionne avec les privilèges root pour la capture réseau${NC}"
    echo
    print_success "ASTRA Defense Engine est maintenant opérationnel !"
}

# Show usage information
show_usage() {
    echo "ASTRA Defense Engine - Script d'Installation Unifié"
    echo
    echo "Usage: sudo $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --full             Installation complète (par défaut)"
    echo "  --update           Mise à jour d'une installation existante"
    echo "  --config-only      Recréer seulement la configuration"
    echo "  --service-only     Recréer seulement le service systemd"
    echo "  --uninstall        Désinstaller ASTRA"
    echo "  --status           Afficher le statut de ASTRA"
    echo "  --help             Afficher cette aide"
    echo
    echo "Exemples:"
    echo "  sudo $0                    # Installation complète"
    echo "  sudo $0 --update          # Mise à jour"
    echo "  sudo $0 --status          # Vérifier le statut"
    echo
}

# Update existing installation
update_astra() {
    print_step "Mise à jour d'ASTRA..."
    
    # Stop service
    systemctl stop astra || true
    
    # Update repository
    setup_repository
    
    # Rebuild
    build_astra
    
    # Deploy new binary
    deploy_binary
    
    # Restart service
    systemctl start astra
    
    print_success "ASTRA mis à jour avec succès"
}

# Uninstall ASTRA
uninstall_astra() {
    print_step "Désinstallation d'ASTRA..."
    
    # Stop and disable service
    systemctl stop astra || true
    systemctl disable astra || true
    
    # Remove files
    rm -f /etc/systemd/system/astra.service
    rm -f /usr/local/bin/astra
    rm -rf "$INSTALL_DIR"
    rm -f /etc/logrotate.d/astra
    
    # Ask about config and logs
    read -p "Supprimer aussi la configuration et les logs ? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -rf "$LOG_DIR"
        print_success "Configuration et logs supprimés"
    fi
    
    systemctl daemon-reload
    
    print_success "ASTRA désinstallé"
}

# Show current status
show_status() {
    echo -e "${CYAN}📊 Statut d'ASTRA:${NC}"
    echo
    
    # Service status
    if systemctl is-active --quiet astra; then
        echo -e "   Service: ${GREEN}Actif${NC}"
    else
        echo -e "   Service: ${RED}Inactif${NC}"
    fi
    
    # Binary check
    if [ -f "/usr/local/bin/astra" ]; then
        echo -e "   Binaire: ${GREEN}Installé${NC}"
    else
        echo -e "   Binaire: ${RED}Manquant${NC}"
    fi
    
    # Config check
    if [ -f "$CONFIG_DIR/config.json" ]; then
        echo -e "   Configuration: ${GREEN}Présente${NC}"
    else
        echo -e "   Configuration: ${RED}Manquante${NC}"
    fi
    
    # Show service details
    echo
    echo -e "${CYAN}Détails du service:${NC}"
    systemctl status astra --no-pager -l || true
    
    # Show recent logs
    echo
    echo -e "${CYAN}Logs récents:${NC}"
    journalctl -u astra --no-pager -l -n 10 || true
}

# Main installation function
main_install() {
    check_root
    check_os
    install_dependencies
    install_rust
    setup_repository
    build_astra
    deploy_binary
    create_configuration
    create_systemd_service
    setup_log_rotation
    start_astra_service
    run_post_install_tests
    show_final_info
}

# Main script logic
main() {
    # Parse command line arguments
    case "${1:-}" in
        --full|"")
            main_install
            ;;
        --update)
            check_root
            update_astra
            ;;
        --config-only)
            check_root
            create_configuration
            systemctl restart astra || true
            print_success "Configuration recréée"
            ;;
        --service-only)
            check_root
            create_systemd_service
            systemctl daemon-reload
            print_success "Service systemd recréé"
            ;;
        --uninstall)
            check_root
            uninstall_astra
            ;;
        --status)
            show_status
            ;;
        --help)
            show_usage
            ;;
        *)
            print_error "Option inconnue: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function with arguments
main "$@"
