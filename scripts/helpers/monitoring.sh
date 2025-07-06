#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          MONITORING STACK SETUP                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Configure Prometheus, Grafana, and monitoring dashboards
# 📊 Features: Service discovery, alerting, health checks

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/containers.sh"

setup_monitoring_stack() {
    log "STEP" "Setting up monitoring stack..."
    
    local monitoring_enabled=$(is_feature_enabled '.monitoring.enabled' 'true')
    
    if [[ "$monitoring_enabled" != "true" ]]; then
        log "INFO" "Monitoring disabled in configuration, skipping"
        return 0
    fi
    
    configure_prometheus || return 1
    configure_grafana || return 1
    setup_service_monitoring || return 1
    configure_alerting || return 1
    
    log "SUCCESS" "Monitoring stack setup completed"
}

configure_prometheus() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" ]]; then
        log "WARN" "Monitoring service not configured, skipping Prometheus setup"
        return 0
    fi
    
    local container_id="1${monitoring_ip##*.}"
    
    log "INFO" "Configuring Prometheus..."
    
    if ! container_exists "$container_id"; then
        log "WARN" "Monitoring container $container_id not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create enhanced Prometheus configuration
        container_exec "$container_id" bash -c "cat > /opt/monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: '$(get_config '.cluster.name')'
    environment: 'homelab'

rule_files:
  - '/etc/prometheus/alert_rules.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Prometheus itself
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s

  # Proxmox host monitoring
  - job_name: 'proxmox-host'
    static_configs:
      - targets: ['$(get_config '.proxmox.host'):9100']
    scrape_interval: 30s
    metrics_path: /metrics

  # Container monitoring
  - job_name: 'containers'
    static_configs:
EOF"
        
        # Add monitoring targets for each service
        add_service_monitoring_targets "$container_id"
        
        # Create basic alert rules
        create_alert_rules "$container_id"
        
        # Restart Prometheus to apply configuration
        container_exec "$container_id" bash -c "
            cd /opt/monitoring &&
            docker compose restart prometheus
        "
        
        log "SUCCESS" "Prometheus configured with service discovery"
    else
        log "INFO" "[DRY RUN] Would configure Prometheus"
    fi
}

