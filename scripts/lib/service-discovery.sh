#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       SERVICE DISCOVERY LIBRARY                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Dynamic service discovery and management based on JSON configurations
# 📝 USAGE: Source this file in other scripts to access service discovery functions
# 🔧 FEATURES: Service enumeration, dependency resolution, metadata access

# Source configuration library
SERVICE_DISCOVERY_SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$SERVICE_DISCOVERY_SCRIPT_DIR/config.sh"

# ══════════════════════════════════════════════════════════════════════════════
# 📋 SERVICE ENUMERATION
# ══════════════════════════════════════════════════════════════════════════════

# Get list of all available services
get_all_services() {
    local services_dir="$CONFIG_DIR/services"
    
    if [[ ! -d "$services_dir" ]]; then
        echo "❌ Services directory not found: $services_dir" >&2
        return 1
    fi
    
    for service_dir in "$services_dir"/*/; do
        if [[ -d "$service_dir" && -f "$service_dir/service.json" ]]; then
            basename "$service_dir"
        fi
    done
}

# Get list of services configured for auto-deployment
get_auto_deploy_services() {
    get_config_array '.services.auto_deploy'
}

# Get service deployment order
get_deployment_order() {
    get_config_array '.services.deploy_order'
}

# Check if service is configured for auto-deployment
is_auto_deploy_service() {
    local service_name="$1"
    local auto_deploy_services
    
    readarray -t auto_deploy_services < <(get_auto_deploy_services)
    
    for service in "${auto_deploy_services[@]}"; do
        if [[ "$service" == "$service_name" ]]; then
            return 0
        fi
    done
    return 1
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 SERVICE METADATA
# ══════════════════════════════════════════════════════════════════════════════

# Get service metadata from service.json
get_service_metadata() {
    local service_name="$1"
    local property="$2"
    local service_file="$CONFIG_DIR/services/$service_name/service.json"
    
    if [[ ! -f "$service_file" ]]; then
        echo "❌ Service metadata not found: $service_file" >&2
        return 1
    fi
    
    if [[ -n "$property" ]]; then
        jq -r "$property // empty" "$service_file"
    else
        jq . "$service_file"
    fi
}

# Get service container configuration
get_service_container_config() {
    local service_name="$1"
    local property="$2"
    local container_file="$CONFIG_DIR/services/$service_name/container.json"
    
    if [[ ! -f "$container_file" ]]; then
        echo "❌ Container config not found: $container_file" >&2
        return 1
    fi
    
    if [[ -n "$property" ]]; then
        # Substitute environment variables in the result
        jq -r "$property // empty" "$container_file" | envsubst
    else
        # Substitute environment variables in the entire config
        envsubst < "$container_file"
    fi
}

# Get service display name
get_service_display_name() {
    local service_name="$1"
    get_service_metadata "$service_name" '.service.display_name'
}

# Get service description
get_service_description() {
    local service_name="$1"
    get_service_metadata "$service_name" '.service.description'
}

# Get service category
get_service_category() {
    local service_name="$1"
    get_service_metadata "$service_name" '.service.category'
}

# Get service priority
get_service_priority() {
    local service_name="$1"
    get_service_container_config "$service_name" '.service.priority'
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔗 DEPENDENCY MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

# Get service dependencies
get_service_dependencies() {
    local service_name="$1"
    local dependency_type="${2:-required}"  # required, optional, or all
    
    case "$dependency_type" in
        "required")
            get_service_metadata "$service_name" '.dependencies.required[]?'
            ;;
        "optional")
            get_service_metadata "$service_name" '.dependencies.optional[]?'
            ;;
        "all")
            {
                get_service_metadata "$service_name" '.dependencies.required[]?'
                get_service_metadata "$service_name" '.dependencies.optional[]?'
            }
            ;;
        *)
            echo "❌ Invalid dependency type: $dependency_type" >&2
            return 1
            ;;
    esac
}

# Check if service has dependencies
has_dependencies() {
    local service_name="$1"
    local dependencies
    
    dependencies=$(get_service_dependencies "$service_name" "required")
    [[ -n "$dependencies" ]]
}

# Resolve service dependencies in deployment order
resolve_dependencies() {
    local service_name="$1"
    local resolved=()
    local visited=()
    
    # Recursive function to resolve dependencies
    _resolve_deps() {
        local current_service="$1"
        
        # Check if already visited (circular dependency)
        for visited_service in "${visited[@]}"; do
            if [[ "$visited_service" == "$current_service" ]]; then
                echo "❌ Circular dependency detected: $current_service" >&2
                return 1
            fi
        done
        
        # Mark as visited
        visited+=("$current_service")
        
        # Get dependencies
        local dependencies
        readarray -t dependencies < <(get_service_dependencies "$current_service" "required")
        
        # Resolve dependencies first
        for dep in "${dependencies[@]}"; do
            if [[ -n "$dep" ]]; then
                _resolve_deps "$dep"
            fi
        done
        
        # Add current service to resolved list if not already there
        local found=false
        for resolved_service in "${resolved[@]}"; do
            if [[ "$resolved_service" == "$current_service" ]]; then
                found=true
                break
            fi
        done
        
        if [[ "$found" == false ]]; then
            resolved+=("$current_service")
        fi
    }
    
    # Resolve dependencies for the requested service
    _resolve_deps "$service_name"
    
    # Print resolved dependencies
    for resolved_service in "${resolved[@]}"; do
        echo "$resolved_service"
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 🌐 EXTERNAL ACCESS
# ══════════════════════════════════════════════════════════════════════════════

# Check if service has external access enabled
has_external_access() {
    local service_name="$1"
    local external_enabled
    
    external_enabled=$(get_service_metadata "$service_name" '.external_access.enabled')
    [[ "$external_enabled" == "true" ]]
}

# Get service subdomain
get_service_subdomain() {
    local service_name="$1"
    get_service_metadata "$service_name" '.external_access.subdomain'
}

# Check if service is public (no authentication required)
is_public_service() {
    local service_name="$1"
    local public_access
    
    public_access=$(get_service_metadata "$service_name" '.external_access.public')
    [[ "$public_access" == "true" ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# 📊 MONITORING AND BACKUP
# ══════════════════════════════════════════════════════════════════════════════

# Check if service has monitoring enabled
has_monitoring() {
    local service_name="$1"
    local monitoring_enabled
    
    monitoring_enabled=$(get_service_metadata "$service_name" '.monitoring.enabled')
    [[ "$monitoring_enabled" == "true" ]]
}

# Check if service has backup enabled
has_backup() {
    local service_name="$1"
    local backup_enabled
    
    backup_enabled=$(get_service_metadata "$service_name" '.backup.enabled')
    [[ "$backup_enabled" == "true" ]]
}

# Get service backup paths
get_backup_paths() {
    local service_name="$1"
    get_service_metadata "$service_name" '.backup.paths[]?'
}

# ══════════════════════════════════════════════════════════════════════════════
# 📋 SERVICE LISTING AND FILTERING
# ══════════════════════════════════════════════════════════════════════════════

# List services by category
list_services_by_category() {
    local category="$1"
    local services
    
    readarray -t services < <(get_all_services)
    
    for service in "${services[@]}"; do
        local service_category
        service_category=$(get_service_category "$service")
        
        if [[ "$service_category" == "$category" ]]; then
            echo "$service"
        fi
    done
}

# List services with external access
list_external_services() {
    local services
    
    readarray -t services < <(get_all_services)
    
    for service in "${services[@]}"; do
        if has_external_access "$service"; then
            echo "$service"
        fi
    done
}

# List services with monitoring
list_monitored_services() {
    local services
    
    readarray -t services < <(get_all_services)
    
    for service in "${services[@]}"; do
        if has_monitoring "$service"; then
            echo "$service"
        fi
    done
}

# Print service summary
print_service_summary() {
    local service_name="$1"
    
    echo "📋 Service: $service_name"
    echo "  Display Name: $(get_service_display_name "$service_name")"
    echo "  Description: $(get_service_description "$service_name")"
    echo "  Category: $(get_service_category "$service_name")"
    echo "  Priority: $(get_service_priority "$service_name")"
    echo "  External Access: $(has_external_access "$service_name" && echo "enabled" || echo "disabled")"
    echo "  Monitoring: $(has_monitoring "$service_name" && echo "enabled" || echo "disabled")"
    echo "  Backup: $(has_backup "$service_name" && echo "enabled" || echo "disabled")"
    
    # Show dependencies
    local dependencies
    readarray -t dependencies < <(get_service_dependencies "$service_name" "required")
    if [[ ${#dependencies[@]} -gt 0 ]]; then
        echo "  Dependencies: ${dependencies[*]}"
    fi
}

# Export functions for use in other scripts
export -f get_all_services get_auto_deploy_services get_deployment_order is_auto_deploy_service
export -f get_service_metadata get_service_container_config get_service_display_name get_service_description get_service_category get_service_priority
export -f get_service_dependencies has_dependencies resolve_dependencies
export -f has_external_access get_service_subdomain is_public_service
export -f has_monitoring has_backup get_backup_paths
export -f list_services_by_category list_external_services list_monitored_services print_service_summary