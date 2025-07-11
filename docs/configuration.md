# ⚙️ Configuration Reference

This guide explains how to configure your modern Python-based Proxmox homelab.

## 🎯 Configuration Overview

The homelab uses a modern Python-based configuration system with type-safe validation:

- **`.env`** - Environment secrets and deployment settings
- **Pydantic models** - Type-safe configuration with automatic validation
- **Service discovery** - Automatic detection of services from directories
- **Template engine** - Jinja2 for reliable variable substitution

## 🚀 Getting Started

### 1. Environment Configuration

```bash
# Copy the example configuration
cp .env.example .env

# Edit with your values
nano .env
```

### 2. Required Configuration

Fill in these **required** variables in your `.env` file:

```bash
# Domain and administration
DOMAIN=yourdomain.com
ADMIN_EMAIL=admin@yourdomain.com

# Network configuration (management network)
MANAGEMENT_SUBNET=192.168.1.0/24
MANAGEMENT_GATEWAY=192.168.1.1

# Proxmox server details
PROXMOX_HOST=192.168.1.100
PROXMOX_TOKEN=root@pam!homelab-deploy=your-proxmox-api-token

# Storage configuration
NFS_SERVER=192.168.1.200

# Authentication and security
AUTHENTIK_ADMIN_PASSWORD=your-secure-password
CLOUDFLARE_API_TOKEN=your-cloudflare-api-token
```

### 3. Network Configuration

The system automatically creates an **isolated container network**:

```bash
# Container network (automatically created)
CONTAINER_SUBNET=10.0.0.0/24
CONTAINER_GATEWAY=10.0.0.1
```

### 4. Optional Features

Add these for enhanced functionality:

```bash
# External access via Cloudflare tunnel
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token

# VPN privacy (NordVPN WireGuard)
NORDVPN_PRIVATE_KEY=your-nordvpn-wireguard-key
# OR NordVPN OpenVPN
NORDVPN_USERNAME=your-nordvpn-username
NORDVPN_PASSWORD=your-nordvpn-password

# Deployment notifications
DISCORD_WEBHOOK=https://discord.com/api/webhooks/your-webhook-url

# Timezone (optional, defaults to UTC)
TZ=America/New_York
```

## 📋 Configuration Validation

The Python system provides **comprehensive validation** before deployment:

```bash
# Validate all configuration
python scripts/deploy.py validate-only

# This automatically checks:
# ✅ Network configuration and IP allocation
# ✅ Proxmox connectivity and API access
# ✅ NFS server reachability
# ✅ Required secrets and tokens
# ✅ Service configuration syntax
# ✅ Service dependencies
```

## 🏗️ Configuration Components

### Environment Variables (`.env`)
- **Secrets**: API tokens, passwords, private keys
- **Network settings**: IP ranges, hostnames, domains
- **Feature toggles**: Optional services and integrations

### Pydantic Models
- **Type safety**: Automatic type validation and conversion
- **Error prevention**: Clear error messages for invalid configurations
- **Documentation**: Built-in field descriptions and examples

### Service Discovery
- **Automatic detection**: Services discovered from `config/services/` directories
- **Dependency resolution**: Automatic deployment ordering
- **Flexible structure**: Add services by creating directories

## 📦 Service Configuration

Each service requires **three configuration files**:

### `container.json`
Defines the **LXC container** configuration:
```json
{
  "container_id": 110,
  "hostname": "service-name",
  "ip_address": "10.0.0.10",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20
}
```

### `service.json`
Defines **service metadata** and behavior:
```json
{
  "service": {
    "name": "service-name",
    "description": "Service description",
    "category": "media"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["vpn-gateway"]
  }
}
```

### `docker-compose.yaml`
Standard **Docker Compose** service definition:
```yaml
version: '3.8'
services:
  app:
    image: linuxserver/app:latest
    # ... standard Docker Compose configuration
```

## 🎨 Template Processing

The system uses **Jinja2 templates** for reliable variable substitution:

```yaml
# In docker-compose.yaml
version: '3.8'
services:
  app:
    image: app:latest
    environment:
      - DOMAIN={{ domain }}
      - ADMIN_EMAIL={{ admin_email }}
      - API_KEY={{ cloudflare_api_token }}
    labels:
      - "traefik.http.routers.app.rule=Host(`app.{{ domain }}`)"
```

**Template variables available:**
- All environment variables from `.env`
- Network configuration (subnets, gateways, IPs)
- Service-specific settings
- Container configuration

## ✅ Configuration Validation

The Python CLI provides **comprehensive validation**:

```bash
# Run all validation checks
python scripts/deploy.py validate-only

# List discovered services
python scripts/deploy.py list-services --details

# Test deployment without changes
python scripts/deploy.py deploy --dry-run

# Deploy specific services only
python scripts/deploy.py deploy --services pihole,nginx-proxy
```

