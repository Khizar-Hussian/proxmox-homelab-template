#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        VALIDATION LIBRARY                                   ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Comprehensive validation for JSON configurations and system state
# 📝 USAGE: Source this file in other scripts to access validation functions
# 🔧 FEATURES: JSON validation, network validation, service validation

# Source configuration library
VALIDATION_SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$VALIDATION_SCRIPT_DIR/config.sh"

# ══════════════════════════════════════════════════════════════════════════════
# 📋 JSON VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Validate JSON file syntax
validate_json_file() {
    local file_path="$1"
    
    if [[ ! -f "$file_path" ]]; then
        echo "❌ Error: File not found: $file_path" >&2
        return 1
    fi
    
    if ! jq . "$file_path" >/dev/null 2>&1; then
        echo "❌ Error: Invalid JSON in file: $file_path" >&2
        return 1
    fi
    
    echo "✅ Valid JSON: $file_path"
}

# Validate all JSON configuration files
validate_all_configs() {
    echo "🔍 Validating all configuration files..."
    
    local config_dir="$CONFIG_DIR"
    local errors=0
    
    # Validate main cluster config
    if ! validate_json_file "$CLUSTER_CONFIG_FILE"; then
        ((errors++))
    fi
    
    # Validate service configurations
    for service_dir in "$config_dir"/services/*/; do
        if [[ -d "$service_dir" ]]; then
            local service_name=$(basename "$service_dir")
            
            # Validate container.json
            if [[ -f "$service_dir/container.json" ]]; then
                if ! validate_json_file "$service_dir/container.json"; then
                    ((errors++))
                fi
            fi
            
            # Validate service.json
            if [[ -f "$service_dir/service.json" ]]; then
                if ! validate_json_file "$service_dir/service.json"; then
                    ((errors++))
                fi
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ All configuration files are valid"
        return 0
    else
        echo "❌ Found $errors configuration errors" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 🌐 NETWORK VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Validate IP address format
validate_ip() {
    local ip="$1"
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate subnet format
validate_subnet() {
    local subnet="$1"
    
    if [[ $subnet =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        local ip_part="${subnet%/*}"
        local cidr_part="${subnet#*/}"
        
        # Validate IP part
        if ! validate_ip "$ip_part"; then
            return 1
        fi
        
        # Validate CIDR part
        if [[ $cidr_part -lt 1 || $cidr_part -gt 32 ]]; then
            return 1
        fi
        
        return 0
    fi
    return 1
}

# Test network connectivity
test_connectivity() {
    local host="$1"
    local port="${2:-22}"
    local timeout="${3:-5}"
    
    echo "🔍 Testing connectivity to $host:$port..."
    
    if timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null; then
        echo "✅ Connection to $host:$port successful"
        return 0
    else
        echo "❌ Cannot connect to $host:$port" >&2
        return 1
    fi
}

