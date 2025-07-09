#!/bin/bash

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                          HOMELAB HEALTH CHECK SCRIPT                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# 🎯 PURPOSE: Comprehensive health check for all homelab services
# 📊 FEATURES: Service status, connectivity tests, resource monitoring
# 🚨 USAGE: ./scripts/health-check.sh [service-name]

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"