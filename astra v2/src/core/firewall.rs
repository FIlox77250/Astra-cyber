use std::collections::HashMap;
use std::net::IpAddr;
use std::process::{Command, Output};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use chrono::{DateTime, Utc};

use crate::core::config::Config;

#[derive(Debug, Clone)]
struct FirewallRule {
    id: String,
    chain: String,
    rule: String,
    timestamp: DateTime<Utc>,
    persistent: bool,
}

#[derive(Debug, Clone)]
struct BlockedIp {
    ip: IpAddr,
    blocked_at: Instant,
    expires_at: Option<Instant>,
    reason: String,
    block_count: u32,
}

#[derive(Debug, Clone)]
struct RateLimit {
    ip: IpAddr,
    limit: u32,
    window: Duration,
    current_count: u32,
    window_start: Instant,
}

pub struct Firewall {
    config: Arc<Config>,
    iptables_path: String,
    active_rules: Vec<FirewallRule>,
    blocked_ips: HashMap<IpAddr, BlockedIp>,
    rate_limits: HashMap<IpAddr, RateLimit>,
    rule_counter: u32,
    stealth_mode: bool,
    backup_created: bool,
}

impl Firewall {
    pub fn new(config: &Arc<Config>) -> Result<Self, Box<dyn std::error::Error>> {
        let iptables_path = config.firewall.iptables_path.clone();
        
        // Verify iptables is available
        let output = Command::new(&iptables_path)
            .args(&["--version"])
            .output();
            
        match output {
            Ok(_) => println!("🔥 Firewall module initialized - iptables ready"),
            Err(e) => return Err(format!("Failed to initialize firewall: iptables not found at {}: {}", iptables_path, e).into()),
        }

        let mut firewall = Firewall {
            config: config.clone(),
            iptables_path,
            active_rules: Vec::new(),
            blocked_ips: HashMap::new(),
            rate_limits: HashMap::new(),
            rule_counter: 0,
            stealth_mode: config.system.stealth_mode,
            backup_created: false,
        };

        // Create backup of current rules if enabled
        if config.firewall.backup_rules {
            firewall.backup_current_rules()?;
        }

        // Initialize basic security rules
        firewall.initialize_base_rules()?;

        Ok(firewall)
    }

    fn backup_current_rules(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        let timestamp = Utc::now().format("%Y%m%d_%H%M%S");
        let backup_file = format!("/etc/astra/firewall_backup_{}.rules", timestamp);

        let output = Command::new(&self.iptables_path)
            .args(&["-S"])
            .output();

        match output {
            Ok(result) => {
                std::fs::create_dir_all("/etc/astra")?;
                std::fs::write(&backup_file, result.stdout)?;
                println!("💾 Firewall rules backed up to: {}", backup_file);
                self.backup_created = true;
            }
            Err(e) => {
                println!("⚠️  Warning: Could not backup firewall rules: {}", e);
            }
        }

        Ok(())
    }

    fn initialize_base_rules(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        println!("🛡️  Initializing base firewall rules...");

        // Allow loopback traffic
        self.add_rule("INPUT", "-i lo -j ACCEPT")?;
        self.add_rule("OUTPUT", "-o lo -j ACCEPT")?;

        // Allow established and related connections
        self.add_rule("INPUT", "-m state --state ESTABLISHED,RELATED -j ACCEPT")?;
        self.add_rule("OUTPUT", "-m state --state ESTABLISHED -j ACCEPT")?;

        // Drop invalid packets
        self.add_rule("INPUT", "-m state --state INVALID -j DROP")?;

        // Rate limiting for SSH (prevent brute force)
        self.add_rule("INPUT", "-p tcp --dport 22 -m state --state NEW -m recent --set --name SSH")?;
        self.add_rule("INPUT", "-p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j LOG --log-prefix 'SSH-ATTACK: '")?;
        self.add_rule("INPUT", "-p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP")?;

        // Basic stealth rules if enabled
        if self.stealth_mode {
            self.enable_stealth_mode()?;
        }

        // Apply custom rules from config
        for rule in &self.config.firewall.custom_rules {
            if let Err(e) = self.add_custom_rule(rule) {
                println!("⚠️  Warning: Failed to apply custom rule '{}': {}", rule, e);
            }
        }

        println!("✅ Base firewall rules initialized");
        Ok(())
    }

