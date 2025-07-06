#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         CONFIGURATION VALIDATION                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Validate cluster.yaml configuration file
# ✅ Checks: Required fields, IP ranges, network conflicts, service ports

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

validate_configuration() {
    log "STEP" "Validating cluster configuration..."
    
    validate_yaml_syntax || return 1
    validate_required_fields || return 1
    validate_network_configuration || return 1
    validate_service_configuration || return 1
    validate_resource_allocation || return 1
    
    log "SUCCESS" "Configuration validation passed"
}

validate_yaml_syntax() {
    log "INFO" "Checking YAML syntax..."
    
    if ! yq eval '.' "$CLUSTER_CONFIG" > /dev/null 2>&1; then
        log "ERROR" "Invalid YAML syntax in $CLUSTER_CONFIG"
        return 1
    fi
    
    log "DEBUG" "✓ YAML syntax is valid"
}

validate_required_fields() {
    log "INFO" "Checking required configuration fields..."
    
    local required_fields=(
        ".cluster.name"
        ".cluster.domain"
        ".cluster.timezone"
        ".cluster.admin_email"
        ".proxmox.host"
        ".networks.management.subnet"
        ".networks.containers.subnet"
        ".networks.containers.gateway"
    )
    
    local missing_fields=()
    for field in "${required_fields[@]}"; do
        local value=$(yq eval "$field" "$CLUSTER_CONFIG")
        if [[ "$value" == "null" || -z "$value" ]]; then
            missing_fields+=("$field")
        else
            log "DEBUG" "✓ $field = $value"
        fi
    done
    
    if [[ ${#missing_fields[@]} -gt 0 ]]; then
        log "ERROR" "Missing required configuration fields:"
        for field in "${missing_fields[@]}"; do
            log "ERROR" "  $field"
        done
        return 1
    fi
    
    log "SUCCESS" "All required fields present"
}

validate_network_configuration() {
    log "INFO" "Validating network configuration..."
    
    # Validate IP addresses and subnets
    local mgmt_subnet=$(get_config ".networks.management.subnet")
    local container_subnet=$(get_config ".networks.containers.subnet")
    local container_gateway=$(get_config ".networks.containers.gateway")
    
    # Check subnet formats
    if ! [[ "$mgmt_subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log "ERROR" "Invalid management subnet format: $mgmt_subnet"
        return 1
    fi
    
    if ! [[ "$container_subnet" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        log "ERROR" "Invalid container subnet format: $container_subnet"
        return 1
    fi
    
    # Validate gateway IP
    local subnet_base="${container_subnet%/*}"
    local subnet_prefix="${subnet_base%.*}"
    if ! [[ "$container_gateway" =~ ^${subnet_prefix}\.[0-9]{1,3}$ ]]; then
        log "ERROR" "Gateway $container_gateway not in container subnet $container_subnet"
        return 1
    fi
    
    # Check for subnet conflicts
    if [[ "${mgmt_subnet%/*}" == "${container_subnet%/*}" ]]; then
        log "ERROR" "Management and container subnets cannot overlap"
        log "ERROR" "Management: $mgmt_subnet, Container: $container_subnet"
        return 1
    fi
    
    log "DEBUG" "✓ Management subnet: $mgmt_subnet"
    log "DEBUG" "✓ Container subnet: $container_subnet"
    log "DEBUG" "✓ Container gateway: $container_gateway"
    
    # Validate service IPs
    validate_service_ips || return 1
    
    log "SUCCESS" "Network configuration valid"
}

validate_service_ips() {
    log "INFO" "Validating service IP allocations..."
    
    local container_subnet=$(get_config ".networks.containers.subnet")
    local subnet_base="${container_subnet%/*}"
    local subnet_prefix="${subnet_base%.*}"
    
    # Core services
    local core_services=("pihole" "nginx_proxy" "monitoring" "authentik")
    local used_ips=()
    
    for service in "${core_services[@]}"; do
        local service_key="${service//-/_}"  # Replace hyphens with underscores
        local service_ip=$(get_config ".networks.core_services.$service_key")
        
        if [[ "$service_ip" != "null" ]]; then
            # Check IP is in container subnet
            if ! [[ "$service_ip" =~ ^${subnet_prefix}\.[0-9]{1,3}$ ]]; then
                log "ERROR" "Service $service IP $service_ip not in container subnet $container_subnet"
                return 1
            fi
            
            # Check for duplicate IPs
            if [[ " ${used_ips[*]} " =~ " ${service_ip} " ]]; then
                log "ERROR" "Duplicate IP address: $service_ip (service: $service)"
                return 1
            fi
            
            used_ips+=("$service_ip")
            log "DEBUG" "✓ $service: $service_ip"
        fi
    done
    
    log "SUCCESS" "Service IP allocations valid"
}

validate_service_configuration() {
    log "INFO" "Validating service configurations..."
    
    # Check if any services are defined
    local services_dir="$PROJECT_ROOT/config/services"
    if [[ -d "$services_dir" ]]; then
        local service_count=$(find "$services_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
        log "DEBUG" "Found $service_count user-defined services"
        
        # Validate each service
        for service_dir in "$services_dir"/*; do
            if [[ -d "$service_dir" ]]; then
                validate_user_service "$(basename "$service_dir")" || return 1
            fi
        done
    else
        log "DEBUG" "No user services directory found"
    fi
    
    log "SUCCESS" "Service configurations valid"
}

validate_user_service() {
    local service_name="$1"
    local service_dir="$PROJECT_ROOT/config/services/$service_name"
    
    log "DEBUG" "Validating service: $service_name"
    
    # Check for required files
    if [[ ! -f "$service_dir/container.yaml" ]]; then
        log "ERROR" "Service $service_name missing container.yaml"
        return 1
    fi
    
    if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
        log "ERROR" "Service $service_name missing docker-compose.yml"
        return 1
    fi
    
    # Validate container configuration
    local container_config="$service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    local container_ip=$(yq eval '.container.ip' "$container_config")
    
    if [[ "$container_id" == "null" || ! "$container_id" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Service $service_name has invalid container ID: $container_id"
        return 1
    fi
    
    if [[ "$container_ip" == "null" || ! "$container_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log "ERROR" "Service $service_name has invalid container IP: $container_ip"
        return 1
    fi
    
    # Validate docker-compose syntax
    if ! docker compose -f "$service_dir/docker-compose.yml" config > /dev/null 2>&1; then
        log "ERROR" "Service $service_name has invalid docker-compose.yml"
        return 1
    fi
    
    log "DEBUG" "✓ Service $service_name valid (ID: $container_id, IP: $container_ip)"
}

validate_resource_allocation() {
    log "INFO" "Validating resource allocation..."
    
    # Get default resources
    local default_cpu=$(get_config ".defaults.cpu" "1")
    local default_memory=$(get_config ".defaults.memory" "512")
    local default_disk=$(get_config ".defaults.disk" "8")
    
    # Validate defaults are reasonable
    if [[ ! "$default_cpu" =~ ^[0-9]+$ ]] || [[ "$default_cpu" -lt 1 ]] || [[ "$default_cpu" -gt 32 ]]; then
        log "ERROR" "Invalid default CPU allocation: $default_cpu (must be 1-32)"
        return 1
    fi
    
    if [[ ! "$default_memory" =~ ^[0-9]+$ ]] || [[ "$default_memory" -lt 256 ]] || [[ "$default_memory" -gt 16384 ]]; then
        log "ERROR" "Invalid default memory allocation: ${default_memory}MB (must be 256-16384)"
        return 1
    fi
    
    if [[ ! "$default_disk" =~ ^[0-9]+$ ]] || [[ "$default_disk" -lt 4 ]] || [[ "$default_disk" -gt 500 ]]; then
        log "ERROR" "Invalid default disk allocation: ${default_disk}GB (must be 4-500)"
        return 1
    fi
    
    log "DEBUG" "✓ Default resources: ${default_cpu} CPU, ${default_memory}MB RAM, ${default_disk}GB disk"
    log "SUCCESS" "Resource allocation valid"
}

# Allow running this script standalone for validation
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${1:-config/cluster.yaml}"
    PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    
    if [[ ! -f "$CLUSTER_CONFIG" ]]; then
        echo "Usage: $0 [path/to/cluster.yaml]"
        echo "Default: config/cluster.yaml"
        exit 1
    fi
    
    validate_configuration
fi