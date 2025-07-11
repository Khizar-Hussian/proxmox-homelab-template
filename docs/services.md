# 📦 Service Management Guide

This guide covers how to add, configure, update, and manage services in your modern Python-based homelab.

## 🎯 Service Architecture

### Core vs User Services

- **Core Services** - Auto-deployed infrastructure (Pi-hole, Nginx, etc.)
- **User Services** - Optional services you add (Nextcloud, Jellyfin, etc.)
- **Service Discovery** - Automatic detection from directory structure

### Service Structure

Every service requires **three files** for automatic discovery:

```
config/services/service-name/
├── container.json           # LXC container configuration
├── service.json            # Service metadata and dependencies
└── docker-compose.yaml     # Docker Compose service definition
```

**Automatic discovery** - Just create the directory with these files!

## 🚀 Adding a New Service

### Step 1: Create Service Directory

```bash
# Create directory for your service
mkdir config/services/nextcloud
```

### Step 2: Container Configuration

Create `container.json`:

```json
{
  "container_id": 150,
  "hostname": "nextcloud",
  "ip_address": "10.0.0.60",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20
}
```

### Step 3: Service Metadata

Create `service.json`:

```json
{
  "service": {
    "name": "nextcloud",
    "description": "File sharing and collaboration platform",
    "category": "productivity"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["authentik"]
  }
}
```

### Step 4: Docker Compose Configuration

Create `docker-compose.yaml`:

```yaml
version: '3.8'

services:
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    restart: unless-stopped
    
    ports:
      - "80:80"
      
    environment:
      - MYSQL_HOST=db
      - MYSQL_DATABASE={{ mysql_database | default('nextcloud') }}
      - MYSQL_USER={{ mysql_user | default('nextcloud') }}
      - MYSQL_PASSWORD={{ mysql_password }}
      - TRUSTED_DOMAINS={{ domain }}
      - OVERWRITEPROTOCOL=https
      - OVERWRITEHOST=nextcloud.{{ domain }}
      
    volumes:
      - nextcloud-data:/var/www/html
      - /opt/appdata/nextcloud:/var/www/html/data
      
    depends_on:
      - db
      
  db:
    image: mariadb:latest
    container_name: nextcloud-db
    restart: unless-stopped
    
    environment:
      - MYSQL_ROOT_PASSWORD={{ mysql_root_password }}
      - MYSQL_DATABASE={{ mysql_database | default('nextcloud') }}
      - MYSQL_USER={{ mysql_user | default('nextcloud') }}
      - MYSQL_PASSWORD={{ mysql_password }}
      
    volumes:
      - mysql-data:/var/lib/mysql

volumes:
  nextcloud-data:
  mysql-data:
```

### Step 5: Deploy the Service

```bash
# Service is automatically discovered!
python scripts/deploy.py list-services

# Deploy the new service
python scripts/deploy.py deploy --services nextcloud

# Or deploy all services
python scripts/deploy.py deploy
```

**That's it!** The service is automatically discovered and can be deployed immediately.

## 📋 Service Examples

### Simple Web Application

**`container.json`**:
```json
{
  "container_id": 151,
  "hostname": "uptime-kuma",
  "ip_address": "10.0.0.61",
  "cpu_cores": 1,
  "memory_mb": 512,
  "disk_gb": 5
}
```

**`service.json`**:
```json
{
  "service": {
    "name": "uptime-kuma",
    "description": "Uptime monitoring dashboard",
    "category": "monitoring"
  },
  "dependencies": {
    "required": ["pihole"],
    "optional": ["nginx-proxy"]
  }
}
```

**`docker-compose.yaml`**:
```yaml
version: '3.8'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - uptime-data:/app/data

volumes:
  uptime-data:
```

### Media Server

**`container.json`**:
```json
{
  "container_id": 152,
  "hostname": "jellyfin",
  "ip_address": "10.0.0.70",
  "cpu_cores": 4,
  "memory_mb": 4096,
  "disk_gb": 20
}
```

**`service.json`**:
```json
{
  "service": {
    "name": "jellyfin",
    "description": "Media streaming server",
    "category": "media"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["authentik"]
  }
}
```

