#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                           NETWORK CONFIGURATION                             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Setup Proxmox network bridges and container networking
# 🌐 Creates: Container bridge, firewall rules, IP forwarding

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

setup_networking() {
    log "STEP" "Setting up Proxmox networking..."
    
    setup_container_bridge || return 1
    configure_ip_forwarding || return 1
    setup_firewall_rules || return 1
    
    log "SUCCESS" "Network setup completed"
}

setup_container_bridge() {
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local subnet=$(get_config ".networks.containers.subnet" "10.0.0.0/24")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    
    log "INFO" "Setting up container bridge: $bridge"
    
    # Check if bridge already exists
    if ip link show "$bridge" &>/dev/null; then
        log "DEBUG" "Bridge $bridge already exists"
        return 0
    fi
    
    log "INFO" "Creating bridge $bridge with gateway $gateway"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Add bridge configuration to Proxmox
        cat >> /etc/network/interfaces << EOF

# Container network bridge for homelab (auto-generated)
auto $bridge
iface $bridge inet static
    address $gateway/24
    bridge_ports none
    bridge_stp off
    bridge_fd 0
    post-up iptables -t nat -A POSTROUTING -s $subnet ! -d $subnet -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s $subnet ! -d $subnet -j MASQUERADE
EOF
        
        # Bring up the bridge
        ifup "$bridge"
        
        # Verify bridge is up
        if ! ip link show "$bridge" &>/dev/null; then
            log "ERROR" "Failed to create bridge $bridge"
            return 1
        fi
        
        log "SUCCESS" "Bridge $bridge created successfully"
    else
        log "INFO" "[DRY RUN] Would create bridge $bridge with subnet $subnet"
    fi
}

configure_ip_forwarding() {
    log "INFO" "Configuring IP forwarding..."
    
    # Check if already enabled
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) == "1" ]]; then
        log "DEBUG" "IP forwarding already enabled"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Enable IP forwarding
        echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
        sysctl -p
        
        log "SUCCESS" "IP forwarding enabled"
    else
        log "INFO" "[DRY RUN] Would enable IP forwarding"
    fi
}

setup_firewall_rules() {
    local container_subnet=$(get_config ".networks.containers.subnet" "10.0.0.0/24")
    
    log "INFO" "Setting up firewall rules for container network..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Allow container traffic
        iptables -A FORWARD -s "$container_subnet" -j ACCEPT
        iptables -A FORWARD -d "$container_subnet" -j ACCEPT
        
        # Save iptables rules
        if command_exists iptables-save; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        
        log "SUCCESS" "Firewall rules configured"
    else
        log "INFO" "[DRY RUN] Would configure firewall rules for $container_subnet"
    fi
}

# Test network connectivity
test_network_connectivity() {
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    
    log "INFO" "Testing network connectivity..."
    
    # Test bridge exists and is up
    if ! ip link show "$bridge" | grep -q "state UP"; then
        log "ERROR" "Bridge $bridge is not up"
        return 1
    fi
    
    # Test gateway is reachable
    if ! ping -c 1 -W 2 "$gateway" &>/dev/null; then
        log "ERROR" "Gateway $gateway is not reachable"
        return 1
    fi
    
    log "SUCCESS" "Network connectivity test passed"
}

# Configure external access via Cloudflare tunnels
setup_external_access() {
    local cloudflare_enabled=$(get_config ".external_access.cloudflare.enabled" "false")
    
    if [[ "$cloudflare_enabled" != "true" ]]; then
        log "INFO" "Cloudflare tunnels not enabled, skipping external access setup"
        return 0
    fi
    
    log "INFO" "Setting up Cloudflare tunnels for external access..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Install cloudflared if not present
        if ! command_exists cloudflared; then
            install_cloudflared || return 1
        fi
        
        # Configure tunnel
        configure_cloudflare_tunnel || return 1
        
        log "SUCCESS" "External access configured"
    else
        log "INFO" "[DRY RUN] Would setup Cloudflare tunnels"
    fi
}

# Install cloudflared
install_cloudflared() {
    log "INFO" "Installing cloudflared..."
    
    # Download and install cloudflared
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i cloudflared.deb
    rm cloudflared.deb
    
    log "SUCCESS" "cloudflared installed"
}

# Configure Cloudflare tunnel
configure_cloudflare_tunnel() {
    local tunnel_name=$(get_config ".external_access.cloudflare.tunnel_name" "homelab-tunnel")
    local domain=$(get_config ".cluster.domain")
    
    log "INFO" "Configuring Cloudflare tunnel: $tunnel_name"
    
    # Create tunnel configuration
    mkdir -p /etc/cloudflared
    
    cat > /etc/cloudflared/config.yml << EOF
tunnel: $tunnel_name
credentials-file: /etc/cloudflared/tunnel.json

ingress:
  - hostname: $domain
    service: http://$(get_config ".networks.containers.gateway"):80
  - hostname: "*.${domain}"
    service: http://$(get_config ".networks.containers.gateway"):80
  - service: http_status:404
EOF
    
    log "SUCCESS" "Cloudflare tunnel configuration created"
}

