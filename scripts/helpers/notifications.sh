#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                        NOTIFICATION & ALERTING SYSTEM                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Configure notifications for monitoring alerts and system events
# 📱 Features: Discord, Email, Telegram, and webhook notifications

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

setup_notifications() {
    log "STEP" "Setting up notification system..."
    
    setup_discord_notifications || return 1
    setup_email_notifications || return 1
    setup_webhook_notifications || return 1
    test_notification_delivery || return 1
    
    log "SUCCESS" "Notification system setup completed"
}

setup_discord_notifications() {
    local discord_enabled=$(get_config '.monitoring.alerts.discord' 'false')
    
    if [[ "$discord_enabled" != "true" ]]; then
        log "INFO" "Discord notifications not enabled, skipping"
        return 0
    fi
    
    log "INFO" "Setting up Discord notifications..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Discord notification script
        cat > /usr/local/bin/notify-discord << 'EOF'
#!/bin/bash
# Discord notification script for homelab

WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"
MESSAGE="$1"
TITLE="${2:-Homelab Alert}"
COLOR="${3:-16711680}"  # Red by default

if [[ -z "$WEBHOOK_URL" ]]; then
    echo "Error: DISCORD_WEBHOOK_URL not set"
    exit 1
fi

# Create Discord embed
payload=$(cat <<EOF_JSON
{
  "embeds": [
    {
      "title": "$TITLE",
      "description": "$MESSAGE",
      "color": $COLOR,
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
      "footer": {
        "text": "Homelab Monitoring"
      }
    }
  ]
}
EOF_JSON
)

# Send to Discord
curl -s -H "Content-Type: application/json" \
     -d "$payload" \
     "$WEBHOOK_URL"
EOF
        
        chmod +x /usr/local/bin/notify-discord
        
        log "SUCCESS" "Discord notifications configured"
    else
        log "INFO" "[DRY RUN] Would setup Discord notifications"
    fi
}

setup_email_notifications() {
    local email_enabled=$(get_config '.monitoring.alerts.email' 'false')
    
    if [[ "$email_enabled" != "true" ]]; then
        log "INFO" "Email notifications not enabled, skipping"
        return 0
    fi
    
    log "INFO" "Setting up email notifications..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Install and configure mail utilities
        apt update
        apt install -y mailutils ssmtp
        
        # Configure SSMTP
        local smtp_host=$(get_config '.smtp.host' 'smtp.gmail.com')
        local smtp_port=$(get_config '.smtp.port' '587')
        local smtp_user=$(get_config '.smtp.user')
        local admin_email=$(get_config '.cluster.admin_email')
        
        cat > /etc/ssmtp/ssmtp.conf << EOF
root=$admin_email
mailhub=$smtp_host:$smtp_port
AuthUser=$smtp_user
AuthPass=\${SMTP_PASSWORD}
UseSTARTTLS=YES
EOF
        
        # Create email notification script
        cat > /usr/local/bin/notify-email << 'EOF'
#!/bin/bash
# Email notification script for homelab

TO="${1:-$(get_config '.cluster.admin_email')}"
SUBJECT="${2:-Homelab Alert}"
MESSAGE="$3"

if [[ -z "$MESSAGE" ]]; then
    echo "Usage: notify-email <to> <subject> <message>"
    exit 1
fi

# Send email
echo "$MESSAGE" | mail -s "$SUBJECT" "$TO"
EOF
        
        chmod +x /usr/local/bin/notify-email
        
        log "SUCCESS" "Email notifications configured"
    else
        log "INFO" "[DRY RUN] Would setup email notifications"
    fi
}

