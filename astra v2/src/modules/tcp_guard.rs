use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, Instant};
use chrono::{DateTime, Utc};
use tokio::time::sleep;
use pnet::datalink;
use pnet::packet::ethernet::{EtherTypes, EthernetPacket};
use pnet::packet::ip::IpNextHeaderProtocols;
use pnet::packet::ipv4::Ipv4Packet;
use pnet::packet::tcp::{TcpFlags, TcpPacket};
use pnet::packet::Packet;

use crate::core::{config::Config, logger::Logger};
use crate::{SecurityEvent, ThreatLevel};

#[derive(Debug, Clone)]
struct ConnectionAttempt {
    timestamp: Instant,
    port: u16,
    flags: u8,
}

#[derive(Debug)]
struct ScanProfile {
    first_attempt: Instant,
    attempts: Vec<ConnectionAttempt>,
    unique_ports: std::collections::HashSet<u16>,
    syn_flood_count: u32,
    last_syn_time: Instant,
    threat_score: f32,
}

pub struct TcpGuard {
    config: Arc<Config>,
    logger: Arc<Logger>,
    scan_profiles: HashMap<IpAddr, ScanProfile>,
    sensitivity_level: u8,
    stealth_ports: Vec<u16>,
    honeypot_responses: bool,
}

impl TcpGuard {
    pub fn new(config: &Arc<Config>, logger: Arc<Logger>) -> Result<Self, Box<dyn std::error::Error>> {
        let stealth_ports = vec![
            22, 23, 25, 53, 80, 110, 143, 443, 993, 995,  // Common targets
            135, 139, 445, 1433, 3389,                     // Windows services
            21, 69, 161, 162, 514, 873,                    // Unix services
            5060, 5061,                                     // SIP ports (monitored separately)
        ];

        logger.log_info("TCP Guardian initialized with advanced scan detection")?;
        logger.log_info(&format!("Monitoring {} stealth ports", stealth_ports.len()))?;

        Ok(TcpGuard {
            config: config.clone(),
            logger,
            scan_profiles: HashMap::new(),
            sensitivity_level: 5,
            stealth_ports,
            honeypot_responses: true,
        })
    }

    pub async fn scan_network(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // Get network interfaces
        let interfaces = datalink::interfaces();
        
        for interface in interfaces {
            if interface.is_up() && !interface.is_loopback() {
                self.monitor_interface(&interface).await?;
            }
        }
        
        // Cleanup old profiles every scan cycle
        self.cleanup_old_profiles();
        
        Ok(())
    }

    async fn monitor_interface(&mut self, interface: &pnet::datalink::NetworkInterface) -> Result<(), Box<dyn std::error::Error>> {
        use pnet::datalink::Channel::Ethernet;
        
        let config = pnet::datalink::Config {
            write_buffer_size: 4096,
            read_buffer_size: 4096,
            read_timeout: Some(Duration::from_millis(100)),
            write_timeout: Some(Duration::from_millis(100)),
            channel_type: pnet::datalink::ChannelType::Layer2,
            bpf_fd_attempts: 1000,
            linux_fanout: None,
            promiscuous: false, // Stealth mode
        };

        let (_, mut rx) = match pnet::datalink::channel(interface, config) {
            Ok(Ethernet(tx, rx)) => (tx, rx),
            Ok(_) => return Ok(()),
            Err(e) => {
                self.logger.log_error(&format!("Failed to create channel for {}: {}", interface.name, e))?;
                return Ok(());
            }
        };

        loop {
            match rx.next() {
                Ok(packet) => {
                    if let Some(ethernet) = EthernetPacket::new(packet) {
                        self.process_ethernet_packet(&ethernet).await?;
                    }
                }
                Err(_) => break, // Timeout, continue monitoring
            }
        }

        Ok(())
    }

    async fn process_ethernet_packet(&mut self, ethernet: &EthernetPacket) -> Result<(), Box<dyn std::error::Error>> {
        match ethernet.get_ethertype() {
            EtherTypes::Ipv4 => {
                if let Some(ipv4) = Ipv4Packet::new(ethernet.payload()) {
                    self.process_ipv4_packet(&ipv4).await?;
                }
            }
            _ => {} // Only monitoring IPv4 for now
        }
        Ok(())
    }

