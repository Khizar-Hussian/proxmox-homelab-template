#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          PREREQUISITES CHECKER                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Check system requirements and dependencies
# 📦 Validates: Commands, permissions, environment variables, resources

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

check_prerequisites() {
    log "STEP" "Checking system prerequisites..."
    
    check_permissions || return 1
    check_required_commands || return 1
    check_environment_variables || return 1
    check_system_resources || return 1
    check_cluster_config || return 1
    
    log "SUCCESS" "All prerequisites satisfied"
}

check_permissions() {
    log "INFO" "Checking permissions..."
    
    if has_root_access; then
        log "DEBUG" "Root access confirmed"
        return 0
    else
        log "ERROR" "This script requires root access or sudo privileges"
        log "INFO" "Run with: sudo ./scripts/deploy.sh"
        return 1
    fi
}

check_required_commands() {
    log "INFO" "Checking required commands..."
    
    local required_commands=(
        "curl"          # HTTP requests
        "jq"            # JSON processing
        "yq"            # YAML processing
        "pvesh"         # Proxmox API
        "pct"           # LXC container management
        "docker"        # Docker engine
        "openssl"       # Password generation
    )
    
    local missing_commands=()
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        else
            log "DEBUG" "✓ $cmd found"
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Missing required commands: ${missing_commands[*]}"
        show_installation_help "${missing_commands[@]}"
        return 1
    fi
    
    log "SUCCESS" "All required commands available"
}

show_installation_help() {
    local -a missing=("$@")
    
    echo
    log "INFO" "To install missing dependencies:"
    echo
    
    # Basic packages
    if [[ " ${missing[*]} " =~ " curl " ]] || [[ " ${missing[*]} " =~ " jq " ]]; then
        echo "  # Install basic tools:"
        echo "  apt update && apt install -y curl jq"
    fi
    
    # yq (YAML processor)
    if [[ " ${missing[*]} " =~ " yq " ]]; then
        echo "  # Install yq (YAML processor):"
        echo "  wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        echo "  chmod +x /usr/local/bin/yq"
    fi
    
    # Docker
    if [[ " ${missing[*]} " =~ " docker " ]]; then
        echo "  # Install Docker:"
        echo "  curl -fsSL https://get.docker.com | sh"
        echo "  systemctl enable --now docker"
    fi
    
    # Proxmox tools
    if [[ " ${missing[*]} " =~ " pvesh " ]] || [[ " ${missing[*]} " =~ " pct " ]]; then
        log "WARN" "Proxmox tools missing - ensure you're running on Proxmox host"
    fi
    
    echo
}

check_environment_variables() {
    log "INFO" "Checking environment variables..."
    
    # Load .env file if it exists
    local env_file="${PROJECT_ROOT}/.env"
    if [[ -f "$env_file" ]]; then
        log "DEBUG" "Loading environment from .env file"
        set -a
        source "$env_file"
        set +a
    fi
    
    # Required variables
    local required_vars=(
        "PROXMOX_HOST"
        "PROXMOX_TOKEN"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        else
            log "DEBUG" "✓ $var is set"
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        log "INFO" "Set these in GitHub repository secrets or create .env file:"
        echo
        for var in "${missing_vars[@]}"; do
            echo "  $var=your_value_here"
        done
        echo
        return 1
    fi
    
    log "SUCCESS" "Environment variables configured"
}

check_system_resources() {
    log "INFO" "Checking system resources..."
    
    # Check RAM (minimum 2GB recommended)
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))
    
    if [[ $total_ram_gb -lt 2 ]]; then
        log "WARN" "Low RAM: ${total_ram_gb}GB (minimum 2GB recommended)"
    else
        log "DEBUG" "✓ RAM: ${total_ram_gb}GB"
    fi
    
    # Check disk space (minimum 20GB recommended)
    local available_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    
    if [[ $available_gb -lt 20 ]]; then
        log "WARN" "Low disk space: ${available_gb}GB available (minimum 20GB recommended)"
    else
        log "DEBUG" "✓ Disk space: ${available_gb}GB available"
    fi
    
    log "SUCCESS" "System resources adequate"
}

check_cluster_config() {
    log "INFO" "Checking cluster configuration..."
    
    if [[ ! -f "$CLUSTER_CONFIG" ]]; then
        log "ERROR" "Cluster configuration not found: $CLUSTER_CONFIG"
        log "INFO" "Copy the example: cp .env.example .env"
        return 1
    fi
    
    # Basic YAML syntax check
    if ! yq eval '.' "$CLUSTER_CONFIG" > /dev/null 2>&1; then
        log "ERROR" "Invalid YAML syntax in $CLUSTER_CONFIG"
        return 1
    fi
    
    log "SUCCESS" "Cluster configuration found and valid"
}

# Allow running this script standalone for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.json}"
    PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    check_prerequisites
fi