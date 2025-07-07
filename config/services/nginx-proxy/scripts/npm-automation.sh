#!/bin/sh

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     NGINX PROXY MANAGER AUTOMATION                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Automatically create proxy hosts with SSL for all services
# 🤖 FEATURES: API-driven configuration, SSL automation, health checks
# 🔒 RESULT: All services immediately available via HTTPS

set -e  # Exit on error

# Configuration
NPM_HOST="${NPM_HOST:-nginx-proxy-manager}"
NPM_PORT="${NPM_PORT:-81}"
DOMAIN="${DOMAIN:-example.com}"
NPM_API="http://$NPM_HOST:$NPM_PORT/api"
STATE_DIR="${STATE_DIR:-/state}"

# Default NPM credentials (user should change these)
NPM_EMAIL="admin@example.com"
NPM_PASSWORD="changeme"

# Service definitions (IP addresses for proxy targets)
SERVICES="
homepage:10.0.0.44:3000:yourdomain.com,www.yourdomain.com
pihole:10.0.0.40:80:pihole.yourdomain.com
grafana:10.0.0.42:3000:grafana.yourdomain.com
auth:10.0.0.43:9000:auth.yourdomain.com
proxy:10.0.0.41:81:proxy.yourdomain.com
"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Wait for NPM to be ready
wait_for_npm() {
    log "INFO: Waiting for Nginx Proxy Manager to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf "$NPM_API/schema" > /dev/null 2>&1; then
            log "SUCCESS: NPM is ready"
            return 0
        fi
        
        sleep 5
        ((attempt++))
        log "INFO: Waiting for NPM... ($attempt/$max_attempts)"
    done
    
    log "ERROR: NPM failed to become ready after $max_attempts attempts"
    exit 1
}

# Authenticate with NPM and get access token
authenticate_npm() {
    log "INFO: Authenticating with NPM..."
    
    # Replace placeholder domain with actual domain
    local email="${NPM_EMAIL/yourdomain.com/$DOMAIN}"
    
    local auth_response=$(curl -sf -X POST "$NPM_API/tokens" \
        -H "Content-Type: application/json" \
        -d "{
            \"identity\": \"$email\",
            \"secret\": \"$NPM_PASSWORD\"
        }" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$auth_response" ]]; then
        # Extract token from response
        NPM_TOKEN=$(echo "$auth_response" | jq -r '.token // empty')
        
        if [[ -n "$NPM_TOKEN" && "$NPM_TOKEN" != "null" ]]; then
            log "SUCCESS: NPM authentication successful"
            echo "$NPM_TOKEN" > "$STATE_DIR/npm_token"
            return 0
        fi
    fi
    
    log "ERROR: NPM authentication failed"
    log "INFO: Make sure NPM is set up with default credentials: $email / $NPM_PASSWORD"
    log "INFO: Or update credentials in NPM and restart this automation"
    exit 1
}

