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
    
    local monitoring_enabled=$(get_config '.monitoring.enabled' 'true')
    
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
    log "INFO" "Configuring Prometheus service discovery..."
    
    local services_dir="$PROJECT_ROOT/config/services"
    if [[ ! -d "$services_dir" ]]; then
        log "WARN" "Services directory not found, skipping Prometheus configuration"
        return 0
    fi
    
    # Find monitoring service
    local monitoring_service_dir="$services_dir/monitoring"
    if [[ ! -d "$monitoring_service_dir" ]]; then
        log "WARN" "Monitoring service not found, skipping configuration"
        return 0
    fi
    
    local container_config="$monitoring_service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    
    if ! container_exists "$container_id"; then
        log "WARN" "Monitoring container $container_id not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Generate Prometheus configuration
        generate_prometheus_config "$container_id"
        
        # Restart Prometheus to reload configuration
        container_exec "$container_id" bash -c "
            cd /opt/monitoring &&
            docker compose restart prometheus
        "
        
        log "SUCCESS" "Prometheus targets configured"
    else
        log "INFO" "[DRY RUN] Would configure Prometheus targets"
    fi
}

generate_prometheus_config() {
    local container_id="$1"
    
    log "INFO" "Generating Prometheus configuration..."
    
    container_exec "$container_id" bash -c "mkdir -p /opt/monitoring/config"
    
    # Create Prometheus configuration
    container_exec "$container_id" bash -c "cat > /opt/monitoring/config/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - \"alert_rules.yml\"

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

  # Node exporter (host metrics)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # cAdvisor (container metrics)
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  # Nginx Proxy Manager
  - job_name: 'nginx-exporter'
    static_configs:
      - targets: ['nginx-exporter:9113']

  # Pi-hole metrics
  - job_name: 'pihole-exporter'
    static_configs:
      - targets: ['$(get_config ".networks.containers.gateway"):9617']
EOF"
    
    # Add service-specific exporters
    add_service_exporters "$container_id"
}