# Send deployment notifications
send_deployment_notification() {
    local status="$1"      # success, failure, warning
    local message="$2"
    local details="${3:-}"
    
    local title="Homelab Deployment"
    local color="65280"  # Green for success
    
    case "$status" in
        "failure"|"error")
            title="Homelab Deployment Failed"
            color="16711680"  # Red
            ;;
        "warning")
            title="Homelab Deployment Warning"
            color="16776960"  # Yellow
            ;;
    esac
    
    local full_message="$message"
    if [[ -n "$details" ]]; then
        full_message="$message\n\nDetails: $details"
    fi
    
    # Send to all configured notification channels
    if [[ -f /usr/local/bin/notify-discord && -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
        /usr/local/bin/notify-discord "$full_message" "$title" "$color"
    fi
    
    if [[ -f /usr/local/bin/notify-email ]]; then
        local admin_email=$(get_config '.cluster.admin_email')
        if [[ -n "$admin_email" ]]; then
            /usr/local/bin/notify-email "$admin_email" "$title" "$full_message"
        fi
    fi
}

# Send service status notifications
send_service_notification() {
    local service_name="$1"
    local status="$2"      # started, stopped, failed, healthy, unhealthy
    local details="${3:-}"
    
    local title="Service $service_name"
    local color="65280"  # Green
    
    case "$status" in
        "failed"|"unhealthy")
            title="Service $service_name Failed"
            color="16711680"  # Red
            ;;
        "stopped")
            title="Service $service_name Stopped"
            color="16776960"  # Yellow
            ;;
        "started"|"healthy")
            title="Service $service_name Started"
            color="65280"   # Green
            ;;
    esac
    
    local message="Service $service_name is now $status"
    if [[ -n "$details" ]]; then
        message="$message\n\nDetails: $details"
    fi
    
    # Only send critical notifications by default
    if [[ "$status" == "failed" || "$status" == "unhealthy" ]]; then
        if [[ -f /usr/local/bin/notify-discord && -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
            /usr/local/bin/notify-discord "$message" "$title" "$color"
        fi
        
        if [[ -f /usr/local/bin/notify-email ]]; then
            local admin_email=$(get_config '.cluster.admin_email')
            if [[ -n "$admin_email" ]]; then
                /usr/local/bin/notify-email "$admin_email" "$title" "$message"
            fi
        fi
    fi
}

send_deployment_notification() {
    local status="$1"           # success, failure, warning
    local duration="$2"         # deployment time in seconds
    local exit_code="${3:-0}"   # exit code for failures
    
    local cluster_name=$(get_config '.cluster.name' 'homelab')
    local domain=$(get_config '.cluster.domain')
    
    case "$status" in
        "success")
            send_success_notification "$cluster_name" "$domain" "$duration"
            ;;
        "failure")
            send_failure_notification "$cluster_name" "$domain" "$exit_code"
            ;;
        "warning")
            send_warning_notification "$cluster_name" "$domain" "$duration"
            ;;
        *)
            log "ERROR" "Unknown notification status: $status"
            return 1
            ;;
    esac
}

send_success_notification() {
    local cluster_name="$1"
    local domain="$2"
    local duration="$3"
    
    local duration_formatted=$(format_duration "$duration")
    
    log "INFO" "Sending success notification..."
    
    # Discord notification
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        send_discord_notification "success" "$cluster_name" "$domain" "$duration_formatted"
    fi
    
    # Email notification
    if [[ -n "${EMAIL_RECIPIENT:-}" ]]; then
        send_email_notification "success" "$cluster_name" "$domain" "$duration_formatted"
    fi
    
    # Log notification
    log "SUCCESS" "🎉 Deployment completed successfully in $duration_formatted"
}

send_failure_notification() {
    local cluster_name="$1"
    local domain="$2"
    local exit_code="$3"
    
    log "INFO" "Sending failure notification..."
    
    # Discord notification
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        send_discord_notification "failure" "$cluster_name" "$domain" "$exit_code"
    fi
    
    # Email notification
    if [[ -n "${EMAIL_RECIPIENT:-}" ]]; then
        send_email_notification "failure" "$cluster_name" "$domain" "$exit_code"
    fi
    
    # Log notification
    log "ERROR" "💥 Deployment failed with exit code: $exit_code"
}

