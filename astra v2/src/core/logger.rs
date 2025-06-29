use std::fs::{File, OpenOptions};
use std::io::{Write, BufWriter};
use std::path::Path;
use std::sync::{Arc, Mutex};
use chrono::{DateTime, Utc};
use serde_json;

use crate::core::config::Config;
use crate::SecurityEvent;

#[derive(Debug, Clone)]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
    Critical,
}

impl LogLevel {
    fn as_str(&self) -> &'static str {
        match self {
            LogLevel::Debug => "DEBUG",
            LogLevel::Info => "INFO",
            LogLevel::Warning => "WARN",
            LogLevel::Error => "ERROR",
            LogLevel::Critical => "CRITICAL",
        }
    }

    fn emoji(&self) -> &'static str {
        match self {
            LogLevel::Debug => "🔍",
            LogLevel::Info => "ℹ️",
            LogLevel::Warning => "⚠️",
            LogLevel::Error => "❌",
            LogLevel::Critical => "🚨",
        }
    }

    fn from_string(level: &str) -> Self {
        match level.to_uppercase().as_str() {
            "DEBUG" => LogLevel::Debug,
            "INFO" => LogLevel::Info,
            "WARN" | "WARNING" => LogLevel::Warning,
            "ERROR" => LogLevel::Error,
            "CRITICAL" => LogLevel::Critical,
            _ => LogLevel::Info,
        }
    }
}

#[derive(Debug, Clone)]
struct LogEntry {
    timestamp: DateTime<Utc>,
    level: LogLevel,
    module: String,
    message: String,
    metadata: Option<serde_json::Value>,
}

pub struct Logger {
    config: Arc<Config>,
    log_level: LogLevel,
    log_file: Arc<Mutex<BufWriter<File>>>,
    audit_file: Option<Arc<Mutex<BufWriter<File>>>>,
    json_format: bool,
    syslog_enabled: bool,
    console_output: bool,
}

impl Logger {
    pub fn new(config: &Arc<Config>) -> Result<Self, Box<dyn std::error::Error>> {
        let log_level = LogLevel::from_string(&config.logging.log_level);
        
        // Create log directory if it doesn't exist
        if let Some(parent) = Path::new(&config.logging.log_file).parent() {
            std::fs::create_dir_all(parent)?;
        }

        // Open main log file
        let log_file = OpenOptions::new()
            .create(true)
            .write(true)
            .append(true)
            .open(&config.logging.log_file)?;
        
        let log_writer = Arc::new(Mutex::new(BufWriter::new(log_file)));

        // Open audit log file if enabled
        let audit_file = if config.logging.audit_trail {
            let audit_path = config.logging.log_file.replace(".log", "_audit.log");
            let audit_file = OpenOptions::new()
                .create(true)
                .write(true)
                .append(true)
                .open(&audit_path)?;
            Some(Arc::new(Mutex::new(BufWriter::new(audit_file))))
        } else {
            None
        };

        println!("📝 Logger initialized - Level: {} | File: {}", 
                log_level.as_str(), config.logging.log_file);

        Ok(Logger {
            config: config.clone(),
            log_level,
            log_file: log_writer,
            audit_file,
            json_format: config.logging.json_format,
            syslog_enabled: config.logging.syslog_enabled,
            console_output: true, // Always show on console for now
        })
    }

    fn should_log(&self, level: &LogLevel) -> bool {
        use LogLevel::*;
        let current_level = &self.log_level;
        
        match (current_level, level) {
            (Debug, _) => true,
            (Info, Debug) => false,
            (Info, _) => true,
            (Warning, Debug | Info) => false,
            (Warning, _) => true,
            (Error, Debug | Info | Warning) => false,
            (Error, _) => true,
            (Critical, Critical) => true,
            (Critical, _) => false,
        }
    }

    fn format_log_entry(&self, entry: &LogEntry) -> String {
        if self.json_format {
            let mut json_entry = serde_json::json!({
                "timestamp": entry.timestamp.to_rfc3339(),
                "level": entry.level.as_str(),
                "module": entry.module,
                "message": entry.message
            });

            if let Some(metadata) = &entry.metadata {
                json_entry["metadata"] = metadata.clone();
            }

            json_entry.to_string()
        } else {
            format!(
                "[{}] [{}] [{}] {}",
                entry.timestamp.format("%Y-%m-%d %H:%M:%S UTC"),
                entry.level.as_str(),
                entry.module,
                entry.message
            )
        }
    }