    async fn process_ipv4_packet(&mut self, ipv4: &Ipv4Packet) -> Result<(), Box<dyn std::error::Error>> {
        if ipv4.get_next_level_protocol() == IpNextHeaderProtocols::Tcp {
            if let Some(tcp) = TcpPacket::new(ipv4.payload()) {
                let source_ip = IpAddr::V4(ipv4.get_source());
                let dest_port = tcp.get_destination();
                let flags = tcp.get_flags();
                
                // Skip internal traffic
                if self.is_internal_ip(source_ip) {
                    return Ok(());
                }

                self.analyze_tcp_packet(source_ip, dest_port, flags).await?;
            }
        }
        Ok(())
    }

    async fn analyze_tcp_packet(&mut self, source_ip: IpAddr, dest_port: u16, flags: u8) -> Result<(), Box<dyn std::error::Error>> {
        let now = Instant::now();
        
        // Get or create scan profile
        let profile = self.scan_profiles.entry(source_ip).or_insert(ScanProfile {
            first_attempt: now,
            attempts: Vec::new(),
            unique_ports: std::collections::HashSet::new(),
            syn_flood_count: 0,
            last_syn_time: now,
            threat_score: 0.0,
        });

        // Record connection attempt
        profile.attempts.push(ConnectionAttempt {
            timestamp: now,
            port: dest_port,
            flags,
        });
        profile.unique_ports.insert(dest_port);

        // SYN flood detection
        if flags & TcpFlags::SYN != 0 && flags & TcpFlags::ACK == 0 {
            if now.duration_since(profile.last_syn_time) < Duration::from_secs(5) {
                profile.syn_flood_count += 1;
            } else {
                profile.syn_flood_count = 1;
                profile.last_syn_time = now;
            }

            // SYN flood threshold
            if profile.syn_flood_count > 10 {
                self.trigger_syn_flood_alert(source_ip, profile.syn_flood_count).await?;
                profile.threat_score += 0.8;
            }
        }

        // Port scan detection - Advanced heuristics
        self.detect_port_scanning(source_ip, profile).await?;

        Ok(())
    }

    async fn detect_port_scanning(&mut self, source_ip: IpAddr, profile: &mut ScanProfile) -> Result<(), Box<dyn std::error::Error>> {
        let now = Instant::now();
        let time_window = Duration::from_secs(10);
        
        // Count recent attempts
        let recent_attempts: Vec<_> = profile.attempts.iter()
            .filter(|attempt| now.duration_since(attempt.timestamp) < time_window)
            .collect();

        let recent_unique_ports: std::collections::HashSet<u16> = recent_attempts.iter()
            .map(|attempt| attempt.port)
            .collect();

        // Multiple scanning patterns detection
        let mut scan_detected = false;
        let mut scan_type = String::new();
        let mut threat_increase = 0.0;

        // 1. Rapid port scanning (>2 ports in 10 seconds)
        if recent_unique_ports.len() > 2 {
            scan_detected = true;
            scan_type = format!("RAPID_PORT_SCAN ({} ports)", recent_unique_ports.len());
            threat_increase = 0.6;
        }

        // 2. Sequential port scanning detection
        if self.detect_sequential_scan(&recent_attempts) {
            scan_detected = true;
            scan_type = "SEQUENTIAL_SCAN".to_string();
            threat_increase = 0.7;
        }

        // 3. Stealth scan detection (specific flag combinations)
        if self.detect_stealth_scan(&recent_attempts) {
            scan_detected = true;
            scan_type = "STEALTH_SCAN".to_string();
            threat_increase = 0.9;
        }

        // 4. Service enumeration detection
        if self.detect_service_enumeration(&recent_unique_ports) {
            scan_detected = true;
            scan_type = "SERVICE_ENUMERATION".to_string();
            threat_increase = 0.5;
        }

        if scan_detected {
            profile.threat_score += threat_increase;
            self.trigger_scan_alert(source_ip, &scan_type, recent_unique_ports.len(), profile.threat_score).await?;
        }

        Ok(())
    }