add_service_exporters() {
    local container_id="$1"
    local services_dir="$PROJECT_ROOT/config/services"
    
    log "INFO" "Adding service-specific exporters to Prometheus..."
    
    # Scan for services with exporters
    for service_dir in "$services_dir"/*; do
        if [[ -d "$service_dir" && "$(basename "$service_dir")" != "examples" ]]; then
            local service_name=$(basename "$service_dir")
            local container_config="$service_dir/container.yaml"
            
            if [[ -f "$container_config" ]]; then
                local service_ip=$(yq eval '.container.ip' "$container_config")
                
                # Check if service has common exporters
                case "$service_name" in
                    *nextcloud*)
                        add_exporter_config "$container_id" "nextcloud" "$service_ip" "9205"
                        ;;
                    *postgres*)
                        add_exporter_config "$container_id" "postgres" "$service_ip" "9187"
                        ;;
                    *mysql*|*mariadb*)
                        add_exporter_config "$container_id" "mysql" "$service_ip" "9104"
                        ;;
                    *redis*)
                        add_exporter_config "$container_id" "redis" "$service_ip" "9121"
                        ;;
                esac
            fi
        fi
    done
}

add_exporter_config() {
    local container_id="$1"
    local exporter_name="$2"
    local target_ip="$3"
    local port="$4"
    
    container_exec "$container_id" bash -c "cat >> /opt/monitoring/config/prometheus.yml << EOF

  # ${exporter_name} exporter
  - job_name: '${exporter_name}-exporter'
    static_configs:
      - targets: ['${target_ip}:${port}']
EOF"
}

setup_grafana_datasources() {
    log "INFO" "Setting up Grafana datasources..."
    
    local services_dir="$PROJECT_ROOT/config/services"
    local monitoring_service_dir="$services_dir/monitoring"
    
    if [[ ! -d "$monitoring_service_dir" ]]; then
        log "WARN" "Monitoring service not found"
        return 0
    fi
    
    local container_config="$monitoring_service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Grafana datasource configuration
        container_exec "$container_id" bash -c "mkdir -p /opt/monitoring/config/grafana/datasources"
        
        container_exec "$container_id" bash -c "cat > /opt/monitoring/config/grafana/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF"
        
        # Install common dashboards
        install_grafana_dashboards "$container_id"
        
        log "SUCCESS" "Grafana datasources configured"
    else
        log "INFO" "[DRY RUN] Would setup Grafana datasources"
    fi
}

install_grafana_dashboards() {
    local container_id="$1"
    
    log "INFO" "Installing Grafana dashboards..."
    
    container_exec "$container_id" bash -c "mkdir -p /opt/monitoring/dashboards"
    
    # Create dashboard provisioning config
    container_exec "$container_id" bash -c "cat > /opt/monitoring/config/grafana/dashboards/dashboards.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF"
    
    # Download and install common dashboards
    local dashboards=(
        "1860:node-exporter-full"
        "193:docker-containers"
        "7362:nginx-proxy-manager"
        "10467:pihole-dashboard"
    )
    
    for dashboard in "${dashboards[@]}"; do
        local dashboard_id="${dashboard%%:*}"
        local dashboard_name="${dashboard##*:}"
        
        log "DEBUG" "Installing dashboard: $dashboard_name (ID: $dashboard_id)"
        
        container_exec "$container_id" bash -c "
            curl -s https://grafana.com/api/dashboards/${dashboard_id}/revisions/1/download > /opt/monitoring/dashboards/${dashboard_name}.json
        " || log "WARN" "Failed to download dashboard $dashboard_name"
    done
}

configure_alerting_rules() {
    log "INFO" "Configuring Prometheus alerting rules..."
    
    local services_dir="$PROJECT_ROOT/config/services"
    local monitoring_service_dir="$services_dir/monitoring"
    
    if [[ ! -d "$monitoring_service_dir" ]]; then
        return 0
    fi
    
    local container_config="$monitoring_service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create alert rules
        container_exec "$container_id" bash -c "cat > /opt/monitoring/config/alert_rules.yml << 'EOF'
groups:
  - name: homelab.rules
    rules:
      # Service down alerts
      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: \"Service {{ \$labels.instance }} down\"
          description: \"{{ \$labels.instance }} has been down for more than 1 minute.\"

      # High CPU usage
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 85
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: \"High CPU usage on {{ \$labels.instance }}\"
          description: \"CPU usage is above 85% for more than 2 minutes.\"

      # High memory usage
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: \"High memory usage on {{ \$labels.instance }}\"
          description: \"Memory usage is above 90% for more than 2 minutes.\"

      # Low disk space
      - alert: LowDiskSpace
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 10
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: \"Low disk space on {{ \$labels.instance }}\"
          description: \"Disk usage is above 90% for more than 1 minute.\"

      # Container down
      - alert: ContainerDown
        expr: absent(container_last_seen) or (time() - container_last_seen) > 60
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: \"Container {{ \$labels.name }} is down\"
          description: \"Container has been down for more than 1 minute.\"
EOF"
        
        # Configure Alertmanager
        configure_alertmanager "$container_id"
        
        log "SUCCESS" "Alerting rules configured"
    else
        log "INFO" "[DRY RUN] Would configure alerting rules"
    fi
}

configure_alertmanager() {
    local container_id="$1"
    
    log "INFO" "Configuring Alertmanager..."
    
    # Get notification settings
    local discord_enabled=$(get_config '.monitoring.alerts.discord' 'false')
    local email_enabled=$(get_config '.monitoring.alerts.email' 'false')
    local admin_email=$(get_config '.cluster.admin_email')
    
    container_exec "$container_id" bash -c "cat > /opt/monitoring/config/alertmanager.yml << EOF
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@$(get_config '.cluster.domain')'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    email_configs:
      - to: '$admin_email'
        subject: 'Homelab Alert: {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'dev', 'instance']
EOF"
}

verify_monitoring_health() {
    log "INFO" "Verifying monitoring stack health..."
    
    local services_dir="$PROJECT_ROOT/config/services"
    local monitoring_service_dir="$services_dir/monitoring"
    
    if [[ ! -d "$monitoring_service_dir" ]]; then
        log "WARN" "Monitoring service not found"
        return 0
    fi
    
    local container_config="$monitoring_service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    local service_ip=$(yq eval '.container.ip' "$container_config")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would verify monitoring health"
        return 0
    fi
    
    local timeout=60
    local elapsed=0
    
    # Check Prometheus
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://$service_ip:9090/-/healthy" >/dev/null 2>&1; then
            log "SUCCESS" "Prometheus is healthy"
            break
        fi
        sleep 5
        ((elapsed += 5))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log "WARN" "Prometheus health check timeout"
    fi
    
    # Check Grafana
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://$service_ip:3000/api/health" >/dev/null 2>&1; then
            log "SUCCESS" "Grafana is healthy"
            break
        fi
        sleep 5
        ((elapsed += 5))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log "WARN" "Grafana health check timeout"
    fi
    
    log "INFO" "Monitoring stack access:"
    log "INFO" "  Prometheus: http://$service_ip:9090"
    log "INFO" "  Grafana: http://$service_ip:3000 (admin/admin)"
    log "INFO" "  Alertmanager: http://$service_ip:9093"
}

# Get monitoring metrics
get_monitoring_metrics() {
    local services_dir="$PROJECT_ROOT/config/services"
    local monitoring_service_dir="$services_dir/monitoring"
    
    if [[ ! -d "$monitoring_service_dir" ]]; then
        log "ERROR" "Monitoring service not found"
        return 1
    fi
    
    local container_config="$monitoring_service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    local service_ip=$(yq eval '.container.ip' "$container_config")
    
    log "INFO" "Current monitoring metrics:"
    
    # Get Prometheus targets
    if curl -s "http://$service_ip:9090/api/v1/targets" >/dev/null 2>&1; then
        local active_targets=$(curl -s "http://$service_ip:9090/api/v1/targets" | jq -r '.data.activeTargets | length')
        log "INFO" "Active Prometheus targets: $active_targets"
    else
        log "WARN" "Unable to fetch Prometheus metrics"
    fi
    
    # Get container metrics
    if container_exists "$container_id"; then
        local running_containers=$(container_exec "$container_id" bash -c "cd /opt/monitoring && docker compose ps -q | wc -l")
        log "INFO" "Running monitoring containers: $running_containers"
    fi
}

# Backup monitoring configuration
backup_monitoring_config() {
    local services_dir="$PROJECT_ROOT/config/services"
    local monitoring_service_dir="$services_dir/monitoring"
    local backup_dir="${PROJECT_ROOT}/backups/monitoring/$(date +%Y%m%d_%H%M%S)"
    
    if [[ ! -d "$monitoring_service_dir" ]]; then
        log "ERROR" "Monitoring service not found"
        return 1
    fi
    
    local container_config="$monitoring_service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    
    log "INFO" "Backing up monitoring configuration to $backup_dir"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$backup_dir"
        
        # Backup Prometheus data
        container_exec "$container_id" bash -c "
            cd /opt/monitoring &&
            tar czf /tmp/prometheus-backup.tar.gz data/prometheus/ config/
        "
        
        container_pull "$container_id" "/tmp/prometheus-backup.tar.gz" "$backup_dir/prometheus-backup.tar.gz"
        
        # Backup Grafana data
        container_exec "$container_id" bash -c "
            cd /opt/monitoring &&
            tar czf /tmp/grafana-backup.tar.gz data/grafana/ dashboards/
        "
        
        container_pull "$container_id" "/tmp/grafana-backup.tar.gz" "$backup_dir/grafana-backup.tar.gz"
        
        log "SUCCESS" "Monitoring configuration backed up"
    else
        log "INFO" "[DRY RUN] Would backup monitoring configuration"
    fi
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.json}"
    MONITORING_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    setup_monitoring_stack
fi