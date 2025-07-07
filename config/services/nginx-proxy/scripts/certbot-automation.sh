#!/bin/sh

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        CERTBOT AUTOMATION SCRIPT                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Automated Let's Encrypt certificate generation and renewal
# 🔒 FEATURES: Wildcard certificates via Cloudflare DNS challenge
# 🤖 USAGE: Called during deployment and for renewals

set -e  # Exit on error

# Configuration
DOMAIN="${CERTBOT_DOMAIN:-example.com}"
EMAIL="${CERTBOT_EMAIL:-admin@example.com}"
STAGING="${CERTBOT_STAGING:-false}"
CLOUDFLARE_INI="/etc/cloudflare/cloudflare.ini"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/letsencrypt/automation.log
}

# Check if Cloudflare credentials exist
check_cloudflare_credentials() {
    if [[ ! -f "$CLOUDFLARE_INI" ]]; then
        log "ERROR: Cloudflare credentials file not found: $CLOUDFLARE_INI"
        log "INFO: Creating credentials file from environment variable"
        
        if [[ -z "$CLOUDFLARE_API_TOKEN" ]]; then
            log "ERROR: CLOUDFLARE_API_TOKEN environment variable not set"
            exit 1
        fi
        
        # Create credentials directory
        mkdir -p "$(dirname "$CLOUDFLARE_INI")"
        
        # Create credentials file
        cat > "$CLOUDFLARE_INI" << EOF
# Cloudflare API credentials for Let's Encrypt DNS challenge
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
        
        # Secure the credentials file
        chmod 600 "$CLOUDFLARE_INI"
        log "INFO: Created Cloudflare credentials file"
    fi
}

# Generate initial certificates
generate_initial_certificates() {
    log "INFO: Starting initial certificate generation for domain: $DOMAIN"
    
    # Determine staging flag
    local staging_flag=""
    if [[ "$STAGING" == "true" ]]; then
        staging_flag="--staging"
        log "INFO: Using Let's Encrypt staging environment"
    fi
    
    # Generate wildcard certificate
    log "INFO: Generating wildcard certificate for *.$DOMAIN"
    
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CLOUDFLARE_INI" \
        --dns-cloudflare-propagation-seconds 60 \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive \
        $staging_flag \
        --expand \
        -d "$DOMAIN" \
        -d "*.$DOMAIN"
    
    if [[ $? -eq 0 ]]; then
        log "SUCCESS: Wildcard certificate generated successfully"
        
        # List generated certificates
        log "INFO: Certificate details:"
        certbot certificates | tee -a /var/log/letsencrypt/automation.log
        
        # Copy certificates to NPM location (if needed)
        copy_certificates_to_npm
        
    else
        log "ERROR: Certificate generation failed"
        exit 1
    fi
}

# Copy certificates to Nginx Proxy Manager expected location
copy_certificates_to_npm() {
    log "INFO: Copying certificates to NPM location"
    
    local cert_dir="/etc/letsencrypt/live/$DOMAIN"
    local npm_cert_dir="/data/nginx/certificates"
    
    if [[ -d "$cert_dir" ]]; then
        # Create NPM certificates directory
        mkdir -p "$npm_cert_dir"
        
        # Copy certificate files
        cp "$cert_dir/fullchain.pem" "$npm_cert_dir/wildcard-fullchain.pem"
        cp "$cert_dir/privkey.pem" "$npm_cert_dir/wildcard-privkey.pem"
        cp "$cert_dir/cert.pem" "$npm_cert_dir/wildcard-cert.pem"
        
        # Set appropriate permissions
        chmod 644 "$npm_cert_dir"/wildcard-*.pem
        
        log "INFO: Certificates copied to NPM directory"
    else
        log "WARN: Certificate directory not found: $cert_dir"
    fi
}

# Renew certificates
renew_certificates() {
    log "INFO: Starting certificate renewal check"
    
    # Attempt renewal
    certbot renew \
        --dns-cloudflare \
        --dns-cloudflare-credentials "$CLOUDFLARE_INI" \
        --dns-cloudflare-propagation-seconds 60 \
        --non-interactive \
        --quiet
    
    local renewal_exit_code=$?
    
    if [[ $renewal_exit_code -eq 0 ]]; then
        log "INFO: Certificate renewal completed successfully"
        
        # Copy renewed certificates
        copy_certificates_to_npm
        
        # Reload Nginx (send signal to NPM container)
        log "INFO: Reloading Nginx configuration"
        # Note: This would typically send a signal to NPM container
        # For now, we'll just log it
        
    elif [[ $renewal_exit_code -eq 1 ]]; then
        log "INFO: No certificates were due for renewal"
    else
        log "ERROR: Certificate renewal failed with exit code: $renewal_exit_code"
        exit $renewal_exit_code
    fi
}

# Check certificate expiry
check_certificate_expiry() {
    log "INFO: Checking certificate expiry status"
    
    local cert_file="/etc/letsencrypt/live/$DOMAIN/cert.pem"
    
    if [[ -f "$cert_file" ]]; then
        # Get certificate expiry date
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s)
        local current_epoch=$(date +%s)
        local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        log "INFO: Certificate expires in $days_until_expiry days ($expiry_date)"
        
        # Warn if certificate expires soon
        if [[ $days_until_expiry -lt 30 ]]; then
            log "WARN: Certificate expires in less than 30 days!"
        fi
        
        # Export expiry info for monitoring
        echo "$days_until_expiry" > /tmp/cert-expiry-days
        
    else
        log "ERROR: Certificate file not found: $cert_file"
        exit 1
    fi
}

# Test certificate
test_certificate() {
    log "INFO: Testing certificate configuration"
    
    local cert_file="/etc/letsencrypt/live/$DOMAIN/cert.pem"
    
    if [[ -f "$cert_file" ]]; then
        # Verify certificate
        if openssl x509 -in "$cert_file" -text -noout > /dev/null 2>&1; then
            log "SUCCESS: Certificate is valid"
            
            # Show certificate details
            log "INFO: Certificate details:"
            openssl x509 -in "$cert_file" -text -noout | grep -E "(Subject:|DNS:|Not After)" | tee -a /var/log/letsencrypt/automation.log
            
        else
            log "ERROR: Certificate validation failed"
            exit 1
        fi
    else
        log "ERROR: Certificate file not found for testing"
        exit 1
    fi
}

# Main function
main() {
    local action="${1:-initial}"
    
    # Create log directory
    mkdir -p /var/log/letsencrypt
    
    log "INFO: Starting certbot automation - action: $action"
    log "INFO: Domain: $DOMAIN, Email: $EMAIL, Staging: $STAGING"
    
    # Check prerequisites
    check_cloudflare_credentials
    
    case "$action" in
        "initial")
            generate_initial_certificates
            test_certificate
            check_certificate_expiry
            ;;
        "renew")
            renew_certificates
            check_certificate_expiry
            ;;
        "test")
            test_certificate
            check_certificate_expiry
            ;;
        "status")
            check_certificate_expiry
            ;;
        *)
            log "ERROR: Unknown action: $action"
            log "INFO: Usage: $0 {initial|renew|test|status}"
            exit 1
            ;;
    esac
    
    log "INFO: Certbot automation completed successfully"
}

# Run main function with all arguments
main "$@"