# Validate network configuration
validate_network_config() {
    echo "🌐 Validating network configuration..."
    
    local management_subnet management_gateway proxmox_host nfs_server
    management_subnet=$(get_config '.networking.management.subnet')
    management_gateway=$(get_config '.networking.management.gateway')
    proxmox_host=$(get_config '.proxmox.host')
    nfs_server=$(get_config '.storage.nfs_server')
    
    local errors=0
    
    # Validate subnet format
    if ! validate_subnet "$management_subnet"; then
        echo "❌ Invalid management subnet format: $management_subnet" >&2
        ((errors++))
    fi
    
    # Validate gateway IP
    if ! validate_ip "$management_gateway"; then
        echo "❌ Invalid management gateway IP: $management_gateway" >&2
        ((errors++))
    fi
    
    # Validate Proxmox host IP
    if ! validate_ip "$proxmox_host"; then
        echo "❌ Invalid Proxmox host IP: $proxmox_host" >&2
        ((errors++))
    fi
    
    # Validate NFS server IP
    if ! validate_ip "$nfs_server"; then
        echo "❌ Invalid NFS server IP: $nfs_server" >&2
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ Network configuration is valid"
        return 0
    else
        echo "❌ Found $errors network configuration errors" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 SERVICE VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Validate service configuration
validate_service_config() {
    local service_name="$1"
    local service_dir="$CONFIG_DIR/services/$service_name"
    
    if [[ ! -d "$service_dir" ]]; then
        echo "❌ Service directory not found: $service_dir" >&2
        return 1
    fi
    
    local errors=0
    
    # Check required files
    if [[ ! -f "$service_dir/container.json" ]]; then
        echo "❌ Missing container.json for service: $service_name" >&2
        ((errors++))
    fi
    
    if [[ ! -f "$service_dir/service.json" ]]; then
        echo "❌ Missing service.json for service: $service_name" >&2
        ((errors++))
    fi
    
    if [[ ! -f "$service_dir/docker-compose.yaml" ]]; then
        echo "❌ Missing docker-compose.yaml for service: $service_name" >&2
        ((errors++))
    fi
    
    # Validate JSON files
    if [[ -f "$service_dir/container.json" ]]; then
        if ! validate_json_file "$service_dir/container.json"; then
            ((errors++))
        fi
    fi
    
    if [[ -f "$service_dir/service.json" ]]; then
        if ! validate_json_file "$service_dir/service.json"; then
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ Service configuration valid: $service_name"
        return 0
    else
        echo "❌ Found $errors errors in service: $service_name" >&2
        return 1
    fi
}

# Validate all service configurations
validate_all_services() {
    echo "🔧 Validating all service configurations..."
    
    local errors=0
    
    # Get list of services to deploy
    local services
    readarray -t services < <(get_config_array '.services.auto_deploy')
    
    for service in "${services[@]}"; do
        if ! validate_service_config "$service"; then
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ All service configurations are valid"
        return 0
    else
        echo "❌ Found $errors service configuration errors" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔒 VPN CONFIGURATION VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Validate VPN configuration
validate_vpn_config() {
    echo "🔒 Validating VPN configuration..."
    
    local vpn_enabled
    vpn_enabled=$(get_config '.security.vpn.enabled' 'false')
    
    if [[ "$vpn_enabled" != "true" ]]; then
        echo "ℹ️  VPN is disabled, skipping VPN validation"
        return 0
    fi
    
    local errors=0
    
    # Validate VPN provider
    local vpn_provider
    vpn_provider=$(get_config '.security.vpn.provider' 'nordvpn')
    
    if [[ ! "$vpn_provider" =~ ^(nordvpn|surfshark|expressvpn|protonvpn|custom)$ ]]; then
        echo "❌ Invalid VPN provider: $vpn_provider" >&2
        ((errors++))
    fi
    
    # Validate VPN protocol
    local vpn_protocol
    vpn_protocol=$(get_config '.security.vpn.protocol' 'openvpn')
    
    if [[ ! "$vpn_protocol" =~ ^(openvpn|wireguard)$ ]]; then
        echo "❌ Invalid VPN protocol: $vpn_protocol" >&2
        ((errors++))
    fi
    
    # Validate credentials based on provider and protocol
    if ! validate_vpn_credentials "$vpn_provider" "$vpn_protocol"; then
        ((errors++))
    fi
    
    # Validate VPN countries
    if ! validate_vpn_countries "$vpn_provider"; then
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ VPN configuration is valid"
        return 0
    else
        echo "❌ Found $errors VPN configuration errors" >&2
        return 1
    fi
}

# Validate VPN credentials
validate_vpn_credentials() {
    local provider="$1"
    local protocol="$2"
    
    echo "🔑 Validating VPN credentials for $provider ($protocol)..."
    
    case "$provider" in
        "nordvpn")
            case "$protocol" in
                "openvpn")
                    if [[ -z "${NORDVPN_USERNAME:-}" ]]; then
                        echo "❌ NORDVPN_USERNAME is required for NordVPN OpenVPN" >&2
                        return 1
                    fi
                    if [[ -z "${NORDVPN_PASSWORD:-}" ]]; then
                        echo "❌ NORDVPN_PASSWORD is required for NordVPN OpenVPN" >&2
                        return 1
                    fi
                    echo "✅ NordVPN OpenVPN credentials are present"
                    ;;
                "wireguard")
                    if [[ -z "${NORDVPN_PRIVATE_KEY:-}" ]]; then
                        echo "❌ NORDVPN_PRIVATE_KEY is required for NordVPN WireGuard" >&2
                        return 1
                    fi
                    # Validate WireGuard private key format
                    if [[ ! "${NORDVPN_PRIVATE_KEY:-}" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
                        echo "❌ NORDVPN_PRIVATE_KEY appears to be invalid format" >&2
                        return 1
                    fi
                    echo "✅ NordVPN WireGuard private key is present and valid format"
                    ;;
            esac
            ;;
        "surfshark")
            if [[ -z "${SURFSHARK_USER:-}" ]]; then
                echo "❌ SURFSHARK_USER is required for Surfshark" >&2
                return 1
            fi
            if [[ -z "${SURFSHARK_PASSWORD:-}" ]]; then
                echo "❌ SURFSHARK_PASSWORD is required for Surfshark" >&2
                return 1
            fi
            echo "✅ Surfshark credentials are present"
            ;;
        "expressvpn")
            if [[ -z "${EXPRESSVPN_USER:-}" ]]; then
                echo "❌ EXPRESSVPN_USER is required for ExpressVPN" >&2
                return 1
            fi
            if [[ -z "${EXPRESSVPN_PASSWORD:-}" ]]; then
                echo "❌ EXPRESSVPN_PASSWORD is required for ExpressVPN" >&2
                return 1
            fi
            echo "✅ ExpressVPN credentials are present"
            ;;
        *)
            echo "⚠️  Skipping credential validation for provider: $provider"
            ;;
    esac
    
    return 0
}