send_warning_notification() {
    local cluster_name="$1"
    local domain="$2"
    local duration="$3"
    
    local duration_formatted=$(format_duration "$duration")
    
    log "INFO" "Sending warning notification..."
    
    # Discord notification
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        send_discord_notification "warning" "$cluster_name" "$domain" "$duration_formatted"
    fi
    
    # Log notification
    log "WARN" "⚠️ Deployment completed with warnings in $duration_formatted"
}

send_discord_notification() {
    local status="$1"
    local cluster_name="$2"
    local domain="$3"
    local extra_info="$4"
    
    if [[ -z "${DISCORD_WEBHOOK:-}" ]]; then
        log "DEBUG" "Discord webhook not configured, skipping Discord notification"
        return 0
    fi
    
    local color=""
    local title=""
    local description=""
    local emoji=""
    
    case "$status" in
        "success")
            color="5763719"  # Green
            emoji="🎉"
            title="Deployment Successful"
            description="Homelab cluster **$cluster_name** deployed successfully in $extra_info"
            ;;
        "failure")
            color="15548997"  # Red
            emoji="💥"
            title="Deployment Failed"
            description="Homelab cluster **$cluster_name** deployment failed with exit code: $extra_info"
            ;;
        "warning")
            color="16776960"  # Yellow
            emoji="⚠️"
            title="Deployment Warning"
            description="Homelab cluster **$cluster_name** deployed with warnings in $extra_info"
            ;;
    esac
    
    local payload=$(cat << EOF
{
  "embeds": [
    {
      "title": "$emoji $title",
      "description": "$description",
      "color": $color,
      "fields": [
        {
          "name": "Cluster",
          "value": "$cluster_name",
          "inline": true
        },
        {
          "name": "Domain",
          "value": "$domain",
          "inline": true
        },
        {
          "name": "Timestamp",
          "value": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
          "inline": true
        }
      ],
      "footer": {
        "text": "Proxmox Homelab Template"
      }
    }
  ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" >/dev/null; then
            log "DEBUG" "Discord notification sent successfully"
        else
            log "WARN" "Failed to send Discord notification"
        fi
    else
        log "INFO" "[DRY RUN] Would send Discord notification: $title"
    fi
}

send_email_notification() {
    local status="$1"
    local cluster_name="$2"
    local domain="$3"
    local extra_info="$4"
    
    if [[ -z "${EMAIL_RECIPIENT:-}" ]]; then
        log "DEBUG" "Email recipient not configured, skipping email notification"
        return 0
    fi
    
    local subject=""
    local body=""
    
    case "$status" in
        "success")
            subject="🎉 Homelab Deployment Successful - $cluster_name"
            body="Great news! Your homelab cluster '$cluster_name' has been deployed successfully.

Deployment completed in: $extra_info
Domain: https://$domain
Cluster: $cluster_name

Services are now available:
• Pi-hole DNS: https://pihole.$domain/admin
• Nginx Proxy: https://proxy.$domain:81  
• Grafana: https://grafana.$domain
• Authentik SSO: https://auth.$domain

Next steps:
1. Change default passwords for all services
2. Configure SSL certificates in Nginx Proxy Manager
3. Set up authentication providers in Authentik
4. Review monitoring dashboards in Grafana

Deployed at: $(date)"
            ;;
        "failure")
            subject="💥 Homelab Deployment Failed - $cluster_name"
            body="Unfortunately, the deployment of your homelab cluster '$cluster_name' has failed.

Exit code: $extra_info
Domain: $domain
Cluster: $cluster_name

Please check the deployment logs for more details.

Failed at: $(date)"
            ;;
        "warning")
            subject="⚠️ Homelab Deployment Warning - $cluster_name"
            body="Your homelab cluster '$cluster_name' has been deployed, but with some warnings.

