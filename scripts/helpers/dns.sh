#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        DNS AND PROXY CONFIGURATION                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Configure Pi-hole DNS and Nginx Proxy Manager
# 🌐 Features: Local DNS records, SSL certificates, reverse proxy setup

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/containers.sh"

configure_dns_and_proxy() {
    log "STEP" "Configuring DNS and reverse proxy..."
    
    configure_pihole_dns || return 1
    configure_nginx_proxy || return 1
    setup_local_dns_records || return 1
    
    log "SUCCESS" "DNS and proxy configuration completed"
}

configure_pihole_dns() {
    local pihole_ip=$(get_config '.networks.core_services.pihole')
    
    if [[ "$pihole_ip" == "null" ]]; then
        log "WARN" "Pi-hole not configured, skipping DNS setup"
        return 0
    fi
    
    local container_id="1${pihole_ip##*.}"
    
    log "INFO" "Configuring Pi-hole DNS settings..."
    
    if ! container_exists "$container_id"; then
        log "WARN" "Pi-hole container $container_id not found, skipping DNS configuration"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for Pi-hole to be ready
        local timeout=60
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if container_exec "$container_id" docker ps | grep -q pihole; then
                break
            fi
            sleep 2
            ((elapsed += 2))
        done
        
        # Configure upstream DNS servers
        local upstream_servers=$(get_config '.dns.upstream_servers' '["1.1.1.1", "8.8.8.8"]')
        
        # Update Pi-hole DNS settings
        container_exec "$container_id" bash -c "
            # Wait for Pi-hole to be fully ready
            sleep 10
            
            # Configure upstream DNS
            echo 'server=1.1.1.1' >> /opt/pihole/etc-dnsmasq.d/99-upstream.conf
            echo 'server=8.8.8.8' >> /opt/pihole/etc-dnsmasq.d/99-upstream.conf
            
            # Restart Pi-hole to apply changes
            docker exec pihole pihole restartdns
        "
        
        log "SUCCESS" "Pi-hole DNS configured"
    else
        log "INFO" "[DRY RUN] Would configure Pi-hole DNS settings"
    fi
}

configure_nginx_proxy() {
    local nginx_ip=$(get_config '.networks.core_services.nginx_proxy')
    
    if [[ "$nginx_ip" == "null" ]]; then
        log "WARN" "Nginx Proxy Manager not configured, skipping proxy setup"
        return 0
    fi
    
    local container_id="1${nginx_ip##*.}"
    
    log "INFO" "Configuring Nginx Proxy Manager..."
    
    if ! container_exists "$container_id"; then
        log "WARN" "Nginx Proxy Manager container $container_id not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for Nginx Proxy Manager to be ready
        local timeout=120
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if container_exec "$container_id" docker ps | grep -q nginx-proxy-manager; then
                # Test if web interface is accessible
                if container_exec "$container_id" curl -s http://localhost:81 >/dev/null 2>&1; then
                    break
                fi
            fi
            sleep 5
            ((elapsed += 5))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            log "WARN" "Nginx Proxy Manager not ready after ${timeout}s"
            return 0
        fi
        
        log "SUCCESS" "Nginx Proxy Manager is ready"
        log "INFO" "Access at: https://proxy.$(get_config '.cluster.domain'):81"
        log "INFO" "Default credentials: admin@example.com / changeme"
    else
        log "INFO" "[DRY RUN] Would configure Nginx Proxy Manager"
    fi
}

setup_local_dns_records() {
    local domain=$(get_config '.cluster.domain')
    local pihole_ip=$(get_config '.networks.core_services.pihole')
    local nginx_ip=$(get_config '.networks.core_services.nginx_proxy')
    
    if [[ "$pihole_ip" == "null" ]]; then
        log "WARN" "Pi-hole not available, skipping local DNS records"
        return 0
    fi
    
    log "INFO" "Setting up local DNS records for $domain"
    
    local container_id="1${pihole_ip##*.}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Core service DNS records
        add_dns_record "$container_id" "pihole.$domain" "$pihole_ip"
        add_dns_record "$container_id" "proxy.$domain" "$nginx_ip"
        add_dns_record "$container_id" "grafana.$domain" "$nginx_ip"
        add_dns_record "$container_id" "auth.$domain" "$nginx_ip"
        
        # Add DNS records for user services
        setup_user_service_dns "$container_id" "$domain" "$nginx_ip"
        
        log "SUCCESS" "Local DNS records configured"
    else
        log "INFO" "[DRY RUN] Would setup DNS records for *.$domain"
    fi
}

add_dns_record() {
    local container_id="$1"
    local hostname="$2"
    local ip="$3"
    
    log "DEBUG" "Adding DNS record: $hostname -> $ip"
    
    # Add to Pi-hole custom DNS
    container_exec "$container_id" bash -c "
        echo '$ip $hostname' >> /opt/pihole/etc-pihole/custom.list
        docker exec pihole pihole restartdns
    "
}