add_service_monitoring_targets() {
    local container_id="$1"
    
    # Add core services
    local core_services=("pihole" "nginx_proxy" "authentik")
    for service in "${core_services[@]}"; do
        local service_key="${service//-/_}"
        local service_ip=$(get_config ".networks.core_services.$service_key")
        
        if [[ "$service_ip" != "null" ]]; then
            container_exec "$container_id" bash -c "cat >> /opt/monitoring/prometheus.yml << EOF
      - targets: ['$service_ip:80']
        labels:
          service: '$service'
          type: 'core'
EOF"
        fi
    done
    
    # Add user services
    local services_dir="$PROJECT_ROOT/config/services"
    if [[ -d "$services_dir" ]]; then
        for service_dir in "$services_dir"/*; do
            if [[ -d "$service_dir" ]]; then
                local service_name=$(basename "$service_dir")
                local container_config="$service_dir/container.yaml"
                
                if [[ -f "$container_config" ]]; then
                    local service_ip=$(yq eval '.container.ip' "$container_config")
                    
                    container_exec "$container_id" bash -c "cat >> /opt/monitoring/prometheus.yml << EOF
      - targets: ['$service_ip:80']
        labels:
          service: '$service_name'
          type: 'user'
EOF"
                fi
            fi
        done
    fi
}

create_alert_rules() {
    local container_id="$1"
    
    log "INFO" "Creating Prometheus alert rules..."
    
    container_exec "$container_id" bash -c "cat > /opt/monitoring/alert_rules.yml << 'EOF'
groups:
  - name: homelab.rules
    rules:
    # Service availability alerts
    - alert: ServiceDown
      expr: up == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: 'Service {{ \$labels.instance }} is down'
        description: 'Service {{ \$labels.instance }} has been down for more than 5 minutes.'

    # High CPU usage
    - alert: HighCPUUsage
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: 'High CPU usage on {{ \$labels.instance }}'
        description: 'CPU usage is above 85% for more than 10 minutes.'

    # Low disk space
    - alert: LowDiskSpace
      expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: 'Low disk space on {{ \$labels.instance }}'
        description: 'Disk space is below 10% on {{ \$labels.instance }}.'

    # Container not running
    - alert: ContainerDown
      expr: absent(container_last_seen) or (time() - container_last_seen) > 60
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: 'Container {{ \$labels.name }} is not running'
        description: 'Container {{ \$labels.name }} has not been seen for more than 1 minute.'
EOF"
}

configure_grafana() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    local container_id="1${monitoring_ip##*.}"
    
    log "INFO" "Configuring Grafana dashboards..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for Grafana to be ready
        local timeout=120
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if container_exec "$container_id" curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
                break
            fi
            sleep 5
            ((elapsed += 5))
        done
        
        # Create datasource configuration
        create_grafana_datasources "$container_id"
        
        # Import default dashboards
        import_grafana_dashboards "$container_id"
        
        log "SUCCESS" "Grafana configured with dashboards"
        log "INFO" "Access Grafana at: https://grafana.$(get_config '.cluster.domain')"
        log "INFO" "Default credentials: admin / admin"
    else
        log "INFO" "[DRY RUN] Would configure Grafana"
    fi
}

create_grafana_datasources() {
    local container_id="$1"
    
    container_exec "$container_id" bash -c "cat > /opt/monitoring/grafana-datasources.json << 'EOF'
{
  \"apiVersion\": 1,
  \"datasources\": [
    {
      \"name\": \"Prometheus\",
      \"type\": \"prometheus\",
      \"access\": \"proxy\",
      \"url\": \"http://prometheus:9090\",
      \"isDefault\": true,
      \"editable\": true
    }
  ]
}
EOF"
    
    # Mount datasources configuration
    container_exec "$container_id" bash -c "
        docker cp /opt/monitoring/grafana-datasources.json monitoring_grafana_1:/etc/grafana/provisioning/datasources/
        docker restart monitoring_grafana_1
    "
}

import_grafana_dashboards() {
    local container_id="$1"
    
    log "INFO" "Importing Grafana dashboards..."
    
    # Create dashboard for infrastructure overview
    create_infrastructure_dashboard "$container_id"
    
    # Create dashboard for service monitoring
    create_services_dashboard "$container_id"
}

create_infrastructure_dashboard() {
    local container_id="$1"
    
    container_exec "$container_id" bash -c "cat > /opt/monitoring/infrastructure-dashboard.json << 'EOF'
{
  \"dashboard\": {
    \"id\": null,
    \"title\": \"Homelab Infrastructure\",
    \"tags\": [\"homelab\", \"infrastructure\"],
    \"timezone\": \"browser\",
    \"panels\": [
      {
        \"id\": 1,
        \"title\": \"Service Status\",
        \"type\": \"stat\",
        \"targets\": [
          {
            \"expr\": \"up\",
            \"legendFormat\": \"{{ instance }}\"
          }
        ],
        \"gridPos\": {\"h\": 8, \"w\": 12, \"x\": 0, \"y\": 0}
      },
      {
        \"id\": 2,
        \"title\": \"CPU Usage\",
        \"type\": \"graph\",
        \"targets\": [
          {
            \"expr\": \"100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\\\"idle\\\"}[5m])) * 100)\",
            \"legendFormat\": \"{{ instance }}\"
          }
        ],
        \"gridPos\": {\"h\": 8, \"w\": 12, \"x\": 12, \"y\": 0}
      }
    ],
    \"time\": {
      \"from\": \"now-1h\",
      \"to\": \"now\"
    },
    \"refresh\": \"30s\"
  }
}
EOF"
}

create_services_dashboard() {
    local container_id="$1"
    
    container_exec "$container_id" bash -c "cat > /opt/monitoring/services-dashboard.json << 'EOF'
{
  \"dashboard\": {
    \"id\": null,
    \"title\": \"Homelab Services\",
    \"tags\": [\"homelab\", \"services\"],
    \"timezone\": \"browser\",
    \"panels\": [
      {
        \"id\": 1,
        \"title\": \"Service Availability\",
        \"type\": \"table\",
        \"targets\": [
          {
            \"expr\": \"up{job!=\\\"prometheus\\\"}\",
            \"format\": \"table\",
            \"instant\": true
          }
        ],
        \"gridPos\": {\"h\": 8, \"w\": 24, \"x\": 0, \"y\": 0}
      }
    ],
    \"time\": {
      \"from\": \"now-1h\",
      \"to\": \"now\"
    },
    \"refresh\": \"30s\"
  }
}
EOF"
}

setup_service_monitoring() {
    log "INFO" "Setting up service-specific monitoring..."
    
    # This function would set up monitoring for specific services
    # like database metrics, application metrics, etc.
    
    local services_dir="$PROJECT_ROOT/config/services"
    if [[ -d "$services_dir" ]]; then
        for service_dir in "$services_dir"/*; do
            if [[ -d "$service_dir" ]]; then
                local service_name=$(basename "$service_dir")
                setup_service_metrics "$service_name"
            fi
        done
    fi
}

setup_service_metrics() {
    local service_name="$1"
    
    log "DEBUG" "Setting up metrics for service: $service_name"
    
    # Add service-specific monitoring configuration
    # This could include:
    # - Database metrics exporters
    # - Application metrics endpoints
    # - Custom health check endpoints
}

configure_alerting() {
    local alerts_enabled=$(is_feature_enabled '.monitoring.alerts.enabled' 'true')
    
    if [[ "$alerts_enabled" != "true" ]]; then
        log "INFO" "Alerting disabled, skipping alerting configuration"
        return 0
    fi
    
    log "INFO" "Configuring alerting..."
    
    # Configure Discord webhook if enabled
    if is_feature_enabled '.monitoring.alerts.discord'; then
        configure_discord_alerts
    fi
    
    # Configure email alerts if enabled
    if is_feature_enabled '.monitoring.alerts.email'; then
        configure_email_alerts
    fi
}

configure_discord_alerts() {
    log "INFO" "Discord alerts will be configured when webhook is provided"
    log "INFO" "Set DISCORD_WEBHOOK environment variable"
}

configure_email_alerts() {
    log "INFO" "Email alerts will be configured when SMTP settings are provided"
    log "INFO" "Set EMAIL_* environment variables"
}

# Health check functions
check_monitoring_health() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" ]]; then
        log "INFO" "Monitoring not configured"
        return 0
    fi
    
    log "INFO" "Checking monitoring stack health..."
    
    # Check Prometheus
    if curl -s --connect-timeout 5 "http://$monitoring_ip:9090/-/healthy" >/dev/null; then
        log "SUCCESS" "Prometheus is healthy"
    else
        log "WARN" "Prometheus health check failed"
    fi
    
    # Check Grafana
    if curl -s --connect-timeout 5 "http://$monitoring_ip:3000/api/health" >/dev/null; then
        log "SUCCESS" "Grafana is healthy"
    else
        log "WARN" "Grafana health check failed"
    fi
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    setup_monitoring_stack
fi