    fn enable_stealth_mode(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        println!("👻 Enabling stealth mode...");

        // Drop ICMP ping requests (become invisible to ping)
        self.add_stealth_rule("INPUT", "-p icmp --icmp-type echo-request -j DROP")?;

        // Drop all TCP RST responses (hide closed ports)
        self.add_stealth_rule("OUTPUT", "-p tcp --tcp-flags RST RST -j DROP")?;

        // Log and drop port scans
        self.add_stealth_rule("INPUT", "-p tcp --syn -m state --state NEW -m recent --set --name PORTSCAN")?;
        self.add_stealth_rule("INPUT", "-p tcp --syn -m state --state NEW -m recent --update --seconds 10 --hitcount 3 --name PORTSCAN -j LOG --log-prefix 'ASTRA-PORTSCAN: '")?;
        self.add_stealth_rule("INPUT", "-p tcp --syn -m state --state NEW -m recent --update --seconds 10 --hitcount 3 --name PORTSCAN -j DROP")?;

        // Drop packets to commonly scanned ports
        let stealth_ports = &self.config.modules.tcp_guard.stealth_ports;
        for &port in stealth_ports {
            self.add_stealth_rule("INPUT", &format!("-p tcp --dport {} -j LOG --log-prefix 'ASTRA-STEALTH-{}: '", port, port))?;
            self.add_stealth_rule("INPUT", &format!("-p tcp --dport {} -j DROP", port))?;
        }

        println!("👻 Stealth mode activated - system invisible to reconnaissance");
        Ok(())
    }

    pub fn add_rule(&mut self, chain: &str, rule: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.rule_counter += 1;
        let rule_id = format!("ASTRA-{:06}", self.rule_counter);

        let mut cmd = Command::new(&self.iptables_path);
        cmd.args(&["-I", chain]);
        
        // Parse and add rule parameters
        for param in rule.split_whitespace() {
            cmd.arg(param);
        }

        // Add comment for tracking
        cmd.args(&["-m", "comment", "--comment", &rule_id]);

        let output = cmd.output()?;

        if output.status.success() {
            let firewall_rule = FirewallRule {
                id: rule_id.clone(),
                chain: chain.to_string(),
                rule: rule.to_string(),
                timestamp: Utc::now(),
                persistent: false,
            };
            
            self.active_rules.push(firewall_rule);
            println!("🔧 Added firewall rule [{}]: {} {}", rule_id, chain, rule);
        } else {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Failed to add firewall rule: {}", error).into());
        }

        Ok(())
    }

    pub fn add_stealth_rule(&mut self, chain: &str, rule: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.rule_counter += 1;
        let rule_id = format!("ASTRA-STEALTH-{:06}", self.rule_counter);

        let mut cmd = Command::new(&self.iptables_path);
        cmd.args(&["-I", chain]);
        
        for param in rule.split_whitespace() {
            cmd.arg(param);
        }

        cmd.args(&["-m", "comment", "--comment", &rule_id]);

        let output = cmd.output()?;

        if output.status.success() {
            let firewall_rule = FirewallRule {
                id: rule_id.clone(),
                chain: chain.to_string(),
                rule: rule.to_string(),
                timestamp: Utc::now(),
                persistent: true, // Stealth rules are persistent
            };
            
            self.active_rules.push(firewall_rule);
            println!("👻 Added stealth rule [{}]: {} {}", rule_id, chain, rule);
        } else {
            let error = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Failed to add stealth rule: {}", error).into());
        }

        Ok(())
    }

    pub fn add_custom_rule(&mut self, rule: &str) -> Result<(), Box<dyn std::error::Error>> {
        // Parse custom rule format: "CHAIN:RULE"
        let parts: Vec<&str> = rule.splitn(2, ':').collect();
        if parts.len() != 2 {
            return Err(format!("Invalid custom rule format: '{}' (expected 'CHAIN:RULE')", rule).into());
        }

        let chain = parts[0].trim();
        let rule_params = parts[1].trim();

        self.add_rule(chain, rule_params)?;
        Ok(())
    }

