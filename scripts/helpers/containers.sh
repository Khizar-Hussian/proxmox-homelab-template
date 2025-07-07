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

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    deploy_core_infrastructure
fi