**`docker-compose.yaml`**:
```yaml
version: '3.8'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "8096:8096"
    volumes:
      - jellyfin-config:/config
      - /mnt/media:/media:ro  # NFS mount from host
    environment:
      - JELLYFIN_PublishedServerUrl=https://jellyfin.{{ domain }}

volumes:
  jellyfin-config:
```

### Download Client with VPN

Services that need privacy automatically use the VPN gateway:

**`container.json`**:
```json
{
  "container_id": 153,
  "hostname": "qbittorrent",
  "ip_address": "10.0.0.13",
  "cpu_cores": 2,
  "memory_mb": 1024,
  "disk_gb": 10
}
```

**`service.json`**:
```json
{
  "service": {
    "name": "qbittorrent",
    "description": "BitTorrent client with VPN privacy",
    "category": "media"
  },
  "dependencies": {
    "required": ["vpn-gateway"],
    "optional": ["prowlarr"]
  }
}
```

**`docker-compose.yaml`**:
```yaml
version: '3.8'
services:
  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    
    environment:
      - PUID=1000
      - PGID=1000
      - TZ={{ timezone | default('UTC') }}
      - WEBUI_PORT=8080
      
    volumes:
      - qb-config:/config
      - /mnt/downloads:/downloads  # NFS mount from host
      
    ports:
      - "8080:8080"
      
    # VPN routing handled by network configuration
    
volumes:
  qb-config:
```

## 🔧 Service Management

### List All Services

```bash
# List discovered services
python scripts/deploy.py list-services

# List with detailed information
python scripts/deploy.py list-services --details
```

### Deploy Services

```bash
# Deploy all auto-deploy services
python scripts/deploy.py deploy

# Deploy specific services
python scripts/deploy.py deploy --services nextcloud,jellyfin

# Test deployment without making changes
python scripts/deploy.py deploy --dry-run
```

### Update a Service

```bash
# Edit service configuration
nano config/services/nextcloud/docker-compose.yaml

# Redeploy the service
python scripts/deploy.py deploy --services nextcloud
```

### Remove a Service

```bash
# Remove service directory
rm -rf config/services/nextcloud/

# Service is automatically removed from discovery
python scripts/deploy.py list-services
```

### Service Status

```bash
# Check container status
pct status 150

# View service logs
pct exec 150 -- docker logs nextcloud

# Check all containers in service
pct exec 150 -- docker ps
```

## 📊 Service Configuration Reference

### Container Configuration (`container.json`)

```json
{
  "container_id": 150,        // Required: Unique container ID
  "hostname": "service-name", // Required: Container hostname
  "ip_address": "10.0.0.60",  // Required: Container IP address
  
  "cpu_cores": 2,             // Optional: CPU cores (default: 1)
  "memory_mb": 2048,          // Optional: RAM in MB (default: 512)
  "disk_gb": 20,              // Optional: Disk space in GB (default: 8)
  
  "features": [               // Optional: LXC features
    "nesting=1",              // Enable Docker nesting
    "keyctl=1"                // Enable keyctl
  ],
  
  "mounts": [                 // Optional: Additional mounts
    {
      "source": "/mnt/media",  // Host path
      "target": "/media",      // Container path
      "readonly": true         // Mount as read-only
    }
  ]
}
```

### Service Metadata (`service.json`)

```json
{
  "service": {
    "name": "service-name",            // Required: Service name
    "description": "Service description", // Optional: Description
    "category": "media",               // Optional: Category
    "subcategory": "streaming",       // Optional: Subcategory
    "tags": ["media", "streaming"]    // Optional: Tags
  },
  
  "dependencies": {
    "required": ["pihole", "nginx-proxy"], // Required services
    "optional": ["authentik"],            // Optional services
    "conflicts": []                       // Conflicting services
  },
  
  "external_access": {          // Optional: External access config
    "enabled": true,           // Enable external access
    "subdomain": "service",    // Subdomain for access
    "public": false,           // Public vs private access
    "authentication_required": true // Require authentication
  },
  
  "monitoring": {              // Optional: Monitoring config
    "enabled": true,           // Enable monitoring
    "metrics_available": true, // Metrics endpoint available
    "port": 9090              // Metrics port
  }
}
```

### Docker Compose Best Practices