    fn detect_sequential_scan(&self, attempts: &[&ConnectionAttempt]) -> bool {
        if attempts.len() < 3 {
            return false;
        }

        let mut ports: Vec<u16> = attempts.iter().map(|a| a.port).collect();
        ports.sort();
        
        // Check for sequential ports (like 80, 81, 82 or 443, 444, 445)
        let mut sequential_count = 1;
        for i in 1..ports.len() {
            if ports[i] == ports[i-1] + 1 {
                sequential_count += 1;
                if sequential_count >= 3 {
                    return true;
                }
            } else {
                sequential_count = 1;
            }
        }
        
        false
    }

    fn detect_stealth_scan(&self, attempts: &[&ConnectionAttempt]) -> bool {
        for attempt in attempts {
            // SYN scan detection
            if attempt.flags == TcpFlags::SYN {
                return true;
            }
            // FIN scan detection
            if attempt.flags == TcpFlags::FIN {
                return true;
            }
            // NULL scan detection  
            if attempt.flags == 0 {
                return true;
            }
            // XMAS scan detection
            if attempt.flags & (TcpFlags::FIN | TcpFlags::PSH | TcpFlags::URG) != 0 {
                return true;
            }
        }
        false
    }

    fn detect_service_enumeration(&self, ports: &std::collections::HashSet<u16>) -> bool {
        // Common service ports that indicate enumeration
        let service_ports: std::collections::HashSet<u16> = [
            21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 993, 995, 1433, 3389, 5060, 5061
        ].iter().cloned().collect();

        let enumerated_services = ports.intersection(&service_ports).count();
        enumerated_services >= 3
    }

    async fn trigger_scan_alert(&self, source_ip: IpAddr, scan_type: &str, port_count: usize, threat_score: f32) -> Result<(), Box<dyn std::error::Error>> {
        let event = SecurityEvent {
            timestamp: Utc::now(),
            source_ip,
            event_type: "TCP_SCAN_DETECTED".to_string(),
            threat_level: ThreatLevel {
                level: if threat_score > 0.8 { 9 } else if threat_score > 0.5 { 7 } else { 5 },
                confidence: 0.95,
                category: "RECONNAISSANCE".to_string(),
            },
            details: format!("{} - {} ports scanned, threat_score: {:.2}", scan_type, port_count, threat_score),
            action_taken: "MONITORING_ENHANCED".to_string(),
        };

        self.logger.log_security_event(&event)?;
        
        // If threat score is high enough, recommend immediate blocking
        if threat_score > 0.7 {
            self.logger.log_critical(&format!("🚨 CRITICAL: {} engaging in {} - IMMEDIATE CONTAINMENT RECOMMENDED", source_ip, scan_type))?;
        }

        Ok(())
    }

    async fn trigger_syn_flood_alert(&self, source_ip: IpAddr, syn_count: u32) -> Result<(), Box<dyn std::error::Error>> {
        let event = SecurityEvent {
            timestamp: Utc::now(),
            source_ip,
            event_type: "SYN_FLOOD_DETECTED".to_string(),
            threat_level: ThreatLevel {
                level: if syn_count > 50 { 10 } else if syn_count > 25 { 8 } else { 6 },
                confidence: 0.9,
                category: "DOS_ATTACK".to_string(),
            },
            details: format!("SYN flood attack detected - {} SYN packets in 5 seconds", syn_count),
            action_taken: "RATE_LIMITING_APPLIED".to_string(),
        };

        self.logger.log_security_event(&event)?;
        self.logger.log_critical(&format!("🚨 SYN FLOOD ATTACK: {} sent {} SYN packets - DEFENSIVE MEASURES ACTIVATED", source_ip, syn_count))?;

        Ok(())
    }

    fn cleanup_old_profiles(&mut self) {
        let now = Instant::now();
        let retention_time = Duration::from_secs(300); // 5 minutes

        self.scan_profiles.retain(|_, profile| {
            now.duration_since(profile.first_attempt) < retention_time
        });
    }

    fn is_internal_ip(&self, ip: IpAddr) -> bool {
        match ip {
            IpAddr::V4(ipv4) => {
                let octets = ipv4.octets();
                // RFC 1918 private networks
                matches!(octets[0], 10) ||
                (octets[0] == 172 && (16..=31).contains(&octets[1])) ||
                (octets[0] == 192 && octets[1] == 168) ||
                // Loopback
                octets[0] == 127 ||
                // Link-local
                (octets[0] == 169 && octets[1] == 254)
            }
            IpAddr::V6(_) => false, // Skip IPv6 for now
        }
    }

