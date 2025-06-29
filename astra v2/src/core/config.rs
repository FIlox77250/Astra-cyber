use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub system: SystemConfig,
    pub network: NetworkConfig,
    pub security: SecurityConfig,
    pub logging: LoggingConfig,
    pub modules: ModulesConfig,
    pub firewall: FirewallConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemConfig {
    pub stealth_mode: bool,
    pub max_memory_usage: u64,    // MB
    pub max_cpu_usage: f32,       // Percentage
    pub update_interval: u64,     // Seconds
    pub auto_restart: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkConfig {
    pub interfaces: Vec<String>,
    pub monitor_all_interfaces: bool,
    pub promiscuous_mode: bool,
    pub capture_buffer_size: usize,
    pub packet_timeout: u64,      // Milliseconds
    pub ipv6_support: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityConfig {
    pub default_sensitivity: u8,
    pub auto_block_enabled: bool,
    pub auto_block_threshold: f32,
    pub honeypot_enabled: bool,
    pub counter_recon_enabled: bool,
    pub threat_intel_enabled: bool,
    pub whitelist_ips: Vec<String>,
    pub blacklist_ips: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoggingConfig {
    pub log_level: String,
    pub log_file: String,
    pub max_log_size: u64,        // MB
    pub log_retention_days: u32,
    pub syslog_enabled: bool,
    pub json_format: bool,
    pub audit_trail: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModulesConfig {
    pub tcp_guard: TcpGuardConfig,
    pub sip_shield: SipShieldConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TcpGuardConfig {
    pub enabled: bool,
    pub sensitivity: u8,
    pub scan_threshold: usize,
    pub time_window: u64,         // Seconds
    pub syn_flood_threshold: u32,
    pub stealth_ports: Vec<u16>,
    pub honeypot_responses: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SipShieldConfig {
    pub enabled: bool,
    pub sensitivity: u8,
    pub monitored_ports: Vec<u16>,
    pub attack_threshold: u32,
    pub registration_monitoring: bool,
    pub invite_flood_threshold: u32,
    pub brute_force_threshold: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FirewallConfig {
    pub enabled: bool,
    pub default_policy: String,
    pub custom_rules: Vec<String>,
    pub auto_rules: bool,
    pub backup_rules: bool,
    pub iptables_path: String,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            system: SystemConfig {
                stealth_mode: true,
                max_memory_usage: 512,
                max_cpu_usage: 80.0,
                update_interval: 1,
                auto_restart: true,
            },
            network: NetworkConfig {
                interfaces: vec!["eth0".to_string(), "wlan0".to_string()],
                monitor_all_interfaces: true,
                promiscuous_mode: false,
                capture_buffer_size: 8192,
                packet_timeout: 100,
                ipv6_support: false,
            },
            security: SecurityConfig {
                default_sensitivity: 5,
                auto_block_enabled: true,
                auto_block_threshold: 0.7,
                honeypot_enabled: true,
                counter_recon_enabled: true,
                threat_intel_enabled: true,
                whitelist_ips: vec![
                    "127.0.0.1".to_string(),
                    "::1".to_string(),
                    "192.168.1.0/24".to_string(),
                    "10.0.0.0/8".to_string(),
                    "172.16.0.0/12".to_string(),
                ],
                blacklist_ips: vec![],
            },
            logging: LoggingConfig {
                log_level: "INFO".to_string(),
                log_file: "/var/log/astra/astra.log".to_string(),
                max_log_size: 100,
                log_retention_days: 30,
                syslog_enabled: true,
                json_format: false,
                audit_trail: true,
            },
            modules: ModulesConfig {
                tcp_guard: TcpGuardConfig {
                    enabled: true,
                    sensitivity: 5,
                    scan_threshold: 3,
                    time_window: 10,
                    syn_flood_threshold: 10,
                    stealth_ports: vec![
                        22, 23, 25, 53, 80, 110, 143, 443, 993, 995,
                        135, 139, 445, 1433, 3389,
                        21, 69, 161, 162, 514, 873,
                        5060, 5061,
                    ],
                    honeypot_responses: true,
                },
                sip_shield: SipShieldConfig {
                    enabled: true,
                    sensitivity: 5,
                    monitored_ports: vec![5060, 5061],
                    attack_threshold: 10,
                    registration_monitoring: true,
                    invite_flood_threshold: 20,
                    brute_force_threshold: 5,
                },
            },
            firewall: FirewallConfig {
                enabled: true,
                default_policy: "DROP".to_string(),
                custom_rules: vec![],
                auto_rules: true,
                backup_rules: true,
                iptables_path: "/sbin/iptables".to_string(),
            },
        }
    }
}

impl Config {
    pub fn load() -> Result<Self, Box<dyn std::error::Error>> {
        let config_paths = vec![
            "/etc/astra/config.json",
            "./config.json",
            "~/.config/astra/config.json",
        ];

        // Try to load from existing config files
        for path in config_paths {
            if Path::new(path).exists() {
                let config_data = fs::read_to_string(path)?;
                let config: Config = serde_json::from_str(&config_data)?;
                println!("📋 Configuration loaded from: {}", path);
                return Ok(config);
            }
        }

        // Create default config if none found
        let default_config = Config::default();
        
        // Try to create config directory and save default config
        if let Err(e) = fs::create_dir_all("/etc/astra") {
            println!("⚠️  Could not create /etc/astra directory: {}", e);
        } else {
            if let Ok(config_json) = serde_json::to_string_pretty(&default_config) {
                if let Err(e) = fs::write("/etc/astra/config.json", config_json) {
                    println!("⚠️  Could not save default config to /etc/astra/config.json: {}", e);
                } else {
                    println!("📝 Default configuration created at: /etc/astra/config.json");
                }
            }
        }

        println!("⚙️  Using default configuration");
        Ok(default_config)
    }

    pub fn save(&self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let config_json = serde_json::to_string_pretty(self)?;
        
        // Create directory if it doesn't exist
        if let Some(parent) = Path::new(path).parent() {
            fs::create_dir_all(parent)?;
        }
        
        fs::write(path, config_json)?;
        println!("💾 Configuration saved to: {}", path);
        Ok(())
    }

    pub fn validate(&self) -> Result<(), Box<dyn std::error::Error>> {
        // Validate system config
        if self.system.max_cpu_usage > 100.0 || self.system.max_cpu_usage < 1.0 {
            return Err("Invalid CPU usage limit (must be 1-100%)".into());
        }

        if self.system.max_memory_usage < 64 {
            return Err("Minimum memory requirement is 64MB".into());
        }

        // Validate security config
        if self.security.default_sensitivity > 10 || self.security.default_sensitivity < 1 {
            return Err("Sensitivity level must be between 1-10".into());
        }

        if self.security.auto_block_threshold > 1.0 || self.security.auto_block_threshold < 0.0 {
            return Err("Auto-block threshold must be between 0.0-1.0".into());
        }

        // Validate module configs
        if self.modules.tcp_guard.sensitivity > 10 || self.modules.tcp_guard.sensitivity < 1 {
            return Err("TCP Guard sensitivity must be between 1-10".into());
        }

        if self.modules.sip_shield.sensitivity > 10 || self.modules.sip_shield.sensitivity < 1 {
            return Err("SIP Shield sensitivity must be between 1-10".into());
        }

        // Validate firewall config
        if !["ACCEPT", "DROP", "REJECT"].contains(&self.firewall.default_policy.as_str()) {
            return Err("Invalid firewall default policy (must be ACCEPT, DROP, or REJECT)".into());
        }

        // Check if iptables exists
        if !Path::new(&self.firewall.iptables_path).exists() {
            return Err(format!("iptables not found at: {}", self.firewall.iptables_path).into());
        }

        println!("✅ Configuration validation passed");
        Ok(())
    }

    pub fn get_interface_list(&self) -> Vec<String> {
        if self.network.monitor_all_interfaces {
            // Get all available network interfaces
            use pnet::datalink;
            datalink::interfaces()
                .into_iter()
                .filter(|iface| iface.is_up() && !iface.is_loopback())
                .map(|iface| iface.name)
                .collect()
        } else {
            self.network.interfaces.clone()
        }
    }

    pub fn is_whitelisted_ip(&self, ip: &str) -> bool {
        self.security.whitelist_ips.iter().any(|whitelisted| {
            if whitelisted.contains('/') {
                // CIDR notation check (simplified)
                ip.starts_with(&whitelisted.split('/').next().unwrap_or("")[..whitelisted.len().min(ip.len())])
            } else {
                ip == whitelisted
            }
        })
    }

    pub fn is_blacklisted_ip(&self, ip: &str) -> bool {
        self.security.blacklist_ips.iter().any(|blacklisted| {
            if blacklisted.contains('/') {
                // CIDR notation check (simplified)
                ip.starts_with(&blacklisted.split('/').next().unwrap_or("")[..blacklisted.len().min(ip.len())])
            } else {
                ip == blacklisted
            }
        })
    }

    pub fn update_runtime_config(&mut self, updates: HashMap<String, serde_json::Value>) -> Result<(), Box<dyn std::error::Error>> {
        for (key, value) in updates {
            match key.as_str() {
                "system.stealth_mode" => {
                    if let Some(val) = value.as_bool() {
                        self.system.stealth_mode = val;
                    }
                }
                "security.default_sensitivity" => {
                    if let Some(val) = value.as_u64() {
                        if val >= 1 && val <= 10 {
                            self.security.default_sensitivity = val as u8;
                        }
                    }
                }
                "modules.tcp_guard.sensitivity" => {
                    if let Some(val) = value.as_u64() {
                        if val >= 1 && val <= 10 {
                            self.modules.tcp_guard.sensitivity = val as u8;
                        }
                    }
                }
                "modules.sip_shield.sensitivity" => {
                    if let Some(val) = value.as_u64() {
                        if val >= 1 && val <= 10 {
                            self.modules.sip_shield.sensitivity = val as u8;
                        }
                    }
                }
                _ => {
                    println!("⚠️  Unknown configuration key: {}", key);
                }
            }
        }
        
        // Validate after updates
        self.validate()?;
        Ok(())
    }
}