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
    
    configure_prometheus_targets || return 1
    setup_grafana_datasources || return 1
    configure_alerting_rules || return 1
    verify_monitoring_health || return 1
    
    log "SUCCESS" "Monitoring stack setup completed"
}

configure_prometheus_targets() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" ]]; then
        log "WARN" "Monitoring service not configured, skipping Prometheus setup"
        return 0
    fi
    
    local container_id="1${monitoring_ip##*.}"
    
    log "INFO" "Configuring Prometheus service discovery..."
    
    if ! container_exists "$container_id"; then
        log "WARN" "Monitoring container $container_id not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Update Prometheus configuration with all services
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

  # Pi-hole monitoring
  - job_name: 'pihole'
    static_configs:
      - targets: ['$(get_config '.networks.core_services.pihole' '10.0.0.40'):9617']
    scrape_interval: 30s

  # Nginx Proxy Manager monitoring  
  - job_name: 'nginx-proxy'
    static_configs:
      - targets: ['$(get_config '.networks.core_services.nginx_proxy' '10.0.0.41'):9113']
    scrape_interval: 30s

  # VPN Gateway monitoring
  - job_name: 'vpn-gateway'
    static_configs:
      - targets: ['$(get_config '.networks.core_services.vpn_gateway' '10.0.0.39'):8001']
    scrape_interval: 30s

  # Container monitoring (cAdvisor)
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 30s

  # Node exporter (system metrics)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']
    scrape_interval: 30s
EOF"
        
        # Add user services to monitoring
        add_user_services_to_prometheus "$container_id"
        
        # Restart Prometheus to apply configuration
        container_exec "$container_id" bash -c "
            cd /opt/monitoring &&
            docker compose restart prometheus
        "
        
        log "SUCCESS" "Prometheus targets configured"
    else
        log "INFO" "[DRY RUN] Would configure Prometheus targets"
    fi
}

