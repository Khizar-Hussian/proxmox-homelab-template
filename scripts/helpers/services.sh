#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                           SERVICE DEPLOYMENT                                ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Deploy user services from config/services/ directory
# 🐳 Features: Docker Compose deployment, environment generation, health checks

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/containers.sh"

deploy_user_services() {
    log "STEP" "Deploying user services..."
    
    local services_dir="$PROJECT_ROOT/config/services"
    
    if [[ ! -d "$services_dir" ]]; then
        log "INFO" "No services directory found, skipping service deployment"
        return 0
    fi
    
    # Find all service directories
    local services=()
    while IFS= read -r -d '' service_dir; do
        services+=($(basename "$service_dir"))
    done < <(find "$services_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log "INFO" "No services found in $services_dir"
        return 0
    fi
    
    log "INFO" "Found ${#services[@]} services: ${services[*]}"
    
    for service in "${services[@]}"; do
        deploy_user_service "$service" || return 1
    done
    
    log "SUCCESS" "User services deployment completed"
}

deploy_user_service() {
    local service_name="$1"
    local service_dir="$PROJECT_ROOT/config/services/$service_name"
    
    log "INFO" "Deploying service: $service_name"
    
    # Validate service configuration
    validate_service_config "$service_name" || return 1
    
    # Parse container configuration
    local container_config="$service_dir/container.yaml"
    local container_id=$(yq eval '.container.id' "$container_config")
    local container_ip=$(yq eval '.container.ip' "$container_config")
    local hostname=$(yq eval '.container.hostname // "'"$service_name"'"' "$container_config")
    
    # Check if container exists
    if container_exists "$container_id"; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log "WARN" "Destroying existing container $container_id for redeploy"
            destroy_container "$container_id"
        else
            log "INFO" "Container $container_id exists, updating service only"
            update_service "$service_name" "$container_id" "$service_dir"
            return 0
        fi
    fi
    
    # Create and configure container
    create_service_container "$service_name" "$container_id" "$container_ip" "$hostname" "$container_config" || return 1
    deploy_service_stack "$service_name" "$container_id" "$service_dir" || return 1
    verify_service_health "$service_name" "$container_id" || return 1
    
    log "SUCCESS" "Service $service_name deployed successfully"
}

validate_service_config() {
    local service_name="$1"
    local service_dir="$PROJECT_ROOT/config/services/$service_name"
    
    # Check required files
    if [[ ! -f "$service_dir/container.yaml" ]]; then
        log "ERROR" "Service $service_name missing container.yaml"
        return 1
    fi
    
    if [[ ! -f "$service_dir/docker-compose.yml" ]]; then
        log "ERROR" "Service $service_name missing docker-compose.yml"
        return 1
    fi
    
    # Validate YAML syntax
    if ! yq eval '.' "$service_dir/container.yaml" >/dev/null 2>&1; then
        log "ERROR" "Invalid YAML in $service_dir/container.yaml"
        return 1
    fi
    
    return 0
}

create_service_container() {
    local service_name="$1"
    local container_id="$2"
    local container_ip="$3"
    local hostname="$4"
    local container_config="$5"
    
    log "INFO" "Creating container for service: $service_name"
    
    # Get resources from service config or defaults
    local cpu=$(yq eval '.container.resources.cpu // 2' "$container_config")
    local memory=$(yq eval '.container.resources.memory // 1024' "$container_config")
    local disk=$(yq eval '.container.resources.disk // 20' "$container_config")
    
    # Get Proxmox configuration
    local storage=$(get_config ".proxmox.storage" "local-lvm")
    local template=$(get_config ".proxmox.template" "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst")
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create container
        pct create "$container_id" "$template" \
            --hostname "$hostname" \
            --cores "$cpu" \
            --memory "$memory" \
            --rootfs "$storage:$disk" \
            --net0 "name=eth0,bridge=$bridge,ip=${container_ip}/24,gw=$gateway" \
            --nameserver "$(get_config '.networks.core_services.pihole' "$gateway")" \
            --features "nesting=1" \
            --unprivileged 1 \
            --start 1
        
        # Setup NFS mounts if configured
        setup_nfs_mounts "$container_id" "$container_config"
        
        # Wait for container to be ready
        wait_for_container_ready "$container_id"
        
        # Install Docker
        setup_docker_in_container "$container_id"
        
        log "SUCCESS" "Container $container_id created for $service_name"
    else
        log "INFO" "[DRY RUN] Would create container $container_id for $service_name"
    fi
}

setup_nfs_mounts() {
    local container_id="$1"
    local container_config="$2"
    
    # Check if NFS mounts are configured
    local nfs_mounts=$(yq eval '.container.nfs_mounts' "$container_config")
    if [[ "$nfs_mounts" == "null" || "$nfs_mounts" == "[]" ]]; then
        return 0
    fi
    
    local nfs_server=$(get_config '.storage.nfs_server')
    if [[ "$nfs_server" == "null" ]]; then
        log "WARN" "NFS mounts configured but no NFS server specified"
        return 0
    fi
    
    log "INFO" "Setting up NFS mounts for container $container_id"
    
    # Install NFS client
    container_exec "$container_id" apt update
    container_exec "$container_id" apt install -y nfs-common
    
    # Process each mount
    local mount_count=$(yq eval '.container.nfs_mounts | length' "$container_config")
    for ((i=0; i<mount_count; i++)); do
        local source=$(yq eval ".container.nfs_mounts[$i].source" "$container_config")
        local target=$(yq eval ".container.nfs_mounts[$i].target" "$container_config")
        
        if [[ "$source" != "null" && "$target" != "null" ]]; then
            log "DEBUG" "Mounting NFS: $nfs_server:$source -> $target"
            
            container_exec "$container_id" mkdir -p "$target"
            container_exec "$container_id" bash -c "echo '$nfs_server:$source $target nfs defaults 0 0' >> /etc/fstab"
            container_exec "$container_id" mount "$target"
        fi
    done
}

deploy_service_stack() {
    local service_name="$1"
    local container_id="$2"
    local service_dir="$3"
    
    log "INFO" "Deploying Docker stack for $service_name"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create service directory in container
        container_exec "$container_id" mkdir -p "/opt/$service_name"
        
        # Copy docker-compose.yml
        container_push "$container_id" "$service_dir/docker-compose.yml" "/opt/$service_name/docker-compose.yml"
        
        # Copy additional files
        for file in .env config.yml config.yaml settings.ini; do
            if [[ -f "$service_dir/$file" ]]; then
                container_push "$container_id" "$service_dir/$file" "/opt/$service_name/$file"
            fi
        done
        
        # Generate environment file
        generate_service_env "$service_name" "$container_id"
        
        # Deploy the stack
        container_exec "$container_id" bash -c "
            cd /opt/$service_name &&
            docker compose pull &&
            docker compose up -d
        "
        
        log "SUCCESS" "Docker stack deployed for $service_name"
    else
        log "INFO" "[DRY RUN] Would deploy Docker stack for $service_name"
    fi
}

generate_service_env() {
    local service_name="$1"
    local container_id="$2"
    
    log "DEBUG" "Generating environment file for $service_name"
    
    local domain=$(get_config '.cluster.domain')
    local timezone=$(get_config '.cluster.timezone')
    local admin_email=$(get_config '.cluster.admin_email')
    
    # Generate secure passwords
    local mysql_root_password=$(generate_password 32)
    local mysql_password=$(generate_password 32)
    local admin_password=$(generate_password 16)
    local api_key=$(generate_password 32)
    local secret_key=$(generate_password 50)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        container_exec "$container_id" bash -c "cat > /opt/$service_name/.env << 'EOF'
# Auto-generated environment file for $service_name
# Generated on: $(date)
# DO NOT COMMIT THIS FILE TO GIT

# Service configuration
SERVICE_NAME=$service_name
DOMAIN=$domain
SERVICE_DOMAIN=${service_name}.${domain}
TZ=$timezone
ADMIN_EMAIL=$admin_email

# Database passwords
MYSQL_ROOT_PASSWORD=$mysql_root_password
MYSQL_PASSWORD=$mysql_password
MYSQL_USER=$service_name
MYSQL_DATABASE=$service_name
POSTGRES_PASSWORD=$mysql_password
POSTGRES_USER=$service_name
POSTGRES_DB=$service_name

# Application secrets
ADMIN_PASSWORD=$admin_password
API_KEY=$api_key
SECRET_KEY=$secret_key
EOF"
    fi
}

update_service() {
    local service_name="$1"
    local container_id="$2"
    local service_dir="$3"
    
    log "INFO" "Updating existing service: $service_name"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Stop service
        container_exec "$container_id" bash -c "cd /opt/$service_name && docker compose down" || true
        
        # Update configuration files
        container_push "$container_id" "$service_dir/docker-compose.yml" "/opt/$service_name/docker-compose.yml"
        
        # Restart with updated configuration
        container_exec "$container_id" bash -c "
            cd /opt/$service_name &&
            docker compose pull &&
            docker compose up -d
        "
        
        log "SUCCESS" "Service $service_name updated"
    else
        log "INFO" "[DRY RUN] Would update service $service_name"
    fi
}

verify_service_health() {
    local service_name="$1"
    local container_id="$2"
    local timeout="${3:-120}"
    
    log "INFO" "Verifying health of service: $service_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would verify health of $service_name"
        return 0
    fi
    
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        # Check if containers are running
        local running_containers=$(container_exec "$container_id" bash -c "cd /opt/$service_name && docker compose ps -q" 2>/dev/null | wc -l)
        
        if [[ $running_containers -gt 0 ]]; then
            log "SUCCESS" "Service $service_name is healthy ($running_containers containers running)"
            return 0
        fi
        
        sleep 5
        ((elapsed += 5))
    done
    
    log "WARN" "Service $service_name health check timeout after ${timeout}s"
    return 0  # Don't fail deployment for health check timeout
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    deploy_user_services
fi