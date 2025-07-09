#!/bin/bash

# Simple, direct validation script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_ROOT/.env"
CONFIG_FILE="$PROJECT_ROOT/config/cluster.json"

# Load environment variables
if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Error: .env file not found at $ENV_FILE"
    exit 1
fi

echo "🔐 Loading environment variables..."
set -a  # Export all variables
source "$ENV_FILE"
set +a  # Stop exporting

# Validate required variables
echo "🔍 Validating required environment variables..."
REQUIRED_VARS=(
    "DOMAIN"
    "ADMIN_EMAIL" 
    "PROXMOX_HOST"
    "MANAGEMENT_SUBNET"
    "MANAGEMENT_GATEWAY"
    "NFS_SERVER"
    "PROXMOX_TOKEN"
    "CLOUDFLARE_API_TOKEN"
    "AUTHENTIK_ADMIN_PASSWORD"
)

missing_vars=()
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "❌ Missing required variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

echo "✅ All required environment variables are present"

# Process configuration with envsubst
echo "📋 Processing configuration..."
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Create processed config
PROCESSED_CONFIG=$(envsubst < "$CONFIG_FILE")

# Validate JSON syntax
echo "🔍 Validating JSON syntax..."
if ! echo "$PROCESSED_CONFIG" | jq . >/dev/null 2>&1; then
    echo "❌ Invalid JSON in configuration file"
    exit 1
fi
echo "✅ JSON syntax is valid"

# Extract and validate network values
echo "🌐 Validating network configuration..."

MGMT_SUBNET=$(echo "$PROCESSED_CONFIG" | jq -r '.networking.management.subnet // empty')
MGMT_GATEWAY=$(echo "$PROCESSED_CONFIG" | jq -r '.networking.management.gateway // empty')  
PROXMOX_IP=$(echo "$PROCESSED_CONFIG" | jq -r '.proxmox.host // empty')
NFS_IP=$(echo "$PROCESSED_CONFIG" | jq -r '.storage.nfs_server // empty')

echo "  Management subnet: $MGMT_SUBNET"
echo "  Management gateway: $MGMT_GATEWAY"
echo "  Proxmox host: $PROXMOX_IP"
echo "  NFS server: $NFS_IP"

# Validate IP format
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
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
        if validate_ip "$ip_part" && [[ $cidr_part -ge 1 && $cidr_part -le 32 ]]; then
            return 0
        fi
    fi
    return 1
}

errors=0

# Validate subnet
if [[ -z "$MGMT_SUBNET" ]] || ! validate_subnet "$MGMT_SUBNET"; then
    echo "❌ Invalid management subnet format: $MGMT_SUBNET"
    ((errors++))
fi

# Validate gateway
if [[ -z "$MGMT_GATEWAY" ]] || ! validate_ip "$MGMT_GATEWAY"; then
    echo "❌ Invalid management gateway IP: $MGMT_GATEWAY"
    ((errors++))
fi

# Validate Proxmox host
if [[ -z "$PROXMOX_IP" ]] || ! validate_ip "$PROXMOX_IP"; then
    echo "❌ Invalid Proxmox host IP: $PROXMOX_IP"
    ((errors++))
fi

# Validate NFS server
if [[ -z "$NFS_IP" ]] || ! validate_ip "$NFS_IP"; then
    echo "❌ Invalid NFS server IP: $NFS_IP"
    ((errors++))
fi

if [[ $errors -eq 0 ]]; then
    echo "✅ All network configuration is valid"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Domain: $(echo "$PROCESSED_CONFIG" | jq -r '.cluster.domain // "Not configured"')"
    echo "  Cluster: $(echo "$PROCESSED_CONFIG" | jq -r '.cluster.name // "Not configured"')"
    echo "  Admin: $(echo "$PROCESSED_CONFIG" | jq -r '.cluster.admin_email // "Not configured"')"
    echo "  Proxmox: $PROXMOX_IP"
    echo "  NFS: $NFS_IP"
    echo "  Management Network: $MGMT_SUBNET (Gateway: $MGMT_GATEWAY)"
    exit 0
else
    echo "❌ Found $errors network configuration errors"
    exit 1
fi