# Validate VPN countries
validate_vpn_countries() {
    local provider="$1"
    local countries="${VPN_COUNTRIES:-}"
    
    if [[ -z "$countries" ]]; then
        echo "❌ VPN_COUNTRIES is required when VPN is enabled" >&2
        return 1
    fi
    
    # Split countries by comma and validate each
    IFS=',' read -ra COUNTRY_ARRAY <<< "$countries"
    for country in "${COUNTRY_ARRAY[@]}"; do
        # Trim whitespace
        country=$(echo "$country" | xargs)
        
        # Basic validation - not empty and reasonable length
        if [[ -z "$country" ]]; then
            echo "❌ Empty country name in VPN_COUNTRIES" >&2
            return 1
        fi
        
        if [[ ${#country} -lt 2 || ${#country} -gt 50 ]]; then
            echo "❌ Invalid country name length: $country" >&2
            return 1
        fi
    done
    
    echo "✅ VPN countries configuration is valid: $countries"
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔍 DOCKER COMPOSE VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Validate docker-compose file
validate_docker_compose() {
    local compose_file="$1"
    
    if [[ ! -f "$compose_file" ]]; then
        echo "❌ Docker compose file not found: $compose_file" >&2
        return 1
    fi
    
    if command -v docker-compose >/dev/null 2>&1; then
        if docker-compose -f "$compose_file" config >/dev/null 2>&1; then
            echo "✅ Valid docker-compose file: $compose_file"
            return 0
        else
            echo "❌ Invalid docker-compose file: $compose_file" >&2
            return 1
        fi
    else
        echo "⚠️  Docker Compose not available, skipping validation of: $compose_file" >&2
        return 0
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# 🏥 COMPREHENSIVE VALIDATION
# ══════════════════════════════════════════════════════════════════════════════

# Run comprehensive validation
run_comprehensive_validation() {
    echo "🔍 Running comprehensive validation..."
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    local errors=0
    
    # 1. Validate JSON configurations
    if ! validate_all_configs; then
        ((errors++))
    fi
    
    echo ""
    
    # 2. Validate network configuration
    if ! validate_network_config; then
        ((errors++))
    fi
    
    echo ""
    
    # 3. Validate VPN configuration
    if ! validate_vpn_config; then
        ((errors++))
    fi
    
    echo ""
    
    # 4. Validate service configurations
    if ! validate_all_services; then
        ((errors++))
    fi
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    
    if [[ $errors -eq 0 ]]; then
        echo "✅ All validations passed successfully!"
        return 0
    else
        echo "❌ Validation failed with $errors error(s)" >&2
        return 1
    fi
}

# Export functions for use in other scripts
export -f validate_json_file validate_all_configs validate_ip validate_subnet test_connectivity validate_network_config validate_service_config validate_all_services validate_vpn_config validate_vpn_credentials validate_vpn_countries validate_docker_compose run_comprehensive_validation