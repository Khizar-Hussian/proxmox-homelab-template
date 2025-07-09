#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         LXC CONTAINER MANAGEMENT                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Create, configure, and manage LXC containers
# 🐳 Functions: Container lifecycle, Docker setup, resource management

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Deploy core infrastructure containers
# NOTE: This function is deprecated - core services now deployed via services.sh
deploy_core_infrastructure() {
    log "WARN" "deploy_core_infrastructure() is deprecated"
    log "INFO" "Core services are now deployed via services.sh using YAML configurations"
    log "INFO" "This ensures consistency between core and user services"
    return 0
}

# NOTE: Core service deployment functions are deprecated
# Core services (pihole, nginx-proxy, monitoring, authentik) are now
# deployed via services.sh using YAML configurations in config/services/
# This ensures consistency and transparency between core and user services

deploy_core_service() {
    log "WARN" "deploy_core_service() is deprecated - use services.sh instead"
    return 0
}

create_container() {
    local hostname="$1"
    local container_id="$2"
    local container_ip="$3"
    
    log "INFO" "Creating container $container_id ($hostname) at $container_ip"
    
    # Get configuration
    local storage=$(get_config ".proxmox.storage" "local-lvm")
    local template=$(get_config ".proxmox.template" "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst")
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    
    # Get resources
    local cpu=$(get_config ".defaults.cpu" "1")
    local memory=$(get_config ".defaults.memory" "512")
    local disk=$(get_config ".defaults.disk" "8")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create the container
        pct create "$container_id" "$template" \
            --hostname "$hostname" \
            --cores "$cpu" \
            --memory "$memory" \
            --rootfs "$storage:$disk" \
            --net0 "name=eth0,bridge=$bridge,ip=${container_ip}/24,gw=$gateway" \
            --nameserver "$gateway" \
            --features "nesting=1" \
            --unprivileged 1 \
            --start 1
        
        # Wait for container to be ready
        wait_for_container_ready "$container_id"
        
        log "SUCCESS" "Container $container_id created and ready"
    else
        log "INFO" "[DRY RUN] Would create container $container_id with $cpu CPU, ${memory}MB RAM, ${disk}GB disk"
    fi
}

setup_docker_in_container() {
    local container_id="$1"
    
    log "INFO" "Installing Docker in container $container_id"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Install Docker using official script
        pct exec "$container_id" -- bash -c "
            apt update &&
            apt install -y curl ca-certificates &&
            curl -fsSL https://get.docker.com | sh &&
            systemctl enable docker &&
            systemctl start docker &&
            docker --version
        "
        
        # Verify Docker is working
        if ! pct exec "$container_id" -- docker ps &>/dev/null; then
            log "ERROR" "Docker installation failed in container $container_id"
            return 1
        fi
        
        log "SUCCESS" "Docker installed and running in container $container_id"
    else
        log "INFO" "[DRY RUN] Would install Docker in container $container_id"
    fi
}

wait_for_container_ready() {
    local container_id="$1"
    local timeout="${2:-120}"
    
    log "DEBUG" "Waiting for container $container_id to be ready..."
    
    # Wait for container to be running
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if [[ "$(pct status "$container_id" 2>/dev/null | cut -d' ' -f2)" == "running" ]]; then
            break
        fi
        sleep 2
        ((elapsed += 2))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        log "ERROR" "Container $container_id not running after ${timeout}s"
        return 1
    fi
    
    # Wait for network connectivity
    elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if pct exec "$container_id" -- ping -c 1 8.8.8.8 &>/dev/null; then
            log "DEBUG" "Container $container_id network ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        ((elapsed += 2))
    done
    
    log "ERROR" "Container $container_id network not ready after ${timeout}s"
    return 1
}