    pub fn block_ip_permanent(&mut self, ip: IpAddr) -> Result<(), Box<dyn std::error::Error>> {
        if self.blocked_ips.contains_key(&ip) {
            // Update existing block
            if let Some(blocked) = self.blocked_ips.get_mut(&ip) {
                blocked.block_count += 1;
                blocked.expires_at = None; // Make it permanent
                blocked.reason = "PERMANENT_THREAT".to_string();
            }
            return Ok(());
        }

        // Add permanent block rule
        let rule = format!("-s {} -j DROP", ip);
        self.add_rule("INPUT", &rule)?;

        // Track blocked IP
        let blocked_ip = BlockedIp {
            ip,
            blocked_at: Instant::now(),
            expires_at: None, // Permanent
            reason: "HIGH_THREAT_PERMANENT".to_string(),
            block_count: 1,
        };

        self.blocked_ips.insert(ip, blocked_ip);
        println!("🚫 PERMANENT BLOCK: {} - Added to firewall blackhole", ip);

        Ok(())
    }

    pub fn block_ip_temporary(&mut self, ip: IpAddr, duration: Duration) -> Result<(), Box<dyn std::error::Error>> {
        let expires_at = Instant::now() + duration;

        if self.blocked_ips.contains_key(&ip) {
            // Update existing block
            if let Some(blocked) = self.blocked_ips.get_mut(&ip) {
                blocked.block_count += 1;
                blocked.expires_at = Some(expires_at);
            }
            return Ok(());
        }

        // Add temporary block rule
        let rule = format!("-s {} -j DROP", ip);
        self.add_rule("INPUT", &rule)?;

        // Track blocked IP
        let blocked_ip = BlockedIp {
            ip,
            blocked_at: Instant::now(),
            expires_at: Some(expires_at),
            reason: "TEMPORARY_THREAT".to_string(),
            block_count: 1,
        };

        self.blocked_ips.insert(ip, blocked_ip);
        println!("⏱️  TEMPORARY BLOCK: {} - Duration: {:?}", ip, duration);

        Ok(())
    }

    pub fn rate_limit_ip(&mut self, ip: IpAddr, limit: u32, window: Duration) -> Result<(), Box<dyn std::error::Error>> {
        // Add rate limiting rule
        let window_secs = window.as_secs();
        let rule1 = format!("-s {} -m state --state NEW -m recent --set --name RATELIMIT_{}", ip, ip.to_string().replace(".", "_").replace(":", "_"));
        let rule2 = format!("-s {} -m state --state NEW -m recent --update --seconds {} --hitcount {} --name RATELIMIT_{} -j DROP", 
                           ip, window_secs, limit + 1, ip.to_string().replace(".", "_").replace(":", "_"));

        self.add_rule("INPUT", &rule1)?;
        self.add_rule("INPUT", &rule2)?;

        // Track rate limit
        let rate_limit = RateLimit {
            ip,
            limit,
            window,
            current_count: 0,
            window_start: Instant::now(),
        };

        self.rate_limits.insert(ip, rate_limit);
        println!("🚦 RATE LIMIT: {} - Max {} connections per {:?}", ip, limit, window);

        Ok(())
    }

    pub fn unblock_ip(&mut self, ip: IpAddr) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(_) = self.blocked_ips.remove(&ip) {
            // Remove block rule
            let rule = format!("-s {} -j DROP", ip);
            self.remove_rule_by_content(&rule)?;
            
            println!("✅ UNBLOCKED: {} - Removed from firewall", ip);
        }

        // Also remove rate limiting rules
        if let Some(_) = self.rate_limits.remove(&ip) {
            let ip_safe = ip.to_string().replace(".", "_").replace(":", "_");
            let _ = self.remove_rule_by_content(&format!("-s {} -m state --state NEW -m recent --set --name RATELIMIT_{}", ip, ip_safe));
            let _ = self.remove_rule_by_content(&format!("-s {} -m state --state NEW -m recent", ip));
        }