Deployment completed in: $extra_info
Domain: https://$domain
Cluster: $cluster_name

Please review the deployment logs for any issues that may need attention.

Deployed at: $(date)"
            ;;
    esac
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Try to send email using mailx or sendmail if available
        if command_exists mail; then
            echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT"
            log "DEBUG" "Email notification sent to $EMAIL_RECIPIENT"
        elif command_exists sendmail; then
            {
                echo "To: $EMAIL_RECIPIENT"
                echo "Subject: $subject"
                echo ""
                echo "$body"
            } | sendmail "$EMAIL_RECIPIENT"
            log "DEBUG" "Email notification sent via sendmail"
        else
            log "WARN" "No mail command available, cannot send email notification"
        fi
    else
        log "INFO" "[DRY RUN] Would send email to $EMAIL_RECIPIENT: $subject"
    fi
}

format_duration() {
    local total_seconds="$1"
    
    if [[ $total_seconds -lt 60 ]]; then
        echo "${total_seconds}s"
    elif [[ $total_seconds -lt 3600 ]]; then
        local minutes=$((total_seconds / 60))
        local seconds=$((total_seconds % 60))
        echo "${minutes}m ${seconds}s"
    else
        local hours=$((total_seconds / 3600))
        local minutes=$(((total_seconds % 3600) / 60))
        local seconds=$((total_seconds % 60))
        echo "${hours}h ${minutes}m ${seconds}s"
    fi
}

# Service-specific notification functions
send_service_notification() {
    local service_name="$1"
    local action="$2"       # deployed, updated, failed, removed
    local status="$3"       # success, failure, warning
    
    log "INFO" "Sending $action notification for service: $service_name"
    
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        send_service_discord_notification "$service_name" "$action" "$status"
    fi
}