# Create container from service configuration
create_service_container() {
    local service_name="$1"
    local service_config_dir="${PROJECT_ROOT}/config/services/$service_name"
    
    if [[ ! -d "$service_config_dir" ]]; then
        log "ERROR" "Service configuration directory not found: $service_config_dir"
        return 1
    fi
    
    local container_config="$service_config_dir/container.yaml"
    if [[ ! -f "$container_config" ]]; then
        log "ERROR" "Container configuration not found: $container_config"
        return 1
    fi
    
    # Extract container configuration
    local container_id=$(yq eval '.container.id' "$container_config")
    local hostname=$(yq eval '.container.hostname // .container.id' "$container_config")
    local container_ip=$(yq eval '.container.ip' "$container_config")
    local cpu=$(yq eval '.container.resources.cpu // .defaults.cpu' "$container_config")
    local memory=$(yq eval '.container.resources.memory // .defaults.memory' "$container_config")
    local disk=$(yq eval '.container.resources.disk // .defaults.disk' "$container_config")
    
    # Get default values if not specified
    cpu=${cpu:-$(get_config ".defaults.cpu" "1")}
    memory=${memory:-$(get_config ".defaults.memory" "512")}
    disk=${disk:-$(get_config ".defaults.disk" "8")}
    hostname=${hostname:-$service_name}
    
    log "INFO" "Creating container for service: $service_name"
    log "DEBUG" "Container ID: $container_id, IP: $container_ip, CPU: $cpu, Memory: ${memory}MB, Disk: ${disk}GB"
    
    # Check if container already exists
    if container_exists "$container_id"; then
        local status=$(get_container_status "$container_id")
        log "INFO" "Container $container_id already exists (status: $status)"
        
        if [[ "$status" != "running" ]]; then
            start_container "$container_id"
        fi
        return 0
    fi
    
    # Create the container
    create_container "$hostname" "$container_id" "$container_ip" "$cpu" "$memory" "$disk"
    
    # Setup Docker in container
    setup_docker_in_container "$container_id"
    
    # Apply additional container configuration
    apply_container_config "$container_id" "$container_config"
    
    log "SUCCESS" "Container $container_id created successfully for service $service_name"
}

# Apply additional container configuration
apply_container_config() {
    local container_id="$1"
    local config_file="$2"
    
    # Check for privileged mode
    local privileged=$(yq eval '.container.privileged // false' "$config_file")
    if [[ "$privileged" == "true" ]]; then
        log "INFO" "Configuring container $container_id as privileged"
        if [[ "$DRY_RUN" == "false" ]]; then
            pct set "$container_id" --unprivileged 0
        fi
    fi
    
    # Check for mount points
    local mount_points=$(yq eval '.container.mounts // []' "$config_file")
    if [[ "$mount_points" != "[]" ]]; then
        log "INFO" "Configuring mount points for container $container_id"
        local mount_count=0
        while read -r mount; do
            if [[ -n "$mount" && "$mount" != "null" ]]; then
                local source=$(echo "$mount" | yq eval '.source')
                local destination=$(echo "$mount" | yq eval '.destination')
                local options=$(echo "$mount" | yq eval '.options // ""')
                
                if [[ "$DRY_RUN" == "false" ]]; then
                    pct set "$container_id" --mp${mount_count} "$source:$destination${options:+,$options}"
                else
                    log "INFO" "[DRY RUN] Would mount $source to $destination in container $container_id"
                fi
                ((mount_count++))
            fi
        done < <(echo "$mount_points" | yq eval '.[]')
    fi
    
    # Apply additional features
    local features=$(yq eval '.container.features // {}' "$config_file")
    if [[ "$features" != "{}" ]]; then
        log "INFO" "Configuring features for container $container_id"
        local feature_string=""
        
        # Process common features
        local nesting=$(echo "$features" | yq eval '.nesting // false')
        if [[ "$nesting" == "true" ]]; then
            feature_string="nesting=1"
        fi
        
        local keyctl=$(echo "$features" | yq eval '.keyctl // false')
        if [[ "$keyctl" == "true" ]]; then
            feature_string="${feature_string:+$feature_string,}keyctl=1"
        fi
        
        local fuse=$(echo "$features" | yq eval '.fuse // false')
        if [[ "$fuse" == "true" ]]; then
            feature_string="${feature_string:+$feature_string,}fuse=1"
        fi
        
        if [[ -n "$feature_string" && "$DRY_RUN" == "false" ]]; then
            pct set "$container_id" --features "$feature_string"
        fi
    fi
}

# Enhanced container creation with resource specification
create_container() {
    local hostname="$1"
    local container_id="$2"
    local container_ip="$3"
    local cpu="${4:-1}"
    local memory="${5:-512}"
    local disk="${6:-8}"
    
    log "INFO" "Creating container $container_id ($hostname) at $container_ip"
    
    # Get configuration
    local storage=$(get_config ".proxmox.storage" "local-lvm")
    local template=$(get_config ".proxmox.template" "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst")
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    local nameserver=$(get_config ".networks.management.gateway" "192.168.1.1")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create the container
        pct create "$container_id" "$template" \
            --hostname "$hostname" \
            --cores "$cpu" \
            --memory "$memory" \
            --rootfs "$storage:$disk" \
            --net0 "name=eth0,bridge=$bridge,ip=${container_ip}/24,gw=$gateway" \
            --nameserver "$nameserver" \
            --features "nesting=1" \
            --unprivileged 1 \
            --start 1 \
            --onboot 1 \
            --ostype ubuntu \
            --password "$(generate_password)"
        
        # Wait for container to be ready
        wait_for_container_ready "$container_id"
        
        # Update container packages
        update_container_packages "$container_id"
        
        log "SUCCESS" "Container $container_id created and ready"
    else
        log "INFO" "[DRY RUN] Would create container $container_id with $cpu CPU, ${memory}MB RAM, ${disk}GB disk"
    fi
}