# Get existing proxy hosts to avoid duplicates
get_existing_hosts() {
    log "INFO: Getting existing proxy hosts..."
    
    local hosts_response=$(curl -sf -X GET "$NPM_API/nginx/proxy-hosts" \
        -H "Authorization: Bearer $NPM_TOKEN" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$hosts_response" ]]; then
        echo "$hosts_response" > "$STATE_DIR/existing_hosts.json"
        log "INFO: Retrieved existing proxy hosts"
    else
        log "WARN: Could not retrieve existing proxy hosts, proceeding anyway"
        echo "[]" > "$STATE_DIR/existing_hosts.json"
    fi
}

# Check if domain already has a proxy host
domain_exists() {
    local domain="$1"
    
    if [[ -f "$STATE_DIR/existing_hosts.json" ]]; then
        local exists=$(jq -r --arg domain "$domain" '
            .[] | select(.domain_names[]? == $domain) | .id
        ' "$STATE_DIR/existing_hosts.json")
        
        [[ -n "$exists" && "$exists" != "null" ]]
    else
        return 1
    fi
}

# Get available SSL certificates
get_ssl_certificates() {
    log "INFO: Getting available SSL certificates..."
    
    local certs_response=$(curl -sf -X GET "$NPM_API/nginx/certificates" \
        -H "Authorization: Bearer $NPM_TOKEN" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$certs_response" ]]; then
        echo "$certs_response" > "$STATE_DIR/certificates.json"
        
        # Look for wildcard certificate
        WILDCARD_CERT_ID=$(jq -r --arg domain "*.$DOMAIN" '
            .[] | select(.domain_names[]? == $domain) | .id
        ' "$STATE_DIR/certificates.json")
        
        if [[ -n "$WILDCARD_CERT_ID" && "$WILDCARD_CERT_ID" != "null" ]]; then
            log "SUCCESS: Found wildcard certificate (ID: $WILDCARD_CERT_ID)"
        else
            log "WARN: No wildcard certificate found, will request individual certificates"
            WILDCARD_CERT_ID=""
        fi
    else
        log "WARN: Could not retrieve SSL certificates"
        WILDCARD_CERT_ID=""
    fi
}

# Create SSL certificate for domain
create_ssl_certificate() {
    local domains="$1"
    
    log "INFO: Creating SSL certificate for: $domains"
    
    # Convert comma-separated domains to JSON array
    local domain_array=$(echo "$domains" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
    
    local cert_response=$(curl -sf -X POST "$NPM_API/nginx/certificates" \
        -H "Authorization: Bearer $NPM_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"provider\": \"letsencrypt\",
            \"domain_names\": [$domain_array],
            \"meta\": {
                \"letsencrypt_agree\": true,
                \"dns_challenge\": true,
                \"dns_provider\": \"cloudflare\",
                \"cloudflare_api_token\": \"$CLOUDFLARE_API_TOKEN\"
            }
        }" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$cert_response" ]]; then
        local cert_id=$(echo "$cert_response" | jq -r '.id // empty')
        
        if [[ -n "$cert_id" && "$cert_id" != "null" ]]; then
            log "SUCCESS: SSL certificate created (ID: $cert_id)"
            echo "$cert_id"
            return 0
        fi
    fi
    
    log "ERROR: Failed to create SSL certificate for: $domains"
    return 1
}

# Create proxy host
create_proxy_host() {
    local service_name="$1"
    local target_ip="$2"
    local target_port="$3"
    local domains="$4"
    
    log "INFO: Creating proxy host for $service_name ($domains -> $target_ip:$target_port)"
    
    # Check if any domain already exists
    local primary_domain=$(echo "$domains" | cut -d',' -f1)
    if domain_exists "$primary_domain"; then
        log "INFO: Proxy host for $primary_domain already exists, skipping"
        return 0
    fi
    
    # Determine SSL certificate to use
    local cert_id="$WILDCARD_CERT_ID"
    if [[ -z "$cert_id" ]]; then
        # Create individual certificate
        cert_id=$(create_ssl_certificate "$domains")
        if [[ $? -ne 0 ]]; then
            log "WARN: Could not create SSL certificate, creating HTTP-only proxy host"
            cert_id=""
        fi
    fi
    
    # Convert comma-separated domains to JSON array
    local domain_array=$(echo "$domains" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
    
    # Prepare SSL configuration
    local ssl_config='"certificate_id": null, "ssl_forced": false, "hsts_enabled": false'
    if [[ -n "$cert_id" ]]; then
        ssl_config='"certificate_id": '$cert_id', "ssl_forced": true, "hsts_enabled": true'
    fi
    
    # Create proxy host
    local proxy_response=$(curl -sf -X POST "$NPM_API/nginx/proxy-hosts" \
        -H "Authorization: Bearer $NPM_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [$domain_array],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"$target_ip\",
            \"forward_port\": $target_port,
            \"caching_enabled\": false,
            \"block_exploits\": true,
            \"allow_websocket_upgrade\": true,
            \"access_list_id\": 0,
            \"advanced_config\": \"\",
            \"enabled\": true,
            $ssl_config,
            \"http2_support\": true,
            \"hsts_subdomains\": false
        }" 2>/dev/null)
    
    if [[ $? -eq 0 ]] && [[ -n "$proxy_response" ]]; then
        local proxy_id=$(echo "$proxy_response" | jq -r '.id // empty')
        
        if [[ -n "$proxy_id" && "$proxy_id" != "null" ]]; then
            local ssl_status="HTTP"
            [[ -n "$cert_id" ]] && ssl_status="HTTPS"
            
            log "SUCCESS: Proxy host created for $service_name (ID: $proxy_id, SSL: $ssl_status)"
            return 0
        fi
    fi
    
    log "ERROR: Failed to create proxy host for $service_name"
    return 1
}

# Create all proxy hosts
create_all_proxy_hosts() {
    log "INFO: Creating proxy hosts for all services..."
    
    local success_count=0
    local total_count=0
    
    # Process each service definition
    echo "$SERVICES" | while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Parse service definition: name:ip:port:domains
        local service_name=$(echo "$line" | cut -d':' -f1)
        local target_ip=$(echo "$line" | cut -d':' -f2)
        local target_port=$(echo "$line" | cut -d':' -f3)
        local domains=$(echo "$line" | cut -d':' -f4 | sed "s/yourdomain.com/$DOMAIN/g")
        
        # Skip if any field is empty
        if [[ -z "$service_name" || -z "$target_ip" || -z "$target_port" || -z "$domains" ]]; then
            continue
        fi
        
        ((total_count++))
        
        if create_proxy_host "$service_name" "$target_ip" "$target_port" "$domains"; then
            ((success_count++))
        fi
        
        # Small delay between requests
        sleep 2
    done
    
    log "INFO: Created $success_count/$total_count proxy hosts successfully"
    
    if [[ $success_count -eq $total_count ]]; then
        log "SUCCESS: All proxy hosts created successfully"
        return 0
    else
        log "WARN: Some proxy hosts failed to create"
        return 1
    fi
}

# Verify proxy hosts are working
verify_proxy_hosts() {
    log "INFO: Verifying proxy hosts are responding..."
    
    local working_count=0
    local total_count=0
    
    # Test each service
    echo "$SERVICES" | while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        local service_name=$(echo "$line" | cut -d':' -f1)
        local domains=$(echo "$line" | cut -d':' -f4 | sed "s/yourdomain.com/$DOMAIN/g")
        local primary_domain=$(echo "$domains" | cut -d',' -f1)
        
        # Skip if fields are empty
        [[ -z "$service_name" || -z "$primary_domain" ]] && continue
        
        ((total_count++))
        
        # Test HTTP connectivity (we're testing from inside container network)
        if curl -sf -H "Host: $primary_domain" "http://$NPM_HOST/" > /dev/null 2>&1; then
            log "SUCCESS: $service_name is responding at $primary_domain"
            ((working_count++))
        else
            log "WARN: $service_name not responding at $primary_domain"
        fi
        
        sleep 1
    done
    
    log "INFO: $working_count/$total_count proxy hosts are responding"
}

# Generate status report
generate_status_report() {
    log "INFO: Generating NPM automation status report..."
    
    local report_file="$STATE_DIR/npm_automation_report.json"
    
    cat > "$report_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "domain": "$DOMAIN",
    "npm_host": "$NPM_HOST:$NPM_PORT",
    "wildcard_cert_id": "${WILDCARD_CERT_ID:-null}",
    "services": [
EOF
    
    local first=true
    echo "$SERVICES" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        
        local service_name=$(echo "$line" | cut -d':' -f1)
        local domains=$(echo "$line" | cut -d':' -f4 | sed "s/yourdomain.com/$DOMAIN/g")
        
        [[ -z "$service_name" ]] && continue
        
        [[ "$first" == "false" ]] && echo ","
        first=false
        
        cat << EOF
        {
            "name": "$service_name",
            "domains": "$(echo "$domains" | sed 's/,/", "/g')",
            "status": "configured"
        }
EOF
    done >> "$report_file"
    
    cat >> "$report_file" << EOF
    ],
    "status": "completed"
}
EOF
    
    log "INFO: Status report saved to: $report_file"
}

# Main automation function
main() {
    log "INFO: Starting NPM automation for domain: $DOMAIN"
    
    # Create state directory
    mkdir -p "$STATE_DIR"
    
    # Check if automation already completed
    if [[ -f "$STATE_DIR/npm_automation_completed" ]]; then
        log "INFO: NPM automation already completed, skipping"
        exit 0
    fi
    
    # Wait for NPM to be ready
    wait_for_npm
    
    # Authenticate with NPM
    authenticate_npm
    
    # Get existing configuration
    get_existing_hosts
    get_ssl_certificates
    
    # Create proxy hosts
    if create_all_proxy_hosts; then
        log "SUCCESS: Proxy host creation completed"
        
        # Verify hosts are working
        verify_proxy_hosts
        
        # Generate status report
        generate_status_report
        
        # Mark automation as completed
        touch "$STATE_DIR/npm_automation_completed"
        
        log "SUCCESS: NPM automation completed successfully"
        log "INFO: Services are now available at:"
        
        echo "$SERVICES" | while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local service_name=$(echo "$line" | cut -d':' -f1)
            local domains=$(echo "$line" | cut -d':' -f4 | sed "s/yourdomain.com/$DOMAIN/g")
            local primary_domain=$(echo "$domains" | cut -d',' -f1)
            [[ -n "$service_name" && -n "$primary_domain" ]] && log "INFO:   - $service_name: https://$primary_domain"
        done
        
    else
        log "ERROR: Proxy host creation failed"
        exit 1
    fi
}

# Run main function
main "$@"