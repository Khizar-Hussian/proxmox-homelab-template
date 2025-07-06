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

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    setup_networking
fi