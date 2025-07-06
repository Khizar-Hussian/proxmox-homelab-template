#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                     PROXMOX HOMELAB DEPLOYMENT SCRIPT                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🚀 Main deployment orchestrator for Proxmox homelab infrastructure
# 📖 Reads cluster.yaml and deploys entire infrastructure automatically
# 🔧 Modular design with separate scripts for each component
#
# Usage:
#   ./scripts/deploy.sh                    # Deploy everything
#   ./scripts/deploy.sh --validate-only    # Just validate configuration
#   ./scripts/deploy.sh --services-only    # Deploy only services
#   ./scripts/deploy.sh --force            # Force redeploy everything
#
# Environment Variables:
#   CLUSTER_CONFIG    - Path to cluster.yaml (default: config/cluster.yaml)
#   DRY_RUN          - Set to 'true' for dry run mode
#   VERBOSE          - Set to 'true' for verbose output

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 SCRIPT SETUP AND IMPORTS
# ══════════════════════════════════════════════════════════════════════════════

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly HELPERS_DIR="$SCRIPT_DIR/helpers"
readonly CLUSTER_CONFIG="${CLUSTER_CONFIG:-$PROJECT_ROOT/config/cluster.yaml}"

# Import helper functions and modules
source "$HELPERS_DIR/common.sh"          # Logging, colors, utilities
source "$HELPERS_DIR/validation.sh"      # Configuration validation
source "$HELPERS_DIR/prerequisites.sh"   # System prerequisites
source "$HELPERS_DIR/networking.sh"      # Network setup
source "$HELPERS_DIR/containers.sh"      # LXC container management
source "$HELPERS_DIR/services.sh"        # Service deployment
source "$HELPERS_DIR/monitoring.sh"      # Monitoring setup
source "$HELPERS_DIR/dns.sh"             # DNS configuration
source "$HELPERS_DIR/notifications.sh"   # Notification system
source "$HELPERS_DIR/deployment.sh"      # Validation and cleanup

# ══════════════════════════════════════════════════════════════════════════════
# 🎯 COMMAND LINE PARSING
# ══════════════════════════════════════════════════════════════════════════════

VALIDATE_ONLY=false
SERVICES_ONLY=false
FORCE_DEPLOY=false
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

show_help() {
    cat << EOF
${BOLD}Proxmox Homelab Deployment Script${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    --validate-only    Only validate configuration, don't deploy
    --services-only    Deploy only services (skip infrastructure)
    --force           Force redeploy everything
    --dry-run         Show what would be done without making changes
    --verbose         Enable verbose output
    --help, -h        Show this help message

${BOLD}EXAMPLES:${NC}
    $0                          # Full deployment
    $0 --validate-only          # Just check configuration
    $0 --services-only --force  # Redeploy all services
    $0 --dry-run --verbose      # Preview deployment with details

${BOLD}ENVIRONMENT VARIABLES:${NC}
    CLUSTER_CONFIG    Path to cluster.yaml (default: config/cluster.yaml)
    DRY_RUN          Set to 'true' for dry run mode
    VERBOSE          Set to 'true' for verbose output
    PROXMOX_HOST     Proxmox server IP
    PROXMOX_TOKEN    Proxmox API token

${BOLD}MODULAR COMPONENTS:${NC}
    This script orchestrates multiple helper scripts:
    • helpers/prerequisites.sh  - System requirements check
    • helpers/validation.sh     - Configuration validation  
    • helpers/networking.sh     - Network bridge setup
    • helpers/containers.sh     - LXC container management
    • helpers/services.sh       - Service deployment
    • helpers/monitoring.sh     - Monitoring configuration
    • helpers/dns.sh           - DNS and proxy setup
    • helpers/notifications.sh  - Alert notifications

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        --services-only)
            SERVICES_ONLY=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Export variables for helper scripts
export DRY_RUN VERBOSE FORCE_DEPLOY CLUSTER_CONFIG PROJECT_ROOT

# ══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN DEPLOYMENT ORCHESTRATION
# ══════════════════════════════════════════════════════════════════════════════

main() {
    local start_time=$(date +%s)
    
    banner "🏠 PROXMOX HOMELAB DEPLOYMENT"
    
    log "INFO" "Starting deployment with configuration: $CLUSTER_CONFIG"
    log "INFO" "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE DEPLOYMENT")"
    
    # Phase 1: Prerequisites and Validation
    log "STEP" "Phase 1: Prerequisites and Validation"
    check_prerequisites || exit 1
    validate_configuration || exit 1
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log "SUCCESS" "Configuration validation completed successfully"
        exit 0
    fi
    
    # Phase 2: Infrastructure Setup (skip if services-only)
    if [[ "$SERVICES_ONLY" == "false" ]]; then
        log "STEP" "Phase 2: Infrastructure Setup"
        setup_networking || exit 1
        deploy_core_infrastructure || exit 1
    else
        log "INFO" "Skipping infrastructure setup (services-only mode)"
    fi
    
    # Phase 3: Service Deployment
    log "STEP" "Phase 3: Service Deployment"
    deploy_user_services || exit 1
    
    # Phase 4: Post-Deployment Configuration
    log "STEP" "Phase 4: Post-Deployment Configuration"
    configure_dns_and_proxy || exit 1
    setup_monitoring_stack || exit 1
    
    # Phase 5: Validation and Cleanup
    log "STEP" "Phase 5: Validation and Cleanup"
    validate_deployment || exit 1
    cleanup_deployment || exit 1
    
    # Send success notification
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    send_deployment_notification "success" "$duration" || true
    
    banner "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY"
    
    show_deployment_summary
}