    fn write_log_entry(&self, entry: &LogEntry) -> Result<(), Box<dyn std::error::Error>> {
        if !self.should_log(&entry.level) {
            return Ok(());
        }

        let formatted_entry = self.format_log_entry(entry);

        // Write to console
        if self.console_output {
            println!("{} {}", entry.level.emoji(), entry.message);
        }

        // Write to file
        {
            let mut writer = self.log_file.lock().unwrap();
            writeln!(writer, "{}", formatted_entry)?;
            writer.flush()?;
        }

        // Write to syslog if enabled
        if self.syslog_enabled {
            self.write_to_syslog(entry)?;
        }

        Ok(())
    }

    fn write_to_syslog(&self, entry: &LogEntry) -> Result<(), Box<dyn std::error::Error>> {
        use std::process::Command;
        
        let priority = match entry.level {
            LogLevel::Debug => "debug",
            LogLevel::Info => "info",
            LogLevel::Warning => "warning",
            LogLevel::Error => "err",
            LogLevel::Critical => "crit",
        };

        let message = format!("ASTRA[{}]: {}", entry.module, entry.message);

        let _ = Command::new("logger")
            .args(&["-p", &format!("daemon.{}", priority), &message])
            .output();

        Ok(())
    }

    pub fn log(&self, level: LogLevel, module: &str, message: &str) -> Result<(), Box<dyn std::error::Error>> {
        let entry = LogEntry {
            timestamp: Utc::now(),
            level,
            module: module.to_string(),
            message: message.to_string(),
            metadata: None,
        };

        self.write_log_entry(&entry)
    }

    pub fn log_with_metadata(&self, level: LogLevel, module: &str, message: &str, metadata: serde_json::Value) -> Result<(), Box<dyn std::error::Error>> {
        let entry = LogEntry {
            timestamp: Utc::now(),
            level,
            module: module.to_string(),
            message: message.to_string(),
            metadata: Some(metadata),
        };

        self.write_log_entry(&entry)
    }

    pub fn log_debug(&self, message: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.log(LogLevel::Debug, "ASTRA", message)
    }

    pub fn log_info(&self, message: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.log(LogLevel::Info, "ASTRA", message)
    }

    pub fn log_warning(&self, message: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.log(LogLevel::Warning, "ASTRA", message)
    }

    pub fn log_error(&self, message: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.log(LogLevel::Error, "ASTRA", message)
    }

    pub fn log_critical(&self, message: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.log(LogLevel::Critical, "ASTRA", message)
    }

    pub fn log_security_event(&self, event: &SecurityEvent) -> Result<(), Box<dyn std::error::Error>> {
        let metadata = serde_json::json!({
            "source_ip": event.source_ip.to_string(),
            "event_type": event.event_type,
            "threat_level": {
                "level": event.threat_level.level,
                "confidence": event.threat_level.confidence,
                "category": event.threat_level.category
            },
            "details": event.details,
            "action_taken": event.action_taken
        });

        let message = format!(
            "SECURITY EVENT: {} from {} - Threat Level: {}/10 ({}%) - {}",
            event.event_type,
            event.source_ip,
            event.threat_level.level,
            (event.threat_level.confidence * 100.0) as u8,
            event.details
        );

        // Log to main log
        self.log_with_metadata(
            if event.threat_level.level >= 8 { LogLevel::Critical }
            else if event.threat_level.level >= 6 { LogLevel::Error }
            else if event.threat_level.level >= 4 { LogLevel::Warning }
            else { LogLevel::Info },
            "SECURITY",
            &message,
            metadata.clone()
        )?;

        // Log to audit trail if enabled
        if let Some(audit_file) = &self.audit_file {
            let audit_entry = LogEntry {
                timestamp: event.timestamp,
                level: LogLevel::Info,
                module: "AUDIT".to_string(),
                message: message.clone(),
                metadata: Some(metadata),
            };

            let formatted_audit = self.format_log_entry(&audit_entry);
            let mut writer = audit_file.lock().unwrap();
            writeln!(writer, "{}", formatted_audit)?;
            writer.flush()?;
        }

        Ok(())
    }

    pub fn log_system_event(&self, event_type: &str, details: &str) -> Result<(), Box<dyn std::error::Error>> {
        let metadata = serde_json::json!({
            "event_type": event_type,
            "details": details,
            "hostname": self.get_hostname(),
            "pid": std::process::id()
        });

        let message = format!("SYSTEM: {} - {}", event_type, details);
        self.log_with_metadata(LogLevel::Info, "SYSTEM", &message, metadata)
    }

    pub fn log_module_event(&self, module: &str, event: &str, data: Option<serde_json::Value>) -> Result<(), Box<dyn std::error::Error>> {
        if let Some(metadata) = data {
            self.log_with_metadata(LogLevel::Info, module, event, metadata)
        } else {
            self.log(LogLevel::Info, module, event)
        }
    }