        Ok(())
    }

    fn remove_rule_by_content(&mut self, rule_content: &str) -> Result<(), Box<dyn std::error::Error>> {
        // Find rule by content and remove it
        let mut rules_to_remove = Vec::new();
        
        for (index, rule) in self.active_rules.iter().enumerate() {
            if rule.rule.contains(rule_content) || rule_content.contains(&rule.rule) {
                rules_to_remove.push((index, rule.clone()));
            }
        }

        // Remove rules in reverse order to maintain indices
        for (_, rule) in rules_to_remove.iter().rev() {
            let mut cmd = Command::new(&self.iptables_path);
            cmd.args(&["-D", &rule.chain]);
            
            for param in rule.rule.split_whitespace() {
                cmd.arg(param);
            }

            let _ = cmd.output(); // Ignore errors during removal
        }

        // Remove from our tracking
        self.active_rules.retain(|rule| !rule.rule.contains(rule_content) && !rule_content.contains(&rule.rule));

        Ok(())
    }

    pub fn cleanup_expired_blocks(&mut self) -> Result<u32, Box<dyn std::error::Error>> {
        let now = Instant::now();
        let mut expired_ips = Vec::new();

        // Find expired blocks
        for (ip, blocked) in &self.blocked_ips {
            if let Some(expires_at) = blocked.expires_at {
                if now >= expires_at {
                    expired_ips.push(*ip);
                }
            }
        }

        // Remove expired blocks
        let count = expired_ips.len() as u32;
        for ip in expired_ips {
            self.unblock_ip(ip)?;
        }

        if count > 0 {
            println!("🕒 Cleaned up {} expired IP blocks", count);
        }

        Ok(count)
    }

    pub fn get_blocked_ips(&self) -> Vec<(IpAddr, &BlockedIp)> {
        self.blocked_ips.iter().map(|(ip, blocked)| (*ip, blocked)).collect()
    }

    pub fn get_active_rules_count(&self) -> usize {
        self.active_rules.len()
    }

    pub fn get_firewall_stats(&self) -> std::collections::HashMap<String, u32> {
        let mut stats = std::collections::HashMap::new();
        
        stats.insert("total_rules".to_string(), self.active_rules.len() as u32);
        stats.insert("blocked_ips".to_string(), self.blocked_ips.len() as u32);
        stats.insert("rate_limited_ips".to_string(), self.rate_limits.len() as u32);
        
        let permanent_blocks = self.blocked_ips.values()
            .filter(|blocked| blocked.expires_at.is_none())
            .count() as u32;
        stats.insert("permanent_blocks".to_string(), permanent_blocks);
        
        let temporary_blocks = self.blocked_ips.values()
            .filter(|blocked| blocked.expires_at.is_some())
            .count() as u32;
        stats.insert("temporary_blocks".to_string(), temporary_blocks);

        stats
    }

    pub fn emergency_lockdown(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        println!("🚨 EMERGENCY LOCKDOWN ACTIVATED");

        // Block all new connections except from localhost
        self.add_rule("INPUT", "-s 127.0.0.1 -j ACCEPT")?;
        self.add_rule("INPUT", "-s ::1 -j ACCEPT")?;
        self.add_rule("INPUT", "-m state --state NEW -j LOG --log-prefix 'ASTRA-LOCKDOWN: '")?;
        self.add_rule("INPUT", "-m state --state NEW -j DROP")?;

        println!("🔒 Emergency lockdown complete - Only localhost connections allowed");
        Ok(())
    }

    pub fn disable_lockdown(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        println!("🔓 Disabling emergency lockdown...");

        // Remove lockdown rules
        self.remove_rule_by_content("-m state --state NEW -j DROP")?;
        self.remove_rule_by_content("-m state --state NEW -j LOG --log-prefix 'ASTRA-LOCKDOWN: '")?;

        println!("✅ Emergency lockdown disabled");
        Ok(())
    }

    pub fn backup_and_restore(&mut self, restore: bool) -> Result<(), Box<dyn std::error::Error>> {
        if restore && self.backup_created {
            println!("🔄 Restoring firewall rules from backup...");
            
            // Find the most recent backup
            let backup_dir = "/etc/astra";
            if let Ok(entries) = std::fs::read_dir(backup_dir) {
                let mut backup_files: Vec<_> = entries
                    .filter_map(|entry| entry.ok())
                    .filter(|entry| {
                        entry.file_name().to_string_lossy().starts_with("firewall_backup_")
                    })
                    .collect();
                
                backup_files.sort_by_key(|entry| {
                    entry.metadata().and_then(|m| m.modified()).unwrap_or(std::time::UNIX_EPOCH)
                });
                
                if let Some(latest_backup) = backup_files.last() {
                    let backup_path = latest_backup.path();
                    println!("📂 Restoring from: {:?}", backup_path);
                    
                    // Flush current rules
                    let _ = Command::new(&self.iptables_path).args(&["-F"]).output();
                    
                    // Restore from backup
                    let _ = Command::new(&self.iptables_path)
                        .args(&["-restore"])
                        .arg(&backup_path)
                        .output();
                    
                    self.active_rules.clear();
                    self.blocked_ips.clear();
                    self.rate_limits.clear();
                    
                    println!("✅ Firewall rules restored from backup");
                }
            }
        } else {
            self.backup_current_rules()?;
        }

        Ok(())
    }

    pub fn flush_all_rules(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        println!("🧹 Flushing all ASTRA firewall rules...");

        // Remove only our rules (those with ASTRA comments)
        for rule in &self.active_rules {
            let mut cmd = Command::new(&self.iptables_path);
            cmd.args(&["-D", &rule.chain]);
            
            for param in rule.rule.split_whitespace() {
                cmd.arg(param);
            }
            
            let _ = cmd.output(); // Ignore errors
        }

        self.active_rules.clear();
        self.blocked_ips.clear();
        self.rate_limits.clear();

        println!("✅ All ASTRA firewall rules flushed");
        Ok(())
    }

    pub fn is_ip_blocked(&self, ip: IpAddr) -> bool {
        self.blocked_ips.contains_key(&ip)
    }

    pub fn is_ip_rate_limited(&self, ip: IpAddr) -> bool {
        self.rate_limits.contains_key(&ip)
    }

    pub fn get_block_info(&self, ip: IpAddr) -> Option<&BlockedIp> {
        self.blocked_ips.get(&ip)
    }

    pub fn add_whitelist_rule(&mut self, ip: IpAddr) -> Result<(), Box<dyn std::error::Error>> {
        let rule = format!("-s {} -j ACCEPT", ip);
        self.add_rule("INPUT", &rule)?;
        println!("✅ WHITELISTED: {} - Permanent access granted", ip);
        Ok(())
    }

    pub fn remove_whitelist_rule(&mut self, ip: IpAddr) -> Result<(), Box<dyn std::error::Error>> {
        let rule = format!("-s {} -j ACCEPT", ip);
        self.remove_rule_by_content(&rule)?;
        println!("❌ WHITELIST REMOVED: {}", ip);
        Ok(())
    }

    pub fn get_connection_count(&self, ip: IpAddr) -> Result<u32, Box<dyn std::error::Error>> {
        // Use netstat to count active connections from IP
        let output = Command::new("netstat")
            .args(&["-tn"])
            .output()?;

        let netstat_output = String::from_utf8_lossy(&output.stdout);
        let count = netstat_output
            .lines()
            .filter(|line| line.contains(&ip.to_string()))
            .count() as u32;

}

impl Drop for Firewall {
    fn drop(&mut self) {
        println!("🔥 Firewall module shutting down...");
        
        // Option to clean up rules on shutdown (configurable)
        if !self.config.firewall.auto_rules {
            if let Err(e) = self.flush_all_rules() {
                println!("⚠️  Warning: Could not clean up firewall rules: {}", e);
            }
        }
        
        println!("✅ Firewall module shutdown complete");
    }
}