# Update container packages
update_container_packages() {
    local container_id="$1"
    
    log "INFO" "Updating packages in container $container_id"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        pct exec "$container_id" -- bash -c "
            apt update &&
            apt upgrade -y &&
            apt install -y curl wget git unzip zip htop nano
        "
    else
        log "INFO" "[DRY RUN] Would update packages in container $container_id"
    fi
}

# Install Docker Compose in container
install_docker_compose() {
    local container_id="$1"
    
    log "INFO" "Installing Docker Compose in container $container_id"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        pct exec "$container_id" -- bash -c "
            # Install Docker Compose
            curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)\" -o /usr/local/bin/docker-compose &&
            chmod +x /usr/local/bin/docker-compose &&
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose &&
            docker-compose --version
        "
        
        # Verify installation
        if ! pct exec "$container_id" -- docker-compose --version &>/dev/null; then
            log "ERROR" "Docker Compose installation failed in container $container_id"
            return 1
        fi
        
        log "SUCCESS" "Docker Compose installed in container $container_id"
    else
        log "INFO" "[DRY RUN] Would install Docker Compose in container $container_id"
    fi
}

# Generate a secure random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Get container resource usage
get_container_resources() {
    local container_id="$1"
    
    if container_exists "$container_id"; then
        pct exec "$container_id" -- bash -c "
            echo \"CPU: \$(cat /proc/loadavg | cut -d' ' -f1)\"
            echo \"Memory: \$(free -h | grep Mem | awk '{print \$3\"/\"\$2}')\"
            echo \"Disk: \$(df -h / | tail -1 | awk '{print \$3\"/\"\$2\" (\"\$5\" used)\"}')\"
        "
    else
        log "ERROR" "Container $container_id does not exist"
        return 1
    fi
}

# List all containers managed by this system
list_containers() {
    log "INFO" "Listing containers managed by homelab template"
    
    # Get all containers with homelab labels
    pct list | grep -E "^[0-9]+" | while read -r line; do
        local container_id=$(echo "$line" | awk '{print $1}')
        local status=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | awk '{print $3}')
        
        # Check if this container has homelab labels
        if pct config "$container_id" 2>/dev/null | grep -q "com.homelab"; then
            printf "%-5s %-10s %-20s %s\n" "$container_id" "$status" "$name" "$(get_container_ip "$container_id")"
        fi
    done
}

# Get container IP address
get_container_ip() {
    local container_id="$1"
    pct config "$container_id" 2>/dev/null | grep -oP 'ip=\K[^/,]+' | head -1
}

# Container utility functions
container_exists() {
    local container_id="$1"
    pct status "$container_id" &>/dev/null
}

get_container_status() {
    local container_id="$1"
    pct status "$container_id" 2>/dev/null | cut -d' ' -f2
}

start_container() {
    local container_id="$1"
    
    if [[ "$(get_container_status "$container_id")" != "running" ]]; then
        log "INFO" "Starting container $container_id"
        if [[ "$DRY_RUN" == "false" ]]; then
            pct start "$container_id"
        fi
    fi
}

stop_container() {
    local container_id="$1"
    
    if [[ "$(get_container_status "$container_id")" == "running" ]]; then
        log "INFO" "Stopping container $container_id"
        if [[ "$DRY_RUN" == "false" ]]; then
            pct stop "$container_id"
        fi
    fi
}

destroy_container() {
    local container_id="$1"
    
    log "WARN" "Destroying container $container_id"
    if [[ "$DRY_RUN" == "false" ]]; then
        stop_container "$container_id"
        pct destroy "$container_id"
    fi
}

# Execute command in container
container_exec() {
    local container_id="$1"
    shift
    
    if [[ "$DRY_RUN" == "false" ]]; then
        pct exec "$container_id" -- "$@"
    else
        log "INFO" "[DRY RUN] Would execute in container $container_id: $*"
    fi
}

# Copy file to container
container_push() {
    local container_id="$1"
    local source="$2"
    local destination="$3"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        pct push "$container_id" "$source" "$destination"
    else
        log "INFO" "[DRY RUN] Would copy $source to container $container_id:$destination"
    fi
}

# Copy file from container
container_pull() {
    local container_id="$1"
    local source="$2"
    local destination="$3"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        pct pull "$container_id" "$source" "$destination"
    else
        log "INFO" "[DRY RUN] Would copy $source from container $container_id to $destination"
    fi
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    CONTAINERS_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    deploy_core_infrastructure
fi