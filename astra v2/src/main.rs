use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};
use tokio::time::sleep;
use serde_json;
use chrono::{DateTime, Utc};

mod modules;
mod core;

use modules::{tcp_guard::TcpGuard, sip_shield::SipShield};
use core::{firewall::Firewall, logger::Logger, config::Config};

#[derive(Debug, Clone)]
pub struct ThreatLevel {
    pub level: u8,        // 1-10 severity
    pub confidence: f32,  // 0.0-1.0 confidence
    pub category: String,
}

#[derive(Debug, Clone)]
pub struct SecurityEvent {
    pub timestamp: DateTime<Utc>,
    pub source_ip: IpAddr,
    pub event_type: String,
    pub threat_level: ThreatLevel,
    pub details: String,
    pub action_taken: String,
}

pub struct AstraEngine {
    config: Arc<Config>,
    firewall: Arc<Mutex<Firewall>>,
    logger: Arc<Logger>,
    tcp_guard: Arc<Mutex<TcpGuard>>,
    sip_shield: Arc<Mutex<SipShield>>,
    threat_intelligence: Arc<Mutex<HashMap<IpAddr, ThreatProfile>>>,
    running: Arc<Mutex<bool>>,
}

#[derive(Debug, Clone)]
struct ThreatProfile {
    first_seen: DateTime<Utc>,
    last_activity: DateTime<Utc>,
    threat_score: f32,
    events_count: u32,
    blocked: bool,
    auto_unblock_time: Option<DateTime<Utc>>,
}

impl AstraEngine {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let config = Arc::new(Config::load()?);
        let logger = Arc::new(Logger::new(&config)?);
        let firewall = Arc::new(Mutex::new(Firewall::new(&config)?));
        let tcp_guard = Arc::new(Mutex::new(TcpGuard::new(&config, logger.clone())?));
        let sip_shield = Arc::new(Mutex::new(SipShield::new(&config, logger.clone())?));
        let threat_intelligence = Arc::new(Mutex::new(HashMap::new()));
        let running = Arc::new(Mutex::new(false));

        logger.log_info("ASTRA Defense Engine initialized - OPERATIONAL STATUS: GREEN")?;
        
