#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                            CORE COMMON FUNCTIONS                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 FOCUSED PURPOSE: Essential logging, colors, and basic utilities only
# 📝 Keep this file small and focused - other utilities go in separate files

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ This script should be sourced, not executed directly"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# 🎨 COLORS AND FORMATTING
# ══════════════════════════════════════════════════════════════════════════════

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ══════════════════════════════════════════════════════════════════════════════
# 📊 LOGGING FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")    echo -e "${CYAN}[INFO]${NC}  ${timestamp} - $*" ;;
        "WARN")    echo -e "${YELLOW}[WARN]${NC}  ${timestamp} - $*" ;;
        "ERROR")   echo -e "${RED}[ERROR]${NC} ${timestamp} - $*" >&2 ;;
        "SUCCESS") echo -e "${GREEN}[✓]${NC}    ${timestamp} - $*" ;;
        "STEP")    echo -e "${PURPLE}[STEP]${NC} ${timestamp} - $*" ;;
        "DEBUG")   [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $*" ;;
    esac
}

banner() {
    local text="$1"
    local width=80
    local padding=$(( (width - ${#text} - 2) / 2 ))
    
    echo -e "${BOLD}${BLUE}"
    echo "═══════════════════════════════════════════════════════════════════════════════"
    printf "║%*s%s%*s║\n" $padding "" "$text" $padding ""
    echo "═══════════════════════════════════════════════════════════════════════════════"
    echo -e "${NC}"
}

# ══════════════════════════════════════════════════════════════════════════════
# 🔧 BASIC UTILITIES
# ══════════════════════════════════════════════════════════════════════════════

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if running as root or with sudo
has_root_access() {
    [[ $EUID -eq 0 ]] || sudo -n true 2>/dev/null
}

# Generate secure random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Get configuration value with default
get_config() {
    local path="$1"
    local default_value="${2:-}"
    local config_file="${CLUSTER_CONFIG:-config/cluster.yaml}"
    
    if [[ -f "$config_file" ]]; then
        # Note: This function is deprecated - use get_config() from lib/config.sh instead
        local value=$(jq -r "$path // empty" "$config_file" 2>/dev/null)
        if [[ "$value" != "null" && -n "$value" ]]; then
            echo "$value"
        else
            echo "$default_value"
        fi
    else
        echo "$default_value"
    fi
}

# Check if feature is enabled
is_feature_enabled() {
    local feature_path="$1"
    local default="${2:-false}"
    
    local value=$(get_config "$feature_path" "$default")
    [[ "$value" == "true" ]]
}