send_service_discord_notification() {
    local service_name="$1"
    local action="$2"
    local status="$3"
    
    local color=""
    local emoji=""
    local title=""
    
    case "$status" in
        "success")
            color="5763719"  # Green
            emoji="✅"
            ;;
        "failure")
            color="15548997"  # Red
            emoji="❌"
            ;;
        "warning")
            color="16776960"  # Yellow
            emoji="⚠️"
            ;;
    esac
    
    case "$action" in
        "deployed")
            title="Service Deployed"
            ;;
        "updated")
            title="Service Updated"
            ;;
        "failed")
            title="Service Failed"
            ;;
        "removed")
            title="Service Removed"
            ;;
    esac
    
    local domain=$(get_config '.cluster.domain')
    
    local payload=$(cat << EOF
{
  "embeds": [
    {
      "title": "$emoji $title",
      "description": "Service **$service_name** has been $action",
      "color": $color,
      "fields": [
        {
          "name": "Service",
          "value": "$service_name",
          "inline": true
        },
        {
          "name": "URL",
          "value": "https://$service_name.$domain",
          "inline": true
        },
        {
          "name": "Timestamp",
          "value": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
          "inline": true
        }
      ],
      "footer": {
        "text": "Proxmox Homelab Template"
      }
    }
  ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" >/dev/null
    fi
}

# Health check notifications
send_health_alert() {
    local service_name="$1"
    local alert_type="$2"    # down, recovered, degraded
    local message="$3"
    
    if [[ -z "${DISCORD_WEBHOOK:-}" ]]; then
        return 0
    fi
    
    local color=""
    local emoji=""
    
    case "$alert_type" in
        "down")
            color="15548997"  # Red
            emoji="🚨"
            ;;
        "recovered")
            color="5763719"   # Green
            emoji="✅"
            ;;
        "degraded")
            color="16776960"  # Yellow
            emoji="⚠️"
            ;;
    esac
    
    local payload=$(cat << EOF
{
  "embeds": [
    {
      "title": "$emoji Service Alert",
      "description": "$message",
      "color": $color,
      "fields": [
        {
          "name": "Service",
          "value": "$service_name",
          "inline": true
        },
        {
          "name": "Status",
          "value": "$alert_type",
          "inline": true
        },
        {
          "name": "Time",
          "value": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
          "inline": true
        }
      ],
      "footer": {
        "text": "Homelab Monitoring"
      }
    }
  ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" >/dev/null
    fi
}

# Backup notifications
send_backup_notification() {
    local backup_type="$1"     # daily, weekly, monthly
    local status="$2"          # success, failure
    local details="$3"         # backup details or error message
    
    log "INFO" "Sending backup notification: $backup_type $status"
    
    if [[ -n "${DISCORD_WEBHOOK:-}" && "$status" == "failure" ]]; then
        # Only send Discord notifications for backup failures
        send_backup_discord_notification "$backup_type" "$status" "$details"
    fi
}

send_backup_discord_notification() {
    local backup_type="$1"
    local status="$2"
    local details="$3"
    
    local color="15548997"  # Red for failures
    local emoji="💾❌"
    
    local payload=$(cat << EOF
{
  "embeds": [
    {
      "title": "$emoji Backup Failed",
      "description": "**$backup_type** backup has failed",
      "color": $color,
      "fields": [
        {
          "name": "Backup Type",
          "value": "$backup_type",
          "inline": true
        },
        {
          "name": "Details",
          "value": "$details",
          "inline": false
        },
        {
          "name": "Time",
          "value": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
          "inline": true
        }
      ],
      "footer": {
        "text": "Homelab Backup System"
      }
    }
  ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        curl -s -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK" >/dev/null
    fi
}

# Test notification functions
test_notifications() {
    log "INFO" "Testing notification systems..."
    
    if [[ -n "${DISCORD_WEBHOOK:-}" ]]; then
        test_discord_webhook
    else
        log "INFO" "Discord webhook not configured"
    fi
    
    if [[ -n "${EMAIL_RECIPIENT:-}" ]]; then
        test_email_notification
    else
        log "INFO" "Email recipient not configured"
    fi
}

test_discord_webhook() {
    log "INFO" "Testing Discord webhook..."
    
    local test_payload=$(cat << EOF
{
  "embeds": [
    {
      "title": "🧪 Test Notification",
      "description": "This is a test notification from your homelab deployment system.",
      "color": 3447003,
      "fields": [
        {
          "name": "Status",
          "value": "Test successful",
          "inline": true
        },
        {
          "name": "Time",
          "value": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
          "inline": true
        }
      ],
      "footer": {
        "text": "Proxmox Homelab Template - Test"
      }
    }
  ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if curl -s -H "Content-Type: application/json" -d "$test_payload" "$DISCORD_WEBHOOK" >/dev/null; then
            log "SUCCESS" "Discord webhook test successful"
        else
            log "ERROR" "Discord webhook test failed"
        fi
    else
        log "INFO" "[DRY RUN] Would test Discord webhook"
    fi
}

test_email_notification() {
    log "INFO" "Testing email notification..."
    
    local subject="🧪 Homelab Test Notification"
    local body="This is a test email from your homelab deployment system.

If you received this email, your notification system is working correctly.

Sent at: $(date)"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if command_exists mail; then
            echo "$body" | mail -s "$subject" "$EMAIL_RECIPIENT"
            log "SUCCESS" "Test email sent to $EMAIL_RECIPIENT"
        else
            log "WARN" "No mail command available for testing"
        fi
    else
        log "INFO" "[DRY RUN] Would send test email to $EMAIL_RECIPIENT"
    fi
}

# Allow running this script standalone for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "test")
            test_notifications
            ;;
        "success")
            send_deployment_notification "success" "300" "0"
            ;;
        "failure")
            send_deployment_notification "failure" "0" "1"
            ;;
        *)
            echo "Usage: $0 [test|success|failure]"
            echo "  test     - Test notification systems"
            echo "  success  - Send test success notification"
            echo "  failure  - Send test failure notification"
            ;;
    esac
fi