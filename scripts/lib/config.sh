#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     CONFIGURATION MANAGEMENT LIBRARY                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Centralized configuration loading and management for JSON configs
# 📝 USAGE: Source this file in other scripts to access configuration functions
# 🔧 FEATURES: Environment variable substitution, validation, caching

# Configuration paths
LIB_SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
HOMELAB_ROOT="$(dirname "$(dirname "$LIB_SCRIPT_DIR")")"
CONFIG_DIR="${CONFIG_DIR:-$HOMELAB_ROOT/config}"
CLUSTER_CONFIG_FILE="${CONFIG_DIR}/cluster.json"
ENV_FILE="${HOMELAB_ROOT}/.env"

# Global variables
CLUSTER_CONFIG=""
SECRETS_LOADED=false

# ══════════════════════════════════════════════════════════════════════════════
# 🔐 SECRETS MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

# Load secrets from .env file
load_secrets() {
    local env_file="${1:-$ENV_FILE}"
    
    if [[ ! -f "$env_file" ]]; then
        echo "❌ Error: .env file not found at $env_file" >&2
        echo "💡 Tip: Copy .env.example to .env and fill in your values" >&2
        return 1
    fi
    
    echo "🔐 Loading secrets from $env_file..."
    
    # Load environment variables, ignoring comments and empty lines
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Export the variable
        export "$line"
    done < "$env_file"
    
    SECRETS_LOADED=true
    echo "✅ Secrets loaded successfully"
}

# Validate that required secrets are set
validate_secrets() {
    local required_secrets=(
        "PROXMOX_TOKEN"
        "CLOUDFLARE_API_TOKEN"
        "AUTHENTIK_ADMIN_PASSWORD"
        "DOMAIN"
        "ADMIN_EMAIL"
        "PROXMOX_HOST"
        "MANAGEMENT_SUBNET"
        "MANAGEMENT_GATEWAY"
        "NFS_SERVER"
    )
    
    local missing_secrets=()
    
    for secret in "${required_secrets[@]}"; do
        if [[ -z "${!secret}" ]]; then
            missing_secrets+=("$secret")
        fi
    done
    
    if [[ ${#missing_secrets[@]} -gt 0 ]]; then
        echo "❌ Error: Missing required secrets:" >&2
        for secret in "${missing_secrets[@]}"; do
            echo "  - $secret" >&2
        done
        echo "" >&2
        echo "💡 Please add these to your .env file" >&2
        return 1
    fi
    
    echo "✅ All required secrets are present"
}

# ══════════════════════════════════════════════════════════════════════════════
# 📋 CLUSTER CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

# Load cluster configuration with environment variable substitution
load_cluster_config() {
    if [[ ! -f "$CLUSTER_CONFIG_FILE" ]]; then
        echo "❌ Error: Cluster config not found at $CLUSTER_CONFIG_FILE" >&2
        return 1
    fi
    
    if [[ "$SECRETS_LOADED" != "true" ]]; then
        echo "⚠️  Warning: Secrets not loaded, some variables may not be substituted" >&2
    fi
    
    echo "📋 Loading cluster configuration..."
    
    # Substitute environment variables in the JSON config
    CLUSTER_CONFIG=$(envsubst < "$CLUSTER_CONFIG_FILE")
    
    # Validate JSON syntax
    if ! echo "$CLUSTER_CONFIG" | jq . >/dev/null 2>&1; then
        echo "❌ Error: Invalid JSON in cluster configuration" >&2
        return 1
    fi
    
    echo "✅ Cluster configuration loaded successfully"
}

# Get a configuration value using jq path
get_config() {
    local path="$1"
    local default_value="${2:-}"
    
    if [[ -z "$CLUSTER_CONFIG" ]]; then
        echo "❌ Error: Cluster configuration not loaded" >&2
        return 1
    fi
    
    local value
    value=$(echo "$CLUSTER_CONFIG" | jq -r "$path // empty")
    
    if [[ -z "$value" || "$value" == "null" ]]; then
        if [[ -n "$default_value" ]]; then
            echo "$default_value"
        else
            echo "❌ Error: Configuration value not found: $path" >&2
            return 1
        fi
    else
        echo "$value"
    fi
}

# Get multiple configuration values as JSON array
get_config_array() {
    local path="$1"
    
    if [[ -z "$CLUSTER_CONFIG" ]]; then
        echo "❌ Error: Cluster configuration not loaded" >&2
        return 1
    fi
    
    echo "$CLUSTER_CONFIG" | jq -r "$path[]? // empty"
}

# Check if a feature is enabled (returns true if secret exists and feature is enabled)
feature_enabled() {
    local feature_path="$1"
    local secret_name="$2"
    
    # Check if feature is explicitly disabled
    local feature_value
    feature_value=$(get_config "$feature_path" "true")
    
    if [[ "$feature_value" == "false" ]]; then
        return 1
    fi
    
    # If secret name provided, check if secret exists
    if [[ -n "$secret_name" ]]; then
        if [[ -z "${!secret_name}" ]]; then
            return 1
        fi
    fi
    
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 UTILITY FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

# Initialize configuration system
init_config() {
    echo "🚀 Initializing configuration system..."
    
    # Load secrets first
    if ! load_secrets; then
        return 1
    fi
    
    # Validate required secrets
    if ! validate_secrets; then
        return 1
    fi
    
    # Load cluster configuration
    if ! load_cluster_config; then
        return 1
    fi
    
    echo "✅ Configuration system initialized successfully"
}

# Print configuration summary
print_config_summary() {
    echo "📋 Configuration Summary:"
    echo "  Domain: $(get_config '.cluster.domain')"
    echo "  Cluster: $(get_config '.cluster.name')"
    echo "  Admin: $(get_config '.cluster.admin_email')"
    echo "  Proxmox: $(get_config '.proxmox.host')"
    echo "  NFS: $(get_config '.storage.nfs_server')"
    echo ""
    echo "🔧 Optional Features:"
    echo "  VPN: $(feature_enabled '.security.vpn.enabled' 'NORDVPN_PRIVATE_KEY' && echo 'enabled' || echo 'disabled')"
    echo "  Cloudflare Tunnel: $(feature_enabled '.external_access.cloudflare.enabled' 'CLOUDFLARE_TUNNEL_TOKEN' && echo 'enabled' || echo 'disabled')"
    echo "  Monitoring: $(feature_enabled '.monitoring.enabled' && echo 'enabled' || echo 'disabled')"
    echo "  Backups: $(feature_enabled '.backups.enabled' && echo 'enabled' || echo 'disabled')"
}

# Export functions for use in other scripts
export -f load_secrets validate_secrets load_cluster_config get_config get_config_array feature_enabled init_config print_config_summary