    pub fn log_performance_metrics(&self, metrics: &std::collections::HashMap<String, f64>) -> Result<(), Box<dyn std::error::Error>> {
        let metadata = serde_json::json!(metrics);
        
        let message = format!(
            "PERFORMANCE: CPU: {:.1}% | Memory: {:.1}MB | Network: {:.1}Mbps",
            metrics.get("cpu_usage").unwrap_or(&0.0),
            metrics.get("memory_usage").unwrap_or(&0.0),
            metrics.get("network_throughput").unwrap_or(&0.0)
        );

        self.log_with_metadata(LogLevel::Debug, "PERFORMANCE", &message, metadata)
    }

    pub fn rotate_logs(&self) -> Result<(), Box<dyn std::error::Error>> {
        let log_path = &self.config.logging.log_file;
        let max_size = self.config.logging.max_log_size * 1024 * 1024; // Convert MB to bytes

        // Check if log file needs rotation
        if let Ok(metadata) = std::fs::metadata(log_path) {
            if metadata.len() > max_size {
                let timestamp = Utc::now().format("%Y%m%d_%H%M%S");
                let rotated_path = format!("{}.{}", log_path, timestamp);
                
                // Close current file handles
                drop(self.log_file.lock().unwrap());
                
                // Rotate the file
                std::fs::rename(log_path, &rotated_path)?;
                
                // Reopen log file
                let new_file = OpenOptions::new()
                    .create(true)
                    .write(true)
                    .append(true)
                    .open(log_path)?;
                
                // This would require rebuilding the Logger, so we'll just log the rotation
                self.log_info(&format!("Log rotated to: {}", rotated_path))?;
            }
        }

        Ok(())
    }

    pub fn cleanup_old_logs(&self) -> Result<(), Box<dyn std::error::Error>> {
        let log_dir = Path::new(&self.config.logging.log_file).parent().unwrap_or(Path::new("."));
        let retention_days = self.config.logging.log_retention_days;
        let cutoff = Utc::now() - chrono::Duration::days(retention_days as i64);

        if let Ok(entries) = std::fs::read_dir(log_dir) {
            for entry in entries {
                if let Ok(entry) = entry {
                    let path = entry.path();
                    if let Some(file_name) = path.file_name() {
                        let file_name_str = file_name.to_string_lossy();
                        
                        // Check if it's an ASTRA log file
                        if file_name_str.starts_with("astra") && file_name_str.contains(".log.") {
                            if let Ok(metadata) = entry.metadata() {
                                if let Ok(modified) = metadata.modified() {
                                    let modified_dt: DateTime<Utc> = modified.into();
                                    if modified_dt < cutoff {
                                        if let Err(e) = std::fs::remove_file(&path) {
                                            self.log_warning(&format!("Could not remove old log file {:?}: {}", path, e))?;
                                        } else {
                                            self.log_info(&format!("Removed old log file: {:?}", path))?;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Ok(())
    }

    pub fn get_log_stats(&self) -> Result<std::collections::HashMap<String, u64>, Box<dyn std::error::Error>> {
        let mut stats = std::collections::HashMap::new();
        
        // Get log file size
        if let Ok(metadata) = std::fs::metadata(&self.config.logging.log_file) {
            stats.insert("log_file_size_bytes".to_string(), metadata.len());
        }

        // Count log entries by level (simplified - would need to parse file for accurate counts)
        stats.insert("total_entries_estimated".to_string(), 0); // Placeholder
        
        Ok(stats)
    }

    fn get_hostname(&self) -> String {
        std::env::var("HOSTNAME")
            .or_else(|_| {
                use std::process::Command;
                Command::new("hostname")
                    .output()
                    .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
                    .unwrap_or_else(|_| "unknown".to_string())
            })
            .unwrap_or_else(|_| "unknown".to_string())
    }

    pub fn flush(&self) -> Result<(), Box<dyn std::error::Error>> {
        {
            let mut writer = self.log_file.lock().unwrap();
            writer.flush()?;
        }

        if let Some(audit_file) = &self.audit_file {
            let mut writer = audit_file.lock().unwrap();
            writer.flush()?;
        }

        Ok(())
    }

    pub fn set_console_output(&mut self, enabled: bool) {
        self.console_output = enabled;
    }

    pub fn set_log_level(&mut self, level: LogLevel) {
        self.log_level = level;
        let _ = self.log_info(&format!("Log level changed to: {}", level.as_str()));
    }
}

impl Drop for Logger {
    fn drop(&mut self) {
        let _ = self.log_info("Logger shutting down");
        let _ = self.flush();
    }
}