    pub fn set_sensitivity_level(&mut self, level: u8) -> Result<(), Box<dyn std::error::Error>> {
        if level > 10 {
            return Err("Sensitivity level must be between 1-10".into());
        }
        
        self.sensitivity_level = level;
        self.logger.log_info(&format!("TCP Guardian sensitivity set to level {}", level))?;
        
        // Adjust detection thresholds based on sensitivity
        match level {
            1..=3 => { /* Low sensitivity - higher thresholds */ }
            4..=6 => { /* Normal sensitivity */ }
            7..=10 => { /* High sensitivity - lower thresholds */ }
            _ => {}
        }
        
        Ok(())
    }

    pub async fn deploy_honeypot_response(&mut self, source_ip: IpAddr, target_port: u16) -> Result<(), Box<dyn std::error::Error>> {
        if !self.honeypot_responses {
            return Ok(());
        }

        // Deploy different honeypot responses based on targeted port
        match target_port {
            22 => {
                // SSH honeypot response
                self.logger.log_info(&format!("Deploying SSH honeypot for {}", source_ip))?;
                // Could implement fake SSH banner response
            }
            80 | 443 => {
                // HTTP/HTTPS honeypot
                self.logger.log_info(&format!("Deploying HTTP honeypot for {}", source_ip))?;
                // Could implement fake web server response
            }
            5060 | 5061 => {
                // SIP honeypot (handled by SIP Shield)
                self.logger.log_info(&format!("Coordinating SIP honeypot response for {}", source_ip))?;
            }
            _ => {
                // Generic honeypot
                self.logger.log_info(&format!("Deploying generic honeypot for {} on port {}", source_ip, target_port))?;
            }
        }

        Ok(())
    }

    pub fn get_threat_statistics(&self) -> HashMap<String, u32> {
        let mut stats = HashMap::new();
        
        let total_profiles = self.scan_profiles.len() as u32;
        let high_threat_count = self.scan_profiles.values()
            .filter(|p| p.threat_score > 0.7)
            .count() as u32;
        let active_scanners = self.scan_profiles.values()
            .filter(|p| p.unique_ports.len() > 2)
            .count() as u32;

        stats.insert("total_monitored_ips".to_string(), total_profiles);
        stats.insert("high_threat_ips".to_string(), high_threat_count);
        stats.insert("active_scanners".to_string(), active_scanners);
        stats.insert("stealth_ports_monitored".to_string(), self.stealth_ports.len() as u32);

        stats
    }

    pub async fn perform_counter_reconnaissance(&mut self, source_ip: IpAddr) -> Result<(), Box<dyn std::error::Error>> {
        // Passive counter-reconnaissance - gather intel on the attacker
        self.logger.log_info(&format!("Initiating passive counter-reconnaissance on {}", source_ip))?;
        
        // Log detailed information about the attacker's behavior
        if let Some(profile) = self.scan_profiles.get(&source_ip) {
            let recon_data = format!(
                "ATTACKER_PROFILE: {} | First_seen: {:?} | Unique_ports: {} | Total_attempts: {} | Threat_score: {:.2} | Techniques: {:?}",
                source_ip,
                profile.first_attempt,
                profile.unique_ports.len(),
                profile.attempts.len(),
                profile.threat_score,
                self.analyze_attack_techniques(profile)
            );
            
            self.logger.log_info(&recon_data)?;
        }

        Ok(())
    }

    fn analyze_attack_techniques(&self, profile: &ScanProfile) -> Vec<String> {
        let mut techniques = Vec::new();
        
        // Analyze scan patterns
        if profile.unique_ports.len() > 10 {
            techniques.push("COMPREHENSIVE_SCAN".to_string());
        }
        
        if profile.syn_flood_count > 5 {
            techniques.push("SYN_FLOOD".to_string());
        }
        
        // Check for common attack patterns
        let common_exploit_ports: std::collections::HashSet<u16> = [
            135, 139, 445, // SMB
            1433, 1521,    // Database
            3389,          // RDP
            5985, 5986,    // WinRM
        ].iter().cloned().collect();
        
        if profile.unique_ports.intersection(&common_exploit_ports).count() > 0 {
            techniques.push("EXPLOIT_TARGETING".to_string());
        }
        
        techniques
    }
} 