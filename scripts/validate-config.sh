#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                       CONFIGURATION VALIDATION SCRIPT                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Standalone validation script for JSON configuration files
# 📝 USAGE: ./scripts/validate-config.sh [--fix] [--verbose]
# 🔧 FEATURES: Comprehensive validation, error reporting, optional fixes

set -euo pipefail

# Script setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
HELPERS_DIR="$SCRIPT_DIR/helpers"

# Source libraries
source "$LIB_DIR/config.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/service-discovery.sh"
source "$HELPERS_DIR/common.sh"

# Command line options
FIX_ERRORS=false
VERBOSE=false

# ══════════════════════════════════════════════════════════════════════════════
# 🎯 COMMAND LINE PARSING
# ══════════════════════════════════════════════════════════════════════════════

show_help() {
    cat << EOF
${BOLD}Configuration Validation Script${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    --fix         Attempt to fix common configuration issues
    --verbose     Show detailed validation output
    --help, -h    Show this help message

${BOLD}EXAMPLES:${NC}
    $0                # Basic validation
    $0 --verbose      # Detailed validation
    $0 --fix          # Validate and fix issues

${BOLD}VALIDATION CHECKS:${NC}
    • JSON syntax validation
    • Required secrets validation
    • Network configuration validation
    • Service configuration validation
    • Docker compose validation
    • Dependency validation

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            FIX_ERRORS=true
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
            echo "❌ Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 VALIDATION FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

# Check if jq is available
check_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required but not installed" >&2
        echo "💡 Install with: sudo apt-get install jq" >&2
        return 1
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "✅ jq is available ($(jq --version))"
    fi
}

# Check if envsubst is available
check_envsubst() {
    if ! command -v envsubst >/dev/null 2>&1; then
        echo "❌ Error: envsubst is required but not installed" >&2
        echo "💡 Install with: sudo apt-get install gettext-base" >&2
        return 1
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo "✅ envsubst is available"
    fi
}

# Validate service dependencies
validate_service_dependencies() {
    echo "🔗 Validating service dependencies..."
    
    local services
    readarray -t services < <(get_all_services)
    
    for service in "${services[@]}"; do
        if [[ -n "$service" ]]; then
            local dependencies
            readarray -t dependencies < <(get_service_dependencies "$service" "required")
            
            for dep in "${dependencies[@]}"; do
                if [[ -n "$dep" ]]; then
                    local service_dir="$CONFIG_DIR/services/$dep"
                    if [[ ! -d "$service_dir" ]]; then
                        echo "❌ Service '$service' depends on '$dep' but '$dep' service not found" >&2
                        return 1
                    fi
                fi
            done
            
            if [[ "$VERBOSE" == "true" ]]; then
                echo "✅ Dependencies valid for service: $service"
            fi
        fi
    done
    
    echo "✅ All service dependencies are valid"
}

# Validate deployment order
validate_deployment_order() {
    echo "📋 Validating deployment order..."
    
    local deploy_order
    readarray -t deploy_order < <(get_deployment_order)
    
    local auto_deploy
    readarray -t auto_deploy < <(get_auto_deploy_services)
    
    # Check if all auto-deploy services are in deployment order
    for service in "${auto_deploy[@]}"; do
        if [[ -n "$service" ]]; then
            local found=false
            for ordered_service in "${deploy_order[@]}"; do
                if [[ "$ordered_service" == "$service" ]]; then
                    found=true
                    break
                fi
            done
            
            if [[ "$found" == false ]]; then
                echo "❌ Service '$service' is in auto_deploy but not in deploy_order" >&2
                return 1
            fi
        fi
    done
    
    echo "✅ Deployment order is valid"
}

# ══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN VALIDATION ROUTINE
# ══════════════════════════════════════════════════════════════════════════════

main() {
    banner "🔍 CONFIGURATION VALIDATION"
    
    # Check prerequisites
    echo "🔧 Checking prerequisites..."
    check_jq || exit 1
    check_envsubst || exit 1
    
    # Initialize configuration
    echo "📋 Initializing configuration..."
    if ! init_config; then
        echo "❌ Failed to initialize configuration" >&2
        exit 1
    fi
    
    # Run comprehensive validation
    echo "🔍 Running comprehensive validation..."
    if ! run_comprehensive_validation; then
        echo "❌ Configuration validation failed" >&2
        exit 1
    fi
    
    # Additional validations
    echo "🔗 Running additional validations..."
    validate_service_dependencies || exit 1
    validate_deployment_order || exit 1
    
    # Show configuration summary
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        print_config_summary
    fi
    
    # Show service summary
    if [[ "$VERBOSE" == "true" ]]; then
        echo ""
        echo "📋 Service Summary:"
        local services
        readarray -t services < <(get_all_services)
        for service in "${services[@]}"; do
            if [[ -n "$service" ]]; then
                print_service_summary "$service"
                echo ""
            fi
        done
    fi
    
    echo ""
    echo "✅ All validations passed successfully!"
    echo "🚀 Configuration is ready for deployment"
}

# Run main function
main "$@"