setup_user_service_dns() {
    local container_id="$1"
    local domain="$2"
    local proxy_ip="$3"
    
    local services_dir="$PROJECT_ROOT/config/services"
    
    if [[ ! -d "$services_dir" ]]; then
        return 0
    fi
    
    log "INFO" "Setting up DNS records for user services"
    
    # Find all user services
    for service_dir in "$services_dir"/*; do
        if [[ -d "$service_dir" ]]; then
            local service_name=$(basename "$service_dir")
            
            # Add DNS record pointing to proxy (which will route to actual service)
            add_dns_record "$container_id" "$service_name.$domain" "$proxy_ip"
            
            log "DEBUG" "Added DNS: $service_name.$domain -> $proxy_ip"
        fi
    done
}

# Certificate management functions
setup_ssl_certificates() {
    local cert_type=$(get_config '.certificates.type' 'internal')
    
    case "$cert_type" in
        "internal")
            setup_internal_ca
            ;;
        "letsencrypt")
            setup_letsencrypt
            ;;
        *)
            log "WARN" "Unknown certificate type: $cert_type"
            ;;
    esac
}

setup_internal_ca() {
    log "INFO" "Setting up internal Certificate Authority..."
    
    local domain=$(get_config '.cluster.domain')
    local nginx_ip=$(get_config '.networks.core_services.nginx_proxy')
    local container_id="1${nginx_ip##*.}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create CA and certificates in Nginx Proxy Manager container
        container_exec "$container_id" bash -c "
            # Create CA directory
            mkdir -p /opt/ca
            cd /opt/ca
            
            # Generate CA private key
            openssl genrsa -out ca-key.pem 4096
            
            # Generate CA certificate
            openssl req -new -x509 -sha256 -days 3650 -key ca-key.pem -out ca-cert.pem -subj '/CN=Homelab CA/O=Homelab/C=US'
            
            # Generate wildcard certificate for domain
            openssl genrsa -out ${domain}-key.pem 2048
            openssl req -new -key ${domain}-key.pem -out ${domain}.csr -subj '/CN=*.${domain}/O=Homelab/C=US'
            openssl x509 -req -in ${domain}.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out ${domain}-cert.pem -days 365 -sha256
            
            # Set proper permissions
            chmod 600 *.pem
        "
        
        log "SUCCESS" "Internal CA and wildcard certificate created"
        log "INFO" "Import ca-cert.pem to your devices for trusted HTTPS"
    else
        log "INFO" "[DRY RUN] Would setup internal CA"
    fi
}

setup_letsencrypt() {
    log "INFO" "Let's Encrypt certificates will be managed by Nginx Proxy Manager"
    log "INFO" "Configure DNS provider API tokens in Nginx Proxy Manager UI"
}

# Proxy configuration helpers
create_proxy_host() {
    local service_name="$1"
    local service_ip="$2"
    local service_port="${3:-80}"
    local domain=$(get_config '.cluster.domain')
    
    log "INFO" "Creating proxy host for $service_name.$domain -> $service_ip:$service_port"
    
    # This would typically be done through Nginx Proxy Manager API
    # For now, we'll just log the configuration needed
    log "INFO" "Manual setup required in Nginx Proxy Manager:"
    log "INFO" "  Domain: $service_name.$domain"
    log "INFO" "  Forward to: $service_ip:$service_port"
    log "INFO" "  SSL: Request new certificate"
}

# Health checks
test_dns_resolution() {
    local domain=$(get_config '.cluster.domain')
    local pihole_ip=$(get_config '.networks.core_services.pihole')
    
    log "INFO" "Testing DNS resolution..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would test DNS resolution"
        return 0
    fi
    
    # Test if Pi-hole resolves local domains
    if dig @"$pihole_ip" "pihole.$domain" +short | grep -q "$pihole_ip"; then
        log "SUCCESS" "DNS resolution working correctly"
    else
        log "WARN" "DNS resolution may not be working properly"
    fi
}

test_proxy_connectivity() {
    local nginx_ip=$(get_config '.networks.core_services.nginx_proxy')
    
    log "INFO" "Testing proxy connectivity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would test proxy connectivity"
        return 0
    fi
    
    # Test if Nginx Proxy Manager is accessible
    if curl -s --connect-timeout 5 "http://$nginx_ip:81" >/dev/null; then
        log "SUCCESS" "Nginx Proxy Manager is accessible"
    else
        log "WARN" "Nginx Proxy Manager may not be ready yet"
    fi
}

# Allow running this script standalone
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    CLUSTER_CONFIG="${CLUSTER_CONFIG:-config/cluster.yaml}"
    DNS_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"
    configure_dns_and_proxy
fi