# 🖥️ CLI Reference

Complete reference for the Python-based deployment CLI.

## 🚀 Getting Started

The homelab uses a modern Python CLI built with Typer and Rich for beautiful terminal output.

```bash
# Install dependencies
pip install -r requirements.txt

# View help
python scripts/deploy.py --help
```

## 📋 Command Overview

| Command | Description |
|---------|-------------|
| `validate-only` | Run comprehensive validation without deployment |
| `list-services` | List all discovered services |
| `deploy` | Deploy services to Proxmox |
| `--help` | Show help information |

## 🔍 validate-only

Run comprehensive validation of configuration, network, and services.

```bash
python scripts/deploy.py validate-only
```

**What it validates:**
- ✅ **System prerequisites** - Python version, required commands
- ✅ **Network configuration** - IP ranges, gateway accessibility, no conflicts
- ✅ **Proxmox connectivity** - API access, authentication, version compatibility
- ✅ **Storage validation** - NFS server connectivity and accessibility
- ✅ **Service discovery** - JSON syntax, YAML syntax, file structure
- ✅ **Dependency resolution** - Required services exist and are valid

**Example output:**
```
🔍 Running comprehensive validation...
═══════════════════════════════════════════════════════════════════════════════

🔧 Checking system prerequisites...
✅ All system prerequisites satisfied

🔍 Running configuration validation...
✅ Connected to Proxmox VE 8.2-1
✅ All validations passed!

🔧 Validating service configurations...
✅ All service configurations are valid

═══════════════════════════════════════════════════════════════════════════════
✅ All validations passed successfully!
```

## 📦 list-services

List all discovered services with optional details.

### Basic Usage

```bash
python scripts/deploy.py list-services
```

**Example output:**
```
📦 Available Services
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Service                     ┃ Category                    ┃ Auto Deploy                 ┃
┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ pihole                      │ infrastructure              │ ✅                           │
│ vpn-gateway                 │ infrastructure              │ ✅                           │
│ nginx-proxy                 │ infrastructure              │ ✅                           │
│ homepage                    │ infrastructure              │ ✅                           │
│ grafana                     │ monitoring                  │ ✅                           │
│ authentik                   │ security                    │ ✅                           │
│ nextcloud                   │ productivity                │ ❌                           │
│ jellyfin                    │ media                       │ ❌                           │
└─────────────────────────────┴─────────────────────────────┴─────────────────────────────┘
```

### Detailed Information

```bash
python scripts/deploy.py list-services --details
```

**Example output:**
```
📦 Available Services
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Service                     ┃ Category                    ┃ Auto Deploy                 ┃ Dependencies                ┃ Description                 ┃
┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ pihole                      │ infrastructure              │ ✅                           │ None                        │ Network-wide DNS server    │
│ vpn-gateway                 │ infrastructure              │ ✅                           │ pihole                      │ VPN gateway for privacy    │
│ nginx-proxy                 │ infrastructure              │ ✅                           │ pihole                      │ Reverse proxy with SSL     │
│ homepage                    │ infrastructure              │ ✅                           │ pihole, nginx-proxy         │ Service dashboard           │
│ grafana                     │ monitoring                  │ ✅                           │ pihole, nginx-proxy         │ Monitoring dashboards       │
│ authentik                   │ security                    │ ✅                           │ pihole, nginx-proxy         │ Single sign-on auth         │
│ nextcloud                   │ productivity                │ ❌                           │ pihole, nginx-proxy         │ File sharing platform      │
│ jellyfin                    │ media                       │ ❌                           │ pihole, nginx-proxy         │ Media streaming server      │
└─────────────────────────────┴─────────────────────────────┴─────────────────────────────┴─────────────────────────────┴─────────────────────────────┘
```

## 🚀 deploy

Deploy services to Proxmox with various options.

### Deploy All Auto-Deploy Services

```bash
python scripts/deploy.py deploy
```

This deploys all services marked with `auto_deploy: true` in their configuration.

### Deploy Specific Services

```bash
python scripts/deploy.py deploy --services pihole,nginx-proxy
```

**Multiple services:**
```bash
python scripts/deploy.py deploy --services "pihole,vpn-gateway,nginx-proxy,homepage"
```

### Dry Run (Preview Changes)

```bash
python scripts/deploy.py deploy --dry-run
```

**With specific services:**
```bash
python scripts/deploy.py deploy --services nextcloud,jellyfin --dry-run
```

**Example dry run output:**
```
🏗️ Deployment Plan (DRY RUN)
═══════════════════════════════════════════════════════════════════════════════

📋 Services to deploy (2):
• nextcloud (productivity)
• jellyfin (media)

🔄 Deployment order:
1. nextcloud (dependencies: pihole, nginx-proxy)
2. jellyfin (dependencies: pihole, nginx-proxy)

🏗️ Actions that would be performed:
• Create LXC container 150 for nextcloud
• Configure networking: 10.0.0.60/24
• Install Docker and Docker Compose
• Deploy service: nextcloud
• Create LXC container 151 for jellyfin
• Configure networking: 10.0.0.70/24
• Install Docker and Docker Compose
• Deploy service: jellyfin

⚠️ DRY RUN: No changes were made
```