# Setup network monitoring
setup_network_monitoring() {
    log "INFO" "Setting up network monitoring..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Install network monitoring tools
        apt update
        apt install -y iftop nethogs nload
        
        # Create network monitoring script
        cat > /usr/local/bin/network-monitor << 'EOF'
#!/bin/bash
# Simple network monitoring for homelab

echo "=== Network Interface Status ==="
ip addr show | grep -E "^[0-9]+:|inet "

echo -e "\n=== Bridge Status ==="
brctl show 2>/dev/null || echo "brctl not available"

echo -e "\n=== Container Network Status ==="
for bridge in vmbr0 vmbr1; do
    if ip link show "$bridge" &>/dev/null; then
        echo "$bridge: $(ip addr show "$bridge" | grep -o 'inet [^/]*' | cut -d' ' -f2)"
    fi
done

echo -e "\n=== Network Connections ==="
ss -tuln | head -20
EOF
        
        chmod +x /usr/local/bin/network-monitor
        
        log "SUCCESS" "Network monitoring tools installed"
    else
        log "INFO" "[DRY RUN] Would setup network monitoring"
    fi
}

# Reset networking to defaults
reset_networking() {
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    
    log "WARN" "Resetting network configuration..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove bridge
        if ip link show "$bridge" &>/dev/null; then
            ifdown "$bridge" 2>/dev/null || true
            ip link delete "$bridge" 2>/dev/null || true
        fi
        
        # Remove from interfaces file
        sed -i "/# Container network bridge for homelab/,/^$/d" /etc/network/interfaces
        
        # Remove NAT rules
        local subnet=$(get_config ".networks.containers.subnet" "10.0.0.0/24")
        iptables -t nat -D POSTROUTING -s "$subnet" ! -d "$subnet" -j MASQUERADE 2>/dev/null || true
        
        log "SUCCESS" "Network configuration reset"
    else
        log "INFO" "[DRY RUN] Would reset network configuration"
    fi
}

# Get network information
get_network_info() {
    log "INFO" "Network Information:"
    
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local subnet=$(get_config ".networks.containers.subnet" "10.0.0.0/24")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    
    echo "Container Bridge: $bridge"
    echo "Container Subnet: $subnet"
    echo "Container Gateway: $gateway"
    
    if ip link show "$bridge" &>/dev/null; then
        echo "Bridge Status: UP"
        local bridge_ip=$(ip addr show "$bridge" | grep -o 'inet [^/]*' | cut -d' ' -f2)
        echo "Bridge IP: ${bridge_ip:-Not assigned}"
    else
        echo "Bridge Status: DOWN"
    fi
    
    echo "IP Forwarding: $(cat /proc/sys/net/ipv4/ip_forward)"
    
    # Show active containers on bridge
    if command_exists pct; then
        echo -e "\nContainers on bridge:"
        pct list | grep -E "^[0-9]+" | while read -r line; do
            local container_id=$(echo "$line" | awk '{print $1}')
            local name=$(echo "$line" | awk '{print $3}')
            local ip=$(pct config "$container_id" 2>/dev/null | grep -oP 'ip=\K[^/,]+' | head -1)
            if [[ -n "$ip" ]]; then
                printf "  %-5s %-20s %s\n" "$container_id" "$name" "$ip"
            fi
        done
    fi
}

# Validate network configuration on Proxmox host
validate_proxmox_network_config() {
    log "INFO" "Validating network configuration..."
    
    local errors=0
    local bridge=$(get_config ".networks.containers.bridge" "vmbr1")
    local subnet=$(get_config ".networks.containers.subnet" "10.0.0.0/24")
    local gateway=$(get_config ".networks.containers.gateway" "10.0.0.1")
    
    # Check if bridge exists (only if we're not in initial deployment)
    if ip link show "$bridge" &>/dev/null; then
        log "INFO" "Bridge $bridge exists"
        
        # Check gateway IP is configured
        if ! ip addr show "$bridge" | grep -q "$gateway"; then
            log "ERROR" "Gateway IP $gateway not configured on bridge $bridge"
            ((errors++))
        fi
    else
        log "INFO" "Bridge $bridge does not exist yet - will be created during deployment"
    fi
    
    # Check if IP forwarding is enabled (only warn, don't fail)
    if [[ $(cat /proc/sys/net/ipv4/ip_forward) != "1" ]]; then
        log "WARN" "IP forwarding is not enabled - will be enabled during deployment"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "SUCCESS" "Network configuration validation passed"
        return 0
    else
        log "ERROR" "Network configuration validation failed ($errors errors)"
        return 1
    fi
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.json}"
    NETWORKING_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    setup_networking
fi