#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         CONFIGURATION VALIDATION                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Wrapper for new JSON validation system
# ✅ Uses comprehensive validation from lib/validation.sh

# Get script directory
HELPERS_VALIDATION_SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VALIDATION_LIB_DIR="$(dirname "$HELPERS_VALIDATION_SCRIPT_DIR")/lib"

# Source common functions
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Source new validation library
source "$VALIDATION_LIB_DIR/validation.sh"

validate_configuration() {
    log "STEP" "Validating JSON configuration..."
    
    # Use new comprehensive validation
    run_comprehensive_validation
}

# Maintain compatibility with old function names
validate_yaml_syntax() {
    log "INFO" "JSON validation (replacing YAML syntax check)..."
    validate_all_configs
}

validate_required_fields() {
    log "INFO" "Validating required fields..."
    validate_secrets
}

validate_network_configuration() {
    log "INFO" "Validating network configuration..."
    validate_network_config
}

validate_service_configuration() {
    log "INFO" "Validating service configuration..."
    validate_all_services
}

validate_resource_allocation() {
    log "INFO" "Resource allocation validation included in service validation"
    return 0
}