## 🔧 Global Options

### Help

```bash
python scripts/deploy.py --help
```

```bash
python scripts/deploy.py deploy --help
```

### Version Information

```bash
python scripts/deploy.py --version
```

## 📊 Command Examples

### Complete Deployment Workflow

```bash
# 1. Validate configuration
python scripts/deploy.py validate-only

# 2. List available services
python scripts/deploy.py list-services --details

# 3. Test deployment
python scripts/deploy.py deploy --dry-run

# 4. Deploy core services
python scripts/deploy.py deploy

# 5. Deploy additional services
python scripts/deploy.py deploy --services nextcloud,jellyfin
```

### Service Discovery and Validation

```bash
# Quick service check
python scripts/deploy.py list-services

# Detailed service information
python scripts/deploy.py list-services --details

# Validate specific service configurations
python scripts/deploy.py validate-only
```

### Selective Deployment

```bash
# Deploy only infrastructure services
python scripts/deploy.py deploy --services pihole,nginx-proxy,homepage

# Deploy media stack
python scripts/deploy.py deploy --services jellyfin,sonarr,radarr,prowlarr

# Deploy productivity tools
python scripts/deploy.py deploy --services nextcloud,vaultwarden,paperless
```

## 🎨 Rich Terminal Output

The CLI provides beautiful terminal output with:

- **Progress bars** for long-running operations
- **Color-coded status** (green for success, red for errors, yellow for warnings)
- **Structured tables** for service listings
- **Detailed error messages** with actionable suggestions
- **Hierarchical output** for complex operations

## 🔍 Troubleshooting Commands

### Validation Issues

```bash
# Full validation with detailed output
python scripts/deploy.py validate-only

# Check specific service discovery
python scripts/deploy.py list-services --details
```

### Deployment Issues

```bash
# Test deployment without making changes
python scripts/deploy.py deploy --dry-run

# Deploy with verbose output (if available)
python scripts/deploy.py deploy --verbose
```

### Service Issues

```bash
# Check if service is discovered
python scripts/deploy.py list-services | grep service-name

# Validate service configuration
python scripts/deploy.py validate-only
```

## 📁 Configuration Files

The CLI reads configuration from:

- **`.env`** - Environment variables and secrets
- **`config/services/`** - Service discovery directory
- **`scripts/lib/models.py`** - Pydantic configuration models
- **`scripts/lib/service_discovery.py`** - Service discovery logic

## 🚀 Advanced Usage

### Service Categories

Services are automatically categorized:

- **infrastructure** - Core services (DNS, proxy, monitoring)
- **media** - Media servers and download clients  
- **productivity** - Office and collaboration tools
- **security** - Authentication and VPN services
- **monitoring** - Metrics and dashboards
- **automation** - Home automation and IoT

### Dependency Resolution

The CLI automatically resolves dependencies:

1. **Discovers all services** from directories
2. **Validates dependencies** exist and are valid
3. **Orders deployment** based on dependency graph
4. **Handles circular dependencies** with warnings

### Template Processing

Services can use **Jinja2 templates** in their docker-compose.yaml:

```yaml
services:
  app:
    environment:
      - DOMAIN={{ domain }}
      - ADMIN_EMAIL={{ admin_email }}
      - DATABASE_URL=postgres://{{ postgres_user }}:{{ postgres_password }}@db:5432/{{ postgres_db }}
```

**Available template variables:**
- All environment variables from `.env`
- Network configuration (subnets, gateways)
- Service-specific settings
- Container configuration

## 🔐 Security Features

### Environment Variable Handling

- **Never logs secrets** - Sensitive data is filtered from output
- **Validates required secrets** - Fails early if secrets are missing
- **Secure template processing** - Jinja2 templates with proper escaping

### Network Validation

- **IP conflict detection** - Prevents overlapping networks
- **Gateway validation** - Ensures gateways are in correct subnets
- **Connectivity testing** - Validates Proxmox and NFS connectivity

### Service Validation

- **JSON schema validation** - Ensures proper service configuration
- **YAML syntax checking** - Validates Docker Compose files
- **Dependency verification** - Checks all dependencies exist

## 📚 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Validation failed |
| 2 | Configuration error |
| 3 | Network error |
| 4 | Service error |
| 5 | Deployment error |

## 🔄 Integration

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Validate homelab configuration
  run: |
    pip install -r requirements.txt
    python scripts/deploy.py validate-only

- name: Deploy homelab
  run: |
    python scripts/deploy.py deploy
```

### Scripting

```bash
#!/bin/bash
# Deploy script with error handling

set -e

echo "🔍 Validating configuration..."
python scripts/deploy.py validate-only

echo "📋 Listing services..."
python scripts/deploy.py list-services --details

echo "🚀 Deploying services..."
python scripts/deploy.py deploy

echo "✅ Deployment complete!"
```

---

📖 **[← Services Guide](services.md)** | **[Configuration Reference →](configuration.md)**