```yaml
version: '3.8'

services:
  app:
    image: app:latest
    container_name: app-name
    hostname: app.{{ domain }}
    restart: unless-stopped
    
    ports:
      - "80:80"                    # Port mapping
      
    environment:
      # Use Jinja2 template variables
      - DB_PASSWORD={{ mysql_password }}
      - API_KEY={{ api_key }}
      - TZ={{ timezone | default('UTC') }}
      - DOMAIN={{ domain }}
      
    volumes:
      # Use named volumes for data
      - app-data:/data
      
      # Use host paths for persistent config
      - /opt/appdata/app:/config
      
      # Use NFS mounts for shared storage
      - /mnt/media:/media:ro
      
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      
    # Labels for service management
    labels:
      - "homelab.service=app-name"
      - "homelab.category=productivity"
      - "homelab.url=https://app.{{ domain }}"

volumes:
  app-data:
    driver: local
```

**Template Variables Available:**
- `{{ domain }}` - Your domain name
- `{{ admin_email }}` - Admin email address
- `{{ timezone }}` - System timezone
- Any environment variable from `.env`
- Service-specific configuration

## 🎯 IP Address Allocation

### Network Segmentation Strategy

**Management Network**: `192.168.1.0/24` (your home network)
- Proxmox host, NFS server, your devices

**Container Network**: `10.0.0.0/24` (isolated container network)
- All services run in this isolated network

### Recommended IP Ranges

| Range | Purpose | Examples |
|-------|---------|----------|
| `10.0.0.10-19` | Media downloads | qBittorrent, SABnzbd, Prowlarr |
| `10.0.0.20-29` | Development | GitLab, Code Server, Jenkins |
| `10.0.0.30-39` | Utilities | Uptime Kuma, Portainer, Watchtower |
| `10.0.0.40-49` | **Core infrastructure** | Pi-hole (.41), VPN (.42), Nginx (.43), Homepage (.44), Grafana (.45), Authentik (.46) |
| `10.0.0.50-59` | Home automation | Home Assistant, ESPHome, Zigbee2MQTT |
| `10.0.0.60-69` | Productivity | Nextcloud, Vaultwarden, Paperless |
| `10.0.0.70-79` | Media services | Jellyfin, Photoprism, Immich |
| `10.0.0.80-89` | Arr stack | Sonarr, Radarr, Lidarr, Bazarr |
| `10.0.0.90-99` | Communication | Matrix, Discord bots, Email |
| `10.0.0.100+` | Custom services | Your experimental services |

### Container ID Convention

Container IDs should be unique and **not** follow IP addressing:
- Use sequential IDs starting from 100
- Core services: 100-119
- User services: 120+

## 🔐 Security Best Practices

### Template Variables (Secure)

**❌ Never hardcode secrets:**
```yaml
environment:
  - MYSQL_PASSWORD=hardcoded123  # Bad!
```

**✅ Use Jinja2 template variables:**
```yaml
environment:
  - MYSQL_PASSWORD={{ mysql_password }}  # Good!
  - API_KEY={{ cloudflare_api_token }}   # Template variables
```

### Network Security

**✅ Automatic network isolation:**
- Services run in isolated `10.0.0.0/24` network
- No direct access to management network
- DNS filtered through Pi-hole
- VPN routing for download services

### Container Security

```yaml
# Run as non-root when possible
user: "1000:1000"

# Drop unnecessary capabilities
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - SETGID

# Security options
security_opt:
  - no-new-privileges:true

# Resource limits
deploy:
  resources:
    limits:
      memory: 512M
      cpus: '1.0'
```

### Service Security

```yaml
# Bind to localhost only when needed
ports:
  - "127.0.0.1:8080:80"
  
# Use read-only mounts when possible
volumes:
  - /mnt/media:/media:ro
  
# Environment-specific secrets
environment:
  - SECRET_KEY={{ secret_key }}  # From .env file
```

## 📦 Service Categories

### Core Infrastructure (Auto-deployed)

- **Pi-hole** (10.0.0.41) - DNS + Ad blocking
- **VPN Gateway** (10.0.0.42) - Privacy tunnel for downloads
- **Nginx Proxy** (10.0.0.43) - Reverse proxy + SSL certificates
- **Homepage** (10.0.0.44) - Service dashboard
- **Grafana** (10.0.0.45) - Monitoring dashboards
- **Authentik** (10.0.0.46) - Single sign-on authentication

### Media Services

- **Jellyfin** - Media streaming server
- **Photoprism** - Photo management and sharing
- **Immich** - Google Photos alternative
- **Navidrome** - Music streaming server

### Productivity Suite

- **Nextcloud** - File sharing and collaboration
- **Vaultwarden** - Password manager (Bitwarden compatible)
- **Paperless-ngx** - Document management
- **Standard Notes** - Note taking application

### Download Stack (VPN-routed)

- **qBittorrent** - Torrent client with web UI
- **SABnzbd** - Usenet downloader
- **Prowlarr** - Indexer manager for Arr stack
- **Sonarr/Radarr/Lidarr** - Media collection managers

### Home Automation

- **Home Assistant** - Smart home hub
- **ESPHome** - ESP device management
- **Zigbee2MQTT** - Zigbee device bridge
- **Node-RED** - Flow-based automation

### Development Tools

- **GitLab** - Git repository and CI/CD
- **Code Server** - VS Code in the browser
- **Jenkins** - Continuous integration
- **Portainer** - Docker container management

## 🔧 Troubleshooting Services

### Configuration Issues

**Service not discovered:**
```bash
# Check service structure
python scripts/deploy.py list-services --details

# Verify required files exist
ls config/services/service-name/
# Should show: container.json, service.json, docker-compose.yaml
```

**Validation failures:**
```bash
# Run comprehensive validation
python scripts/deploy.py validate-only

# Python provides clear error messages with line numbers
```

### Service Issues

**Service won't start:**
```bash
# Check container status
pct status 150

# View container creation logs
pct config 150

# Check Docker containers inside
pct exec 150 -- docker ps -a

# View service logs
pct exec 150 -- docker logs service-name
```

**Network connectivity:**
```bash
# Test container network
pct exec 150 -- ping 8.8.8.8
pct exec 150 -- ping 10.0.0.41  # Pi-hole

# Check service endpoint
curl -I http://10.0.0.60:80

# Test from host
telnet 10.0.0.60 80
```

**Storage issues:**
```bash
# Check disk space
pct exec 150 -- df -h

# Check mount points
pct exec 150 -- mount | grep "/mnt"

# Test NFS from container
pct exec 150 -- ls -la /mnt/media
```

### Service Recovery

**Restart service:**
```bash
# Restart container
pct restart 150

# Or restart just Docker services
pct exec 150 -- docker compose restart
```

**Redeploy service:**
```bash
# Redeploy with Python CLI
python scripts/deploy.py deploy --services service-name

# This will recreate the container and deploy fresh
```

**Full service reset:**
```bash
# Stop and remove container
pct stop 150
pct destroy 150

# Redeploy from scratch
python scripts/deploy.py deploy --services service-name
```

**Reset service data only:**
```bash
# Stop service
pct exec 150 -- docker compose down

# Remove volumes (careful!)
pct exec 150 -- docker volume rm service_data

# Restart service
pct exec 150 -- docker compose up -d
```

## 🚀 Advanced Service Features

### Automatic Dependency Resolution

The Python system automatically handles dependencies:

```json
// In service.json
{
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["authentik"]
  }
}
```

**Automatic deployment order:**
1. Pi-hole (no dependencies)
2. Nginx Proxy (depends on Pi-hole)
3. Your service (depends on both)

### Service Discovery Features

```bash
# List services by category
python scripts/deploy.py list-services --details

# Deploy by category
python scripts/deploy.py deploy --services $(python scripts/deploy.py list-services | grep media)

# Validate dependency chain
python scripts/deploy.py validate-only
```

### Template Processing

Services can use **Jinja2 templates** for dynamic configuration:

```yaml
# In docker-compose.yaml
services:
  app:
    environment:
      - DATABASE_URL=postgres://{{ postgres_user }}:{{ postgres_password }}@db:5432/{{ postgres_db }}
      - REDIS_URL=redis://redis:6379/{{ redis_db | default('0') }}
      - DOMAIN={{ domain }}
```

### Service Categories

Services are automatically organized by category from `service.json`:
- **infrastructure** - Core services (DNS, proxy, monitoring)
- **media** - Media servers and download clients
- **productivity** - Office and collaboration tools
- **automation** - Home automation and IoT
- **development** - Development tools and CI/CD

---

📖 **[← Installation Guide](installation.md)** | **[Configuration Reference →](configuration.md)** | **[CLI Reference →](cli-reference.md)**