**Validation includes:**
- ✅ **Network validation**: IP ranges, gateway accessibility, no conflicts
- ✅ **System validation**: Required commands, Python version, permissions
- ✅ **Proxmox validation**: API connectivity, authentication, version check
- ✅ **Storage validation**: NFS server connectivity and mount accessibility
- ✅ **Service validation**: JSON syntax, YAML syntax, dependency resolution
- ✅ **Secret validation**: Required API tokens and passwords present

## 📦 Adding New Services

The new **service discovery system** makes adding services incredibly easy:

### 1. Create Service Directory
```bash
# Create directory for your service
mkdir config/services/sonarr
```

### 2. Create Configuration Files

**`container.json`** (LXC container settings):
```json
{
  "container_id": 110,
  "hostname": "sonarr",
  "ip_address": "10.0.0.10",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20
}
```

**`service.json`** (service metadata):
```json
{
  "service": {
    "name": "sonarr",
    "description": "TV show management",
    "category": "media"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["vpn-gateway"]
  }
}
```

**`docker-compose.yaml`** (standard Docker Compose):
```yaml
version: '3.8'
services:
  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    # ... standard configuration
```

### 3. Deploy Automatically
```bash
# Service is automatically discovered!
python scripts/deploy.py list-services

# Deploy the new service
python scripts/deploy.py deploy --services sonarr
```

**No manual registration required** - services are automatically discovered from directories!

## 🔧 Troubleshooting

### Configuration Issues

**1. Validation Failures:**
```bash
# Run comprehensive validation
python scripts/deploy.py validate-only

# Check specific error messages
# Python provides clear, detailed error descriptions
```

**2. Network Configuration:**
```bash
# Test Proxmox connectivity
curl -k https://192.168.1.100:8006/api2/json/version

# Test NFS server
ping 192.168.1.200
showmount -e 192.168.1.200
```

**3. Service Discovery Issues:**
```bash
# Check service structure
python scripts/deploy.py list-services --details

# Verify required files exist
ls config/services/*/container.json
ls config/services/*/service.json
ls config/services/*/docker-compose.y*ml
```

### Common Problems

- **Missing environment variables**: Check `.env` file for all required values
- **Invalid JSON/YAML syntax**: Use validation to get specific error locations
- **Network conflicts**: Ensure management and container networks don't overlap
- **Service dependencies**: Use `list-services` to check dependency resolution
- **API connectivity**: Verify Proxmox and Cloudflare tokens are correct

## 🔐 Security Best Practices

### Environment Security
1. **Never commit `.env` file** - Add to `.gitignore` (already included)
2. **Use strong passwords** - Generate secure 20+ character passwords
3. **Rotate API tokens** - Regularly regenerate Proxmox and Cloudflare tokens
4. **Secure NFS** - Use proper NFS export restrictions and authentication

### Network Security
1. **Network isolation** - Services isolated from management network
2. **VPN privacy** - Route download services through VPN gateway
3. **DNS filtering** - All DNS queries filtered through Pi-hole
4. **SSL everywhere** - Automatic SSL certificates for all services

### Configuration Security
1. **Type validation** - Pydantic prevents many configuration errors
2. **Secret management** - Environment variables for all sensitive data
3. **Least privilege** - Services run with minimal required permissions
4. **Regular validation** - Run validation before each deployment

## 🚀 Advanced Configuration

### Custom Network Ranges
Override default network settings:
```bash
# Custom management network
MANAGEMENT_SUBNET=10.10.10.0/24
MANAGEMENT_GATEWAY=10.10.10.1

# Custom container network
CONTAINER_SUBNET=172.16.0.0/24
CONTAINER_GATEWAY=172.16.0.1
```

### Multiple Domains
```bash
# Primary domain
DOMAIN=homelab.local

# Additional domains in service configurations
# Services can specify their own domain overrides
```

### High Availability
- **Proxmox clustering**: Configure multiple Proxmox nodes
- **Service redundancy**: Deploy critical services on multiple containers
- **Storage redundancy**: Use replicated NFS or distributed storage

## 🆘 Getting Help

```bash
# Comprehensive validation and troubleshooting
python scripts/deploy.py validate-only

# List all discovered services and their status
python scripts/deploy.py list-services --details

# View CLI help
python scripts/deploy.py --help
```

**Documentation:**
- **[Installation Guide](installation.md)** - Complete setup process
- **[Service Management](services.md)** - Adding and managing services
- **[CLI Reference](cli-reference.md)** - Complete command documentation
- **[GitHub Issues](https://github.com/Khizar-Hussian/proxmox-homelab-template/issues)** - Report bugs or ask questions