        Ok(AstraEngine {
            config,
            firewall,
            logger,
            tcp_guard,
            sip_shield,
            threat_intelligence,
            running,
        })
    }

    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        {
            let mut running = self.running.lock().unwrap();
            if *running {
                return Err("ASTRA Engine already running".into());
            }
            *running = true;
        }

        self.logger.log_critical("🛡️  ASTRA DEFENSE ENGINE - ACTIVATION SEQUENCE INITIATED")?;
        self.logger.log_info("Deploying stealth protection protocols...")?;

        // Initialize stealth mode
        self.initialize_stealth_mode().await?;

        // Start core modules
        self.start_modules().await?;

        // Start main defense loop
        self.start_defense_loop().await?;

        Ok(())
    }

    async fn initialize_stealth_mode(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.logger.log_info("Activating stealth mode - ghost protocol engaged")?;
        
        let mut firewall = self.firewall.lock().unwrap();
        
        // Drop all ICMP ping responses
        firewall.add_stealth_rule("INPUT", "-p icmp --icmp-type echo-request -j DROP")?;
        
        // Drop TCP RST packets that could reveal open ports
        firewall.add_stealth_rule("INPUT", "-p tcp --tcp-flags RST RST -j DROP")?;
        
        // Drop all unsolicited SYN packets to closed ports (stealth scan protection)
        firewall.add_stealth_rule("INPUT", "-p tcp --syn -m state --state NEW -j LOG --log-prefix 'ASTRA-SCAN-DETECT: '")?;
        firewall.add_stealth_rule("INPUT", "-p tcp --syn -m state --state NEW -j DROP")?;
        
        // Allow only established connections and SIP legitimate traffic
        firewall.add_rule("INPUT", "-m state --state ESTABLISHED,RELATED -j ACCEPT")?;
        
        self.logger.log_info("Stealth mode activated - system now invisible to reconnaissance")?;
        Ok(())
    }

    async fn start_modules(&self) -> Result<(), Box<dyn std::error::Error>> {
        let tcp_guard = self.tcp_guard.clone();
        let sip_shield = self.sip_shield.clone();
        let running = self.running.clone();
        let logger = self.logger.clone();

        // TCP Guardian Thread
        let tcp_running = running.clone();
        let tcp_logger = logger.clone();
        tokio::spawn(async move {
            tcp_logger.log_info("TCP Guardian module - ACTIVE").unwrap();
            while *tcp_running.lock().unwrap() {
                if let Ok(mut guard) = tcp_guard.lock() {
                    if let Err(e) = guard.scan_network().await {
                        tcp_logger.log_error(&format!("TCP Guardian error: {}", e)).unwrap();
                    }
                }
                sleep(Duration::from_millis(100)).await;
            }
        });

        // SIP Shield Thread
        let sip_running = running.clone();
        let sip_logger = logger.clone();
        tokio::spawn(async move {
            sip_logger.log_info("SIP Shield module - ACTIVE").unwrap();
            while *sip_running.lock().unwrap() {
                if let Ok(mut shield) = sip_shield.lock() {
                    if let Err(e) = shield.monitor_sip_traffic().await {
                        sip_logger.log_error(&format!("SIP Shield error: {}", e)).unwrap();
                    }
                }
                sleep(Duration::from_millis(50)).await;
            }
        });

        self.logger.log_info("All defense modules deployed and operational")?;
        Ok(())
    }

    async fn start_defense_loop(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.logger.log_info("Main defense loop - ENGAGED")?;
        
        let mut cleanup_timer = Instant::now();
        
        while *self.running.lock().unwrap() {
            // Threat intelligence analysis every 5 seconds
            self.analyze_threat_intelligence().await?;
            
            // Cleanup expired blocks every 60 seconds
            if cleanup_timer.elapsed() > Duration::from_secs(60) {
                self.cleanup_expired_blocks().await?;
                cleanup_timer = Instant::now();
            }
            
            // Adaptive response calibration
            self.calibrate_defense_systems().await?;
            
            sleep(Duration::from_secs(1)).await;
        }
        
        Ok(())
    }

    async fn analyze_threat_intelligence(&self) -> Result<(), Box<dyn std::error::Error>> {
        let mut ti = self.threat_intelligence.lock().unwrap();
        let now = Utc::now();
        
        // Update threat scores based on activity patterns
        for (ip, profile) in ti.iter_mut() {
            let time_since_last = now.signed_duration_since(profile.last_activity);
            let hours_elapsed = time_since_last.num_hours() as f32;
            
            // Decay threat score over time (rehabilitative approach)
            if hours_elapsed > 1.0 {
                profile.threat_score *= 0.95_f32.powf(hours_elapsed / 24.0);
            }
            
            // Adaptive blocking based on threat evolution
            if profile.threat_score > 0.8 && !profile.blocked {
                self.execute_adaptive_block(*ip, profile.threat_score).await?;
                profile.blocked = true;
                profile.auto_unblock_time = Some(now + chrono::Duration::hours(
                    (profile.threat_score * 12.0) as i64
                ));
            }
        }
        
        Ok(())
    }

    async fn execute_adaptive_block(&self, ip: IpAddr, threat_score: f32) -> Result<(), Box<dyn std::error::Error>> {
        let mut firewall = self.firewall.lock().unwrap();
        
        if threat_score > 0.9 {
            // High threat: Complete blackhole
            firewall.block_ip_permanent(ip)?;
            self.logger.log_critical(&format!("🚨 HIGH THREAT NEUTRALIZED: {} - PERMANENT BLACKHOLE", ip))?;
        } else if threat_score > 0.7 {
            // Medium threat: Temporary aggressive block
            firewall.block_ip_temporary(ip, Duration::from_hours(6))?;
            self.logger.log_warning(&format!("⚠️  MEDIUM THREAT CONTAINED: {} - 6H QUARANTINE", ip))?;
        } else {
            // Low threat: Rate limiting
            firewall.rate_limit_ip(ip, 10, Duration::from_minutes(5))?;
            self.logger.log_info(&format!("📊 LOW THREAT MANAGED: {} - RATE LIMITED", ip))?;
        }
        
        Ok(())
    }

    async fn cleanup_expired_blocks(&self) -> Result<(), Box<dyn std::error::Error>> {
        let mut ti = self.threat_intelligence.lock().unwrap();
        let now = Utc::now();
        let mut unblocked_count = 0;
        
        for (ip, profile) in ti.iter_mut() {
            if profile.blocked {
                if let Some(unblock_time) = profile.auto_unblock_time {
                    if now > unblock_time {
                        let mut firewall = self.firewall.lock().unwrap();
                        firewall.unblock_ip(*ip)?;
                        profile.blocked = false;
                        profile.auto_unblock_time = None;
                        unblocked_count += 1;
                    }
                }
            }
        }
        
        if unblocked_count > 0 {
            self.logger.log_info(&format!("Auto-rehabilitated {} IP addresses", unblocked_count))?;
        }
        
        Ok(())
    }

    async fn calibrate_defense_systems(&self) -> Result<(), Box<dyn std::error::Error>> {
        // Dynamic calibration based on current threat landscape
        let ti = self.threat_intelligence.lock().unwrap();
        let active_threats = ti.values().filter(|p| p.blocked).count();
        
        if active_threats > 100 {
            // High threat environment - increase sensitivity
            if let Ok(mut tcp_guard) = self.tcp_guard.lock() {
                tcp_guard.set_sensitivity_level(9)?;
            }
            if let Ok(mut sip_shield) = self.sip_shield.lock() {
                sip_shield.set_sensitivity_level(9)?;
            }
            self.logger.log_warning("Defense systems calibrated to HIGH ALERT due to threat density")?;
        } else if active_threats < 10 {
            // Low threat environment - normal sensitivity
            if let Ok(mut tcp_guard) = self.tcp_guard.lock() {
                tcp_guard.set_sensitivity_level(5)?;
            }
            if let Ok(mut sip_shield) = self.sip_shield.lock() {
                sip_shield.set_sensitivity_level(5)?;
            }
        }
        
        Ok(())
    }

    pub fn register_security_event(&self, event: SecurityEvent) -> Result<(), Box<dyn std::error::Error>> {
        // Update threat intelligence
        {
            let mut ti = self.threat_intelligence.lock().unwrap();
            let profile = ti.entry(event.source_ip).or_insert(ThreatProfile {
                first_seen: event.timestamp,
                last_activity: event.timestamp,
                threat_score: 0.0,
                events_count: 0,
                blocked: false,
                auto_unblock_time: None,
            });
            
            profile.last_activity = event.timestamp;
            profile.events_count += 1;
            
            // Calculate threat score increase based on event severity
            let score_increase = match event.threat_level.level {
                1..=3 => 0.1,
                4..=6 => 0.25,
                7..=8 => 0.5,
                9..=10 => 0.8,
                _ => 0.05,
            } * event.threat_level.confidence;
            
            profile.threat_score = (profile.threat_score + score_increase).min(1.0);
        }
        
        // Log the event
        self.logger.log_security_event(&event)?;
        
        Ok(())
    }

    pub async fn shutdown(&self) -> Result<(), Box<dyn std::error::Error>> {
        self.logger.log_critical("ASTRA Defense Engine - SHUTDOWN SEQUENCE INITIATED")?;
        
        {
            let mut running = self.running.lock().unwrap();
            *running = false;
        }
        
        // Graceful cleanup
        sleep(Duration::from_secs(2)).await;
        
        self.logger.log_info("All defense systems disengaged - ASTRA offline")?;
        
        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // ASCII Banner
    println!(r#"
    ░█████╗░░██████╗████████╗██████╗░░█████╗░
    ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗
    ███████║╚█████╗░░░░██║░░░██████╔╝███████║
    ██╔══██║░╚═══██╗░░░██║░░░██╔══██╗██╔══██║
    ██║░░██║██████╔╝░░░██║░░░██║░░██║██║░░██║
    ╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝
    
    ADVANCED STEALTH THREAT RESPONSE ARCHITECTURE
    Military-Grade Network Defense Engine v1.0
    "#);

    println!("🔐 Initializing ASTRA Defense Systems...");
    
    // Check for root privileges
    if !is_root() {
        eprintln!("❌ ASTRA requires root privileges for network defense operations");
        std::process::exit(1);
    }
    
    // Initialize and start ASTRA
    let astra = AstraEngine::new()?;
    
    // Handle graceful shutdown
    let astra_clone = Arc::new(astra);
    let shutdown_astra = astra_clone.clone();
    
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.expect("Failed to listen for Ctrl+C");
        println!("\n🛑 Shutdown signal received...");
        if let Err(e) = shutdown_astra.shutdown().await {
            eprintln!("Error during shutdown: {}", e);
        }
        std::process::exit(0);
    });
    
    // Start the defense engine
    astra_clone.start().await?;
    
    Ok(())
}

fn is_root() -> bool {
    unsafe { libc::getuid() == 0 }
}

// Cargo.toml dependencies:
/*
[package]
name = "astra"
version = "1.0.0"
edition = "2021"

[dependencies]
tokio = { version = "1.0", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }
regex = "1.0"
pcap = "1.0"
libc = "0.2"
netstat2 = "0.9"
pnet = "0.31"
log = "0.4"
env_logger = "0.10"
thiserror = "1.0"
anyhow = "1.0"
clap = { version = "4.0", features = ["derive"] }
*/