# ══════════════════════════════════════════════════════════════════════════════
# 📊 DEPLOYMENT SUMMARY
# ══════════════════════════════════════════════════════════════════════════════

show_deployment_summary() {
    local domain=$(yq eval '.cluster.domain' "$CLUSTER_CONFIG")
    
    echo -e "${BOLD}${GREEN}🎯 DEPLOYMENT SUMMARY${NC}"
    echo "════════════════════════════════════════════════════════════════"
    echo
    echo -e "${BOLD}🌐 Core Services:${NC}"
    echo "• Pi-hole DNS:        https://pihole.$domain/admin"
    echo "• Nginx Proxy:        https://proxy.$domain:81"
    echo "• Grafana:            https://grafana.$domain"
    echo "• Authentik SSO:      https://auth.$domain"
    echo
    echo -e "${BOLD}🔐 Default Credentials:${NC}"
    echo "• Nginx Proxy:        admin@example.com / changeme"
    echo "• Pi-hole:            admin / [generated]"
    echo "• Grafana:            admin / admin"
    echo "• Authentik:          admin@$domain / [from AUTHENTIK_ADMIN_PASSWORD]"
    echo
    echo -e "${BOLD}📊 Container Network:${NC}"
    echo "• Management:         $(yq eval '.networks.management.subnet' "$CLUSTER_CONFIG")"
    echo "• Containers:         $(yq eval '.networks.containers.subnet' "$CLUSTER_CONFIG")"
    echo "• Core Services:      $(yq eval '.networks.core_services.pihole' "$CLUSTER_CONFIG")-$(yq eval '.networks.core_services.authentik' "$CLUSTER_CONFIG")"
    echo
    echo -e "${BOLD}📝 Next Steps:${NC}"
    echo "1. Change default passwords for all services"
    echo "2. Configure SSL certificates in Nginx Proxy Manager"
    echo "3. Set up authentication providers in Authentik"
    echo "4. Review monitoring dashboards in Grafana"
    echo "5. Add your services in config/services/ directory"
    echo
    echo -e "${BOLD}📚 Documentation:${NC}"
    echo "• Installation:       docs/installation.md"
    echo "• Service Management: docs/services.md"
    echo "• Troubleshooting:    docs/troubleshooting.md"
    echo
    echo "════════════════════════════════════════════════════════════════"
    echo -e "${GREEN}✅ Your homelab is ready to use!${NC}"
    echo
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔥 ERROR HANDLING
# ══════════════════════════════════════════════════════════════════════════════

cleanup_on_error() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Deployment failed with exit code: $exit_code"
        
        # Send failure notification
        send_deployment_notification "failure" "0" "$exit_code" || true
        
        echo
        echo -e "${RED}💥 DEPLOYMENT FAILED${NC}"
        echo "════════════════════════════════════════════════════════════════"
        echo "• Check logs above for specific error details"
        echo "• Run with --verbose for more detailed output"
        echo "• Use --dry-run to preview changes without making them"
        echo "• See docs/troubleshooting.md for common issues"
        echo
        echo -e "${YELLOW}🔧 Quick Troubleshooting:${NC}"
        echo "• Validate config:    ./scripts/deploy.sh --validate-only"
        echo "• Check prerequisites: ./scripts/helpers/prerequisites.sh"
        echo "• Health check:       ./scripts/health-check.sh"
        echo "════════════════════════════════════════════════════════════════"
    fi
    
    exit $exit_code
}

# Set up error handling
trap cleanup_on_error ERR EXIT

# ══════════════════════════════════════════════════════════════════════════════
# 🎬 SCRIPT EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi