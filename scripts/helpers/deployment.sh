#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                      DEPLOYMENT VALIDATION & CLEANUP                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Validate deployment success and perform cleanup tasks
# ✅ Features: Health checks, service validation, cleanup routines

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/containers.sh"

validate_deployment() {
    log "STEP" "Validating deployment..."
    
    validate_core_services || return 1
    validate_user_services || return 1
    validate_network_connectivity || return 1
    validate_dns_resolution || return 1
    validate_monitoring_stack || return 1
    
    log "SUCCESS" "Deployment validation completed"
}

validate_core_services() {
    log "INFO" "Validating core services..."
    
    local core_services=("pihole" "nginx-proxy" "monitoring" "authentik")
    local failed_services=()
    
    for service in "${core_services[@]}"; do
        if ! validate_core_service "$service"; then
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log "ERROR" "Core services validation failed: ${failed_services[*]}"
        return 1
    fi
    
    log "SUCCESS" "All core services validated"
}

validate_core_service() {
    local service_name="$1"
    local service_config_dir="${PROJECT_ROOT}/config/services/$service_name"
    
    if [[ ! -d "$service_config_dir" ]]; then
        log "WARN" "Service $service_name not found, skipping validation"
        return 0
    fi
    
    local container_config="$service_config_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    local service_ip=$(yq eval '.container.ip' "$container_config")
    
    if [[ "$service_ip" == "null" ]]; then
        log "DEBUG" "Service $service_name not configured, skipping validation"
        return 0
    fi
    
    local container_id="1${service_ip##*.}"
    
    # Check container exists and is running
    if ! container_exists "$container_id"; then
        log "ERROR" "Container $container_id for $service_name does not exist"
        return 1
    fi
    
    if [[ "$(get_container_status "$container_id")" != "running" ]]; then
        log "ERROR" "Container $container_id for $service_name is not running"
        return 1
    fi
    
    # Check Docker containers are running
    local running_containers=0
    if [[ "$DRY_RUN" == "false" ]]; then
        running_containers=$(container_exec "$container_id" docker ps -q | wc -l)
    else
        running_containers=1  # Assume success in dry run
    fi
    
    if [[ $running_containers -eq 0 ]]; then
        log "ERROR" "No Docker containers running in $service_name ($container_id)"
        return 1
    fi
    
    # Check service-specific endpoints
    case "$service_name" in
        "pihole")
            validate_pihole_service "$service_ip"
            ;;
        "nginx-proxy")
            validate_nginx_service "$service_ip"
            ;;
        "monitoring")
            validate_monitoring_service "$service_ip"
            ;;
        "authentik")
            validate_authentik_service "$service_ip"
            ;;
    esac
    
    local result=$?
    if [[ $result -eq 0 ]]; then
        log "SUCCESS" "✓ $service_name validated"
    else
        log "ERROR" "✗ $service_name validation failed"
    fi
    
    return $result
}

validate_pihole_service() {
    local service_ip="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check DNS service (port 53)
    if ! nc -z "$service_ip" 53; then
        log "ERROR" "Pi-hole DNS service not accessible on port 53"
        return 1
    fi
    
    # Check web interface (port 80)
    if ! curl -s --connect-timeout 5 "http://$service_ip" | grep -q "Pi-hole"; then
        log "ERROR" "Pi-hole web interface not accessible"
        return 1
    fi
    
    return 0
}

validate_nginx_service() {
    local service_ip="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check proxy ports
    for port in 80 443 81; do
        if ! nc -z "$service_ip" "$port"; then
            log "ERROR" "Nginx Proxy Manager port $port not accessible"
            return 1
        fi
    done
    
    # Check admin interface
    if ! curl -s --connect-timeout 5 "http://$service_ip:81" >/dev/null; then
        log "ERROR" "Nginx Proxy Manager admin interface not accessible"
        return 1
    fi
    
    return 0
}

validate_monitoring_service() {
    local service_ip="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check Prometheus (port 9090)
    if ! curl -s --connect-timeout 5 "http://$service_ip:9090/-/healthy" >/dev/null; then
        log "ERROR" "Prometheus not healthy"
        return 1
    fi
    
    # Check Grafana (port 3000)
    if ! curl -s --connect-timeout 5 "http://$service_ip:3000/api/health" >/dev/null; then
        log "ERROR" "Grafana not healthy"
        return 1
    fi
    
    return 0
}

validate_authentik_service() {
    local service_ip="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check Authentik ports
    for port in 9000 9443; do
        if ! nc -z "$service_ip" "$port"; then
            log "ERROR" "Authentik port $port not accessible"
            return 1
        fi
    done
    
    return 0
}

validate_user_services() {
    local services_dir="$PROJECT_ROOT/config/services"
    
    if [[ ! -d "$services_dir" ]]; then
        log "INFO" "No user services to validate"
        return 0
    fi
    
    log "INFO" "Validating user services..."
    
    local failed_services=()
    
    for service_dir in "$services_dir"/*; do
        if [[ -d "$service_dir" ]]; then
            local service_name=$(basename "$service_dir")
            if ! validate_user_service "$service_name"; then
                failed_services+=("$service_name")
            fi
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log "WARN" "User services validation failed: ${failed_services[*]}"
        # Don't fail deployment for user service issues
    else
        log "SUCCESS" "All user services validated"
    fi
}

validate_user_service() {
    local service_name="$1"
    local service_dir="$PROJECT_ROOT/config/services/$service_name"
    local container_config="$service_dir/container.yaml"
    
    if [[ ! -f "$container_config" ]]; then
        log "ERROR" "Container config not found for $service_name"
        return 1
    fi
    
    local container_id=$(yq eval '.container.id' "$container_config")
    local container_ip=$(yq eval '.container.ip' "$container_config")
    
    # Check container exists and is running
    if ! container_exists "$container_id"; then
        log "ERROR" "Container $container_id for $service_name does not exist"
        return 1
    fi
    
    if [[ "$(get_container_status "$container_id")" != "running" ]]; then
        log "ERROR" "Container $container_id for $service_name is not running"
        return 1
    fi
    
    # Check Docker containers are running
    if [[ "$DRY_RUN" == "false" ]]; then
        local running_containers=$(container_exec "$container_id" docker ps -q | wc -l)
        if [[ $running_containers -eq 0 ]]; then
            log "ERROR" "No Docker containers running in $service_name"
            return 1
        fi
    fi
    
    # Basic connectivity check
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! nc -z "$container_ip" 80; then
            log "WARN" "Service $service_name not responding on port 80"
            # Don't fail for this - service might use different port
        fi
    fi
    
    log "SUCCESS" "✓ User service $service_name validated"
    return 0
}

validate_network_connectivity() {
    log "INFO" "Validating network connectivity..."
    
    local container_subnet=$(get_config '.networks.containers.subnet')
    local gateway=$(get_config '.networks.containers.gateway')
    
    # Test gateway connectivity
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! ping -c 1 -W 2 "$gateway" >/dev/null; then
            log "ERROR" "Cannot reach container gateway: $gateway"
            return 1
        fi
    fi
    
    # Test external connectivity from container network
    local pihole_ip=$(get_config '.networks.core_services.pihole')
    if [[ "$pihole_ip" != "null" ]]; then
        local container_id="1${pihole_ip##*.}"
        
        if [[ "$DRY_RUN" == "false" ]] && container_exists "$container_id"; then
            if ! container_exec "$container_id" ping -c 1 -W 2 8.8.8.8 >/dev/null; then
                log "ERROR" "No external connectivity from containers"
                return 1
            fi
        fi
    fi
    
    log "SUCCESS" "Network connectivity validated"
}

validate_dns_resolution() {
    log "INFO" "Validating DNS resolution..."
    
    local domain=$(get_config '.cluster.domain')
    local pihole_ip=$(get_config '.networks.core_services.pihole')
    
    if [[ "$pihole_ip" == "null" ]]; then
        log "INFO" "Pi-hole not configured, skipping DNS validation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Test local domain resolution
        if command_exists dig; then
            if ! dig @"$pihole_ip" "pihole.$domain" +short | grep -q "$pihole_ip"; then
                log "WARN" "Local DNS resolution may not be working"
                # Don't fail deployment for DNS issues
            else
                log "SUCCESS" "DNS resolution working"
            fi
        fi
    else
        log "INFO" "[DRY RUN] Would validate DNS resolution"
    fi
}

validate_monitoring_stack() {
    local monitoring_enabled=$(is_feature_enabled '.monitoring.enabled' 'true')
    
    if [[ "$monitoring_enabled" != "true" ]]; then
        log "INFO" "Monitoring disabled, skipping monitoring validation"
        return 0
    fi
    
    log "INFO" "Validating monitoring stack..."
    
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" ]]; then
        log "WARN" "Monitoring IP not configured"
        return 0
    fi
    
    # Monitoring validation is already done in validate_core_services
    log "SUCCESS" "Monitoring stack validation completed"
}

cleanup_deployment() {
    log "STEP" "Performing deployment cleanup..."
    
    cleanup_temporary_files || return 1
    cleanup_failed_containers || return 1
    update_system_configuration || return 1
    
    log "SUCCESS" "Deployment cleanup completed"
}

cleanup_temporary_files() {
    log "INFO" "Cleaning up temporary files..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove any temporary files created during deployment
        find /tmp -name "homelab-*" -type f -mtime +1 -delete 2>/dev/null || true
        
        # Clean up any leftover container creation files
        find /var/lib/lxc -name "*.tmp" -delete 2>/dev/null || true
    fi
    
    log "SUCCESS" "Temporary files cleaned up"
}

cleanup_failed_containers() {
    log "INFO" "Cleaning up failed containers..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Look for stopped containers that failed to start properly
        for container_id in $(pct list | awk 'NR>1 && $2=="stopped" {print $1}'); do
            # Check if this is one of our containers (ID > 100)
            if [[ $container_id -gt 100 ]]; then
                local creation_time=$(stat -c %Y "/etc/pve/lxc/${container_id}.conf" 2>/dev/null || echo 0)
                local current_time=$(date +%s)
                local age=$((current_time - creation_time))
                
                # If container was created in the last hour but is stopped, it likely failed
                if [[ $age -lt 3600 ]]; then
                    log "WARN" "Found potentially failed container $container_id, investigating..."
                    
                    # Try to start it once more
                    if ! pct start "$container_id" 2>/dev/null; then
                        log "WARN" "Container $container_id failed to start, leaving for manual investigation"
                    fi
                fi
            fi
        done
    fi
    
    log "SUCCESS" "Failed container cleanup completed"
}

update_system_configuration() {
    log "INFO" "Updating system configuration..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Update package lists
        apt update >/dev/null 2>&1 || true
        
        # Ensure firewall rules are persistent
        if command_exists iptables-save && [[ -d /etc/iptables ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        
        # Update motd with deployment info
        update_motd
    fi
    
    log "SUCCESS" "System configuration updated"
}

update_motd() {
    local cluster_name=$(get_config '.cluster.name')
    local domain=$(get_config '.cluster.domain')
    
    cat > /etc/motd << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                          🏠 PROXMOX HOMELAB                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

Cluster: $cluster_name
Domain:  $domain
Deployed: $(date)

🌐 Core Services:
  • Pi-hole DNS:       https://pihole.$domain/admin
  • Nginx Proxy:       https://proxy.$domain:81
  • Grafana:           https://grafana.$domain
  • Authentik SSO:     https://auth.$domain

🔧 Management:
  • Container network: $(get_config '.networks.containers.subnet')
  • Proxmox web:       https://$(get_config '.proxmox.host'):8006

📚 Documentation: docs/
🔍 Health check:  ./scripts/health-check.sh

EOF
}

# Generate deployment report
generate_deployment_report() {
    log "INFO" "Generating deployment report..."
    
    local report_file="/tmp/homelab-deployment-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "PROXMOX HOMELAB DEPLOYMENT REPORT"
        echo "=================================="
        echo "Generated: $(date)"
        echo "Cluster: $(get_config '.cluster.name')"
        echo "Domain: $(get_config '.cluster.domain')"
        echo ""
        
        echo "CORE SERVICES:"
        echo "-------------"
        local core_services=("pihole" "nginx-proxy" "monitoring" "authentik")
        for service in "${core_services[@]}"; do
            local service_key="${service//-/_}"
            local service_ip=$(get_config ".networks.core_services.$service_key")
            if [[ "$service_ip" != "null" ]]; then
                local container_id="1${service_ip##*.}"
                local status="UNKNOWN"
                if container_exists "$container_id"; then
                    status=$(get_container_status "$container_id")
                fi
                printf "  %-15s %s (%s)\n" "$service" "$service_ip" "$status"
            fi
        done
        
        echo ""
        echo "USER SERVICES:"
        echo "-------------"
        local services_dir="$PROJECT_ROOT/config/services"
        if [[ -d "$services_dir" ]]; then
            for service_dir in "$services_dir"/*; do
                if [[ -d "$service_dir" ]]; then
                    local service_name=$(basename "$service_dir")
                    local container_config="$service_dir/container.yaml"
                    if [[ -f "$container_config" ]]; then
                        local container_id=$(yq eval '.container.id' "$container_config")
                        local container_ip=$(yq eval '.container.ip' "$container_config")
                        local status="UNKNOWN"
                        if container_exists "$container_id"; then
                            status=$(get_container_status "$container_id")
                        fi
                        printf "  %-15s %s (%s)\n" "$service_name" "$container_ip" "$status"
                    fi
                fi
            done
        else
            echo "  No user services configured"
        fi
        
        echo ""
        echo "NETWORK CONFIGURATION:"
        echo "---------------------"
        echo "  Management:   $(get_config '.networks.management.subnet')"
        echo "  Containers:   $(get_config '.networks.containers.subnet')"
        echo "  Gateway:      $(get_config '.networks.containers.gateway')"
        
        echo ""
        echo "SYSTEM RESOURCES:"
        echo "----------------"
        if [[ "$DRY_RUN" == "false" ]]; then
            echo "  RAM:          $(free -h | awk '/^Mem:/ {print $2}')"
            echo "  Disk:         $(df -h / | awk 'NR==2 {print $4 " available"}')"
            echo "  Load:         $(uptime | awk -F'load average:' '{print $2}')"
        else
            echo "  [DRY RUN - System info not available]"
        fi
        
        echo ""
        echo "NEXT STEPS:"
        echo "----------"
        echo "1. Change default passwords for all services"
        echo "2. Configure SSL certificates in Nginx Proxy Manager"
        echo "3. Set up authentication providers in Authentik"
        echo "4. Review monitoring dashboards in Grafana"
        echo "5. Add your own services in config/services/"
        
    } > "$report_file"
    
    log "SUCCESS" "Deployment report saved to: $report_file"
    
    # Also output to console if verbose
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo ""
        cat "$report_file"
        echo ""
    fi
}

# Health check functions
run_health_checks() {
    log "INFO" "Running comprehensive health checks..."
    
    local health_issues=()
    
    # Check system resources
    check_system_health || health_issues+=("system")
    
    # Check network connectivity
    check_network_health || health_issues+=("network")
    
    # Check service health
    check_services_health || health_issues+=("services")
    
    # Check monitoring health
    check_monitoring_health || health_issues+=("monitoring")
    
    if [[ ${#health_issues[@]} -eq 0 ]]; then
        log "SUCCESS" "All health checks passed"
        return 0
    else
        log "WARN" "Health issues detected in: ${health_issues[*]}"
        return 1
    fi
}

check_system_health() {
    log "DEBUG" "Checking system health..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
    if [[ $disk_usage -gt 90 ]]; then
        log "WARN" "High disk usage: ${disk_usage}%"
        return 1
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [[ $mem_usage -gt 90 ]]; then
        log "WARN" "High memory usage: ${mem_usage}%"
        return 1
    fi
    
    # Check load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    local cpu_count=$(nproc)
    local load_threshold=$((cpu_count * 2))
    
    if (( $(echo "$load_avg > $load_threshold" | bc -l) )); then
        log "WARN" "High load average: $load_avg (threshold: $load_threshold)"
        return 1
    fi
    
    return 0
}

check_network_health() {
    log "DEBUG" "Checking network health..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    local gateway=$(get_config '.networks.containers.gateway')
    
    # Test gateway connectivity
    if ! ping -c 1 -W 2 "$gateway" >/dev/null; then
        log "ERROR" "Cannot reach container gateway: $gateway"
        return 1
    fi
    
    # Test external connectivity
    if ! ping -c 1 -W 2 8.8.8.8 >/dev/null; then
        log "ERROR" "No external internet connectivity"
        return 1
    fi
    
    return 0
}

check_services_health() {
    log "DEBUG" "Checking services health..."
    
    local failed_services=()
    
    # Check core services
    local core_services=("pihole" "nginx-proxy" "monitoring" "authentik")
    for service in "${core_services[@]}"; do
        local service_key="${service//-/_}"
        local service_ip=$(get_config ".networks.core_services.$service_key")
        
        if [[ "$service_ip" != "null" ]]; then
            local container_id="1${service_ip##*.}"
            
            if ! container_exists "$container_id" || [[ "$(get_container_status "$container_id")" != "running" ]]; then
                failed_services+=("$service")
            fi
        fi
    done
    
    # Check user services
    local services_dir="$PROJECT_ROOT/config/services"
    if [[ -d "$services_dir" ]]; then
        for service_dir in "$services_dir"/*; do
            if [[ -d "$service_dir" ]]; then
                local service_name=$(basename "$service_dir")
                local container_config="$service_dir/container.yaml"
                
                if [[ -f "$container_config" ]]; then
                    local container_id=$(yq eval '.container.id' "$container_config")
                    
                    if ! container_exists "$container_id" || [[ "$(get_container_status "$container_id")" != "running" ]]; then
                        failed_services+=("$service_name")
                    fi
                fi
            fi
        done
    fi
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log "WARN" "Failed services: ${failed_services[*]}"
        return 1
    fi
    
    return 0
}

check_monitoring_health() {
    local monitoring_enabled=$(is_feature_enabled '.monitoring.enabled' 'true')
    
    if [[ "$monitoring_enabled" != "true" ]]; then
        return 0
    fi
    
    log "DEBUG" "Checking monitoring health..."
    
    local monitoring_ip=$(get_config '.networks.core_services.monitoring')
    
    if [[ "$monitoring_ip" == "null" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Check Prometheus
    if ! curl -s --connect-timeout 5 "http://$monitoring_ip:9090/-/healthy" >/dev/null; then
        log "WARN" "Prometheus health check failed"
        return 1
    fi
    
    # Check Grafana
    if ! curl -s --connect-timeout 5 "http://$monitoring_ip:3000/api/health" >/dev/null; then
        log "WARN" "Grafana health check failed"
        return 1
    fi
    
    return 0
}

# Rollback functionality
rollback_deployment() {
    local rollback_reason="${1:-Manual rollback requested}"
    
    log "STEP" "Rolling back deployment: $rollback_reason"
    
    # Stop all containers created during this deployment
    stop_deployment_containers
    
    # Restore network configuration if modified
    restore_network_configuration
    
    # Clean up any created resources
    cleanup_deployment_resources
    
    log "SUCCESS" "Deployment rollback completed"
}

stop_deployment_containers() {
    log "INFO" "Stopping deployment containers..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Stop containers created today
        local today=$(date +%Y-%m-%d)
        
        for container_id in $(pct list | awk 'NR>1 {print $1}'); do
            if [[ $container_id -gt 100 ]]; then
                local config_file="/etc/pve/lxc/${container_id}.conf"
                if [[ -f "$config_file" ]]; then
                    local creation_date=$(stat -c %y "$config_file" | cut -d' ' -f1)
                    if [[ "$creation_date" == "$today" ]]; then
                        log "INFO" "Stopping container $container_id (created today)"
                        pct stop "$container_id" || true
                    fi
                fi
            fi
        done
    fi
}

restore_network_configuration() {
    log "INFO" "Restoring network configuration..."
    
    local bridge=$(get_config '.networks.containers.bridge' 'vmbr1')
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove bridge if it was created by us
        if ip link show "$bridge" &>/dev/null; then
            # Check if bridge was created recently (has our comment)
            if grep -q "# Container network bridge for homelab (auto-generated)" /etc/network/interfaces; then
                log "INFO" "Removing auto-generated bridge configuration"
                # Remove our bridge configuration from interfaces file
                sed -i '/# Container network bridge for homelab (auto-generated)/,+8d' /etc/network/interfaces
                ifdown "$bridge" || true
            fi
        fi
    fi
}

cleanup_deployment_resources() {
    log "INFO" "Cleaning up deployment resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove any temporary files
        rm -f /tmp/homelab-* 2>/dev/null || true
        
        # Remove any downloaded container templates if they're not used by other containers
        # (This is optional and should be done carefully)
        
        # Reset iptables rules if they were modified
        # (This should be done very carefully to not break existing rules)
    fi
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    DEPLOYMENT_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    
    case "${1:-validate}" in
        "validate")
            validate_deployment
            ;;
        "cleanup")
            cleanup_deployment
            ;;
        "health")
            run_health_checks
            ;;
        "report")
            generate_deployment_report
            ;;
        "rollback")
            rollback_deployment "${2:-Manual rollback}"
            ;;
        *)
            echo "Usage: $0 [validate|cleanup|health|report|rollback]"
            echo "  validate  - Validate deployment (default)"
            echo "  cleanup   - Perform deployment cleanup"
            echo "  health    - Run health checks"
            echo "  report    - Generate deployment report"
            echo "  rollback  - Rollback deployment"
            ;;
    esac
fi