add_user_services_to_prometheus() {
    local container_id="$1"
    
    # Add monitoring for user services
    local services_dir="$PROJECT_ROOT/config/services"
    if [[ -d "$services_dir" ]]; then
        for service_dir in "$services_dir"/*; do
            if [[ -d "$service_dir" ]]; then
                local service_name=$(basename "$service_dir")
                local container_config="$service_dir/container.yaml"
                
                # Skip core services and examples
                if [[ "$service_name" =~ ^(pihole|nginx-proxy|monitoring|authentik|vpn-gateway|homepage|examples)$ ]]; then
                    continue
                fi
                
                if [[ -f "$container_config" ]]; then
                    local service_ip=$(yq eval '.container.ip' "$container_config")
                    
                    if [[ "$service_ip" != "null" ]]; then
                        # Add basic HTTP monitoring for user services
                        container_exec "$container_id" bash -c "cat >> /opt/monitoring/prometheus.yml << EOF

  # User service: $service_name
  - job_name: '$service_name'
    static_configs:
      - targets: ['$service_ip:80']
    scrape_interval: 60s
    metrics_path: /metrics
    honor_labels: true
EOF"
                        log "DEBUG" "Added monitoring for user service: $service_name"
                    fi
                fi
            fi
        done
    fi
}

setup_grafana_datasources() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    local container_id="1${monitoring_ip##*.}"
    
    log "INFO" "Setting up Grafana datasources..."
    
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
        
        # Create datasource provisioning config
        container_exec "$container_id" bash -c "
            mkdir -p /opt/monitoring/grafana/provisioning/{datasources,dashboards} &&
            cat > /opt/monitoring/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    basicAuth: false
    jsonData:
      timeInterval: 15s
      httpMethod: POST
EOF"
        
        # Create dashboard provisioning config
        container_exec "$container_id" bash -c "cat > /opt/monitoring/grafana/provisioning/dashboards/homelab.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'Homelab Dashboards'
    orgId: 1
    folder: 'Homelab'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF"
        
        # Restart Grafana to apply datasource
        container_exec "$container_id" bash -c "
            cd /opt/monitoring &&
            docker compose restart grafana
        "
        
        log "SUCCESS" "Grafana datasources configured"
    else
        log "INFO" "[DRY RUN] Would setup Grafana datasources"
    fi
}

configure_alerting_rules() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    local container_id="1${monitoring_ip##*.}"
    
    log "INFO" "Configuring alerting rules..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create comprehensive alert rules
        container_exec "$container_id" bash -c "cat > /opt/monitoring/alert_rules.yml << 'EOF'
groups:
  - name: homelab.rules
    rules:
    # Infrastructure alerts
    - alert: ServiceDown
      expr: up == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: 'Service {{ \$labels.instance }} is down'
        description: 'Service {{ \$labels.instance }} has been down for more than 5 minutes.'

    - alert: HighCPUUsage
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: 'High CPU usage on {{ \$labels.instance }}'
        description: 'CPU usage is above 85% for more than 10 minutes.'

    - alert: LowDiskSpace
      expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: 'Low disk space on {{ \$labels.instance }}'
        description: 'Disk space is below 10% on {{ \$labels.instance }}.'

    - alert: HighMemoryUsage
      expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: 'High memory usage on {{ \$labels.instance }}'
        description: 'Memory usage is above 90% for more than 10 minutes.'

    # Service-specific alerts
    - alert: PiholeDown
      expr: pihole_up == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: 'Pi-hole is down'
        description: 'Pi-hole DNS service is not responding.'

    - alert: NginxProxyDown
      expr: nginx_up == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: 'Nginx Proxy Manager is down'
        description: 'Nginx Proxy Manager is not responding.'

    - alert: VPNDisconnected
      expr: gluetun_vpn_status != 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: 'VPN connection lost'
        description: 'VPN gateway has lost connection to VPN provider.'

    # Certificate alerts
    - alert: SSLCertificateExpiringSoon
      expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: 'SSL certificate expiring soon for {{ \$labels.instance }}'
        description: 'SSL certificate for {{ \$labels.instance }} expires in less than 30 days.'

    - alert: SSLCertificateExpired
      expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: 'SSL certificate expired for {{ \$labels.instance }}'
        description: 'SSL certificate for {{ \$labels.instance }} has expired.'
EOF"
        
        log "SUCCESS" "Alert rules configured"
    else
        log "INFO" "[DRY RUN] Would configure alerting rules"
    fi
}

verify_monitoring_health() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "INFO" "Verifying monitoring stack health..."
    
    local container_id="1${monitoring_ip##*.}"
    local health_issues=()
    
    # Check Prometheus
    if ! container_exec "$container_id" curl -s http://localhost:9090/-/healthy >/dev/null 2>&1; then
        health_issues+=("Prometheus")
    fi
    
    # Check Grafana
    if ! container_exec "$container_id" curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
        health_issues+=("Grafana")
    fi
    
    # Check Alertmanager
    if ! container_exec "$container_id" curl -s http://localhost:9093/-/healthy >/dev/null 2>&1; then
        health_issues+=("Alertmanager")
    fi
    
    if [[ ${#health_issues[@]} -eq 0 ]]; then
        log "SUCCESS" "Monitoring stack is healthy"
        return 0
    else
        log "WARN" "Monitoring health issues: ${health_issues[*]}"
        return 1
    fi
}

# Setup service-specific monitoring
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

# Check monitoring health
check_monitoring_health() {
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" ]]; then
        log "INFO" "Monitoring not configured"
        return 0
    fi
    
    log "INFO" "Checking monitoring stack health..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would check monitoring health"
        return 0
    fi
    
    # Check Prometheus
    if curl -s --connect-timeout 5 "http://$monitoring_ip:9090/-/healthy" >/dev/null; then
        log "SUCCESS" "Prometheus is healthy"
    else
        log "WARN" "Prometheus health check failed"
        return 1
    fi
    
    # Check Grafana
    if curl -s --connect-timeout 5 "http://$monitoring_ip:3000/api/health" >/dev/null; then
        log "SUCCESS" "Grafana is healthy"
    else
        log "WARN" "Grafana health check failed"
        return 1
    fi
    
    return 0
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