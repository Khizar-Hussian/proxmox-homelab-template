# Configuration Guide

This guide explains how to configure your Proxmox homelab using the JSON-based configuration system.

## Configuration Overview

The homelab uses a modern JSON-based configuration system with two main components:

1. **`.env`** - Contains secrets and environment-specific values
2. **`config/cluster.json`** - Contains the main configuration with inline documentation

## Getting Started

### 1. Create Your Environment File

```bash
cp .env.example .env
nano .env
```

### 2. Required Configuration

Fill in these required variables in your `.env` file:

```bash
# Domain and admin settings
DOMAIN=yourdomain.com
ADMIN_EMAIL=admin@yourdomain.com

# Proxmox connection
PROXMOX_HOST=192.168.1.10
PROXMOX_TOKEN=root@pam!homelab=your-api-token

# Network configuration
MANAGEMENT_SUBNET=192.168.1.0/24
MANAGEMENT_GATEWAY=192.168.1.1

# Storage
NFS_SERVER=192.168.1.20

# Authentication
AUTHENTIK_ADMIN_PASSWORD=your-secure-password

# SSL certificates
CLOUDFLARE_API_TOKEN=your-cloudflare-token
```

### 3. Optional Features

Add these for additional functionality:

```bash
# External access
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token

# VPN privacy
NORDVPN_PRIVATE_KEY=your-nordvpn-key

# Notifications
DISCORD_WEBHOOK=your-discord-webhook-url

# Backup encryption
BACKUP_ENCRYPTION_KEY=your-gpg-key-id
```

## Configuration Structure

The `config/cluster.json` file contains the main configuration organized into logical sections:

### Cluster Settings
- Basic cluster identification
- Domain and timezone settings
- Admin contact information

### Proxmox Configuration
- Server connection details
- Storage and template settings
- API configuration

### Networking
- Management network settings
- Container network configuration
- IP allocation strategies

### Services
- Auto-deployment configuration
- Service deployment order
- Default service settings

### Security
- Authentication providers
- VPN configuration
- Security hardening options

### External Access
- Cloudflare tunnel configuration
- Public vs private service settings
- SSL certificate management

### Monitoring & Backup
- Monitoring stack configuration
- Alert settings
- Backup schedules and retention

## Service Configuration

Each service has two configuration files:

### `container.json`
Defines the LXC container configuration:
- Container ID and network settings
- Resource allocation (CPU, memory, disk)
- Special capabilities and features
- NFS mount points

### `service.json`
Defines service metadata and behavior:
- Service description and categorization
- Dependencies and conflicts
- External access configuration
- Monitoring and backup settings

## Environment Variable Substitution

The JSON configuration supports environment variable substitution using this syntax:

```json
{
  "cluster": {
    "domain": "${DOMAIN}",
    "name": "${CLUSTER_NAME:-homelab}",
    "admin_email": "${ADMIN_EMAIL}"
  }
}
```

- `${VARIABLE}` - Required variable (fails if not set)
- `${VARIABLE:-default}` - Optional variable with default value

## Configuration Validation

Validate your configuration before deployment:

```bash
# Basic validation
./scripts/validate-config.sh

# Detailed validation with verbose output
./scripts/validate-config.sh --verbose

# Test deployment without making changes
./scripts/deploy.sh --dry-run --verbose
```

## Adding New Services

To add a new service:

1. Create service directory: `config/services/myservice/`

2. Create `container.json`:
```json
{
  "container": {
    "id": 150,
    "hostname": "myservice",
    "ip": "10.0.0.70",
    "resources": {
      "cpu": 1,
      "memory": 512,
      "disk": 8
    }
  }
}
```

3. Create `service.json`:
```json
{
  "service": {
    "name": "myservice",
    "display_name": "My Service",
    "description": "Description of my service",
    "category": "productivity"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"]
  }
}
```

4. Create `docker-compose.yaml` with your service definition

5. Add to auto-deployment in `cluster.json` or deploy manually

## Troubleshooting

### Configuration Issues

1. **JSON Syntax Errors**
   ```bash
   # Check JSON syntax
   jq . config/cluster.json
   jq . config/services/*/container.json
   ```

2. **Missing Environment Variables**
   ```bash
   # Check what's missing
   ./scripts/validate-config.sh --verbose
   ```

3. **Network Configuration**
   ```bash
   # Validate network settings
   ./scripts/validate-config.sh
   ```

### Common Problems

- **Invalid JSON**: Use a JSON validator or `jq` to check syntax
- **Missing secrets**: Ensure all required variables are set in `.env`
- **Network conflicts**: Check IP ranges don't overlap
- **Service dependencies**: Ensure dependent services are configured

## Security Best Practices

1. **Never commit `.env` file** - Contains sensitive secrets
2. **Use strong passwords** - Generate secure passwords for all services
3. **Regular backups** - Enable automatic backup encryption
4. **Monitor access** - Review authentication logs regularly
5. **Update regularly** - Keep services and base system updated

## Advanced Configuration

### Custom Network Ranges
Override default network settings:
```bash
MANAGEMENT_SUBNET=10.10.10.0/24
CONTAINER_SUBNET=172.16.0.0/24
```

### Multiple Domains
Configure additional domains in service files or environment variables.

### High Availability
Configure clustering and failover in the Proxmox and service configurations.

## Getting Help

- Run validation: `./scripts/validate-config.sh --verbose`
- Check logs: `./scripts/health-check.sh`
- Review documentation: `docs/` directory
- Open GitHub issue for bugs or questions