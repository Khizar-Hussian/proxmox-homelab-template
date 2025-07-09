#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     CONFIGURATION MANAGEMENT LIBRARY                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Centralized configuration loading and management for JSON configs
# 📝 USAGE: Source this file in other scripts to access configuration functions
# 🔧 FEATURES: Environment variable substitution, validation, caching

# Guard against multiple sourcing
if [[ -n "${CONFIG_SH_SOURCED:-}" ]]; then
    return 0
fi
readonly CONFIG_SH_SOURCED=1

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
        
        # Trim whitespace and ensure proper format
        line=$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        
        # Skip if line doesn't contain =
        [[ "$line" =~ = ]] || continue
        
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
    
    # Ensure all variables are available to envsubst by explicitly exporting them
    # This addresses the issue where function-scoped exports might not be visible to subprocesses
    set -a  # Automatically export all variables
    
    # Re-source the env file to ensure variables are available to subprocesses
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
    
    # Set default values for optional variables that might not be in .env
    export CLUSTER_NAME="${CLUSTER_NAME:-homelab}"
    export TIMEZONE="${TIMEZONE:-America/New_York}"
    export INTERNAL_DOMAIN="${INTERNAL_DOMAIN:-$DOMAIN}"
    export VPN_ENABLED="${VPN_ENABLED:-true}"
    
    # Explicitly export all required variables to ensure they're available to envsubst
    export DOMAIN ADMIN_EMAIL PROXMOX_HOST MANAGEMENT_SUBNET MANAGEMENT_GATEWAY NFS_SERVER
    export PROXMOX_TOKEN CLOUDFLARE_API_TOKEN AUTHENTIK_ADMIN_PASSWORD
    
    set +a  # Turn off automatic export
    
    # Substitute environment variables in the JSON config
    # Create a temporary file with bash-style defaults replaced by simple variables
    local temp_config=$(mktemp)
    
    # Replace bash-style defaults with actual values
    sed \
        -e "s/\${CLUSTER_NAME:-homelab}/${CLUSTER_NAME}/g" \
        -e "s/\${TIMEZONE:-America\/New_York}/${TIMEZONE//\//\\/}/g" \
        -e "s/\${INTERNAL_DOMAIN:-\${DOMAIN}}/${INTERNAL_DOMAIN}/g" \
        -e "s/\${VPN_ENABLED:-true}/${VPN_ENABLED}/g" \
        "$CLUSTER_CONFIG_FILE" > "$temp_config"
    
    # Now use envsubst on the preprocessed file
    CLUSTER_CONFIG=$(envsubst < "$temp_config")
    
    # Clean up
    rm -f "$temp_config"
    
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
    local secret_name="${2:-}"
    
    # Check if feature is explicitly disabled
    local feature_value
    feature_value=$(get_config "$feature_path" "true")
    
    if [[ "$feature_value" == "false" ]]; then
        return 1
    fi
    
    # If secret name provided, check if secret exists
    if [[ -n "$secret_name" ]]; then
        if [[ -z "${!secret_name:-}" ]]; then
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

# Print configuration summary using direct approach
print_config_summary() {
    echo "📋 Configuration Summary:"
    
    # Use the same reliable approach as simple validation
    set -a
    source "$ENV_FILE"
    # Set defaults for variables that might not be in .env
    export CLUSTER_NAME="${CLUSTER_NAME:-homelab}"
    export TIMEZONE="${TIMEZONE:-America/New_York}"
    set +a
    
    # First handle bash-style defaults that envsubst doesn't understand
    local temp_config=$(mktemp)
    sed \
        -e "s/\${CLUSTER_NAME:-homelab}/${CLUSTER_NAME}/g" \
        -e "s/\${TIMEZONE:-America\/New_York}/${TIMEZONE//\//\\/}/g" \
        "$CLUSTER_CONFIG_FILE" > "$temp_config"
    
    local processed_config=$(envsubst < "$temp_config")
    rm -f "$temp_config"
    
    local domain cluster admin proxmox nfs
    domain=$(echo "$processed_config" | jq -r '.cluster.domain // "Not configured"')
    cluster=$(echo "$processed_config" | jq -r '.cluster.name // "Not configured"')
    admin=$(echo "$processed_config" | jq -r '.cluster.admin_email // "Not configured"')
    proxmox=$(echo "$processed_config" | jq -r '.proxmox.host // "Not configured"')
    nfs=$(echo "$processed_config" | jq -r '.storage.nfs_server // "Not configured"')
    
    echo "  Domain: $domain"
    echo "  Cluster: $cluster"
    echo "  Admin: $admin"
    echo "  Proxmox: $proxmox"
    echo "  NFS: $nfs"
    echo ""
    echo "🔧 Optional Features:"
    echo "  VPN: $([[ "${VPN_ENABLED:-true}" == "true" ]] && echo 'enabled' || echo 'disabled')"
    echo "  Cloudflare Tunnel: $([[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]] && echo 'enabled' || echo 'disabled')"
    echo "  Monitoring: enabled"
    echo "  Backups: enabled"
}

# Export functions for use in other scripts
export -f load_secrets validate_secrets load_cluster_config get_config get_config_array feature_enabled init_config print_config_summary