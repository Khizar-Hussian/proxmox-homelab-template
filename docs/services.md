# 📦 Service Management Guide

This guide covers how to add, configure, update, and manage services in your homelab.

## 🎯 Service Architecture

### Core vs User Services

- **Core Services** - Auto-deployed infrastructure (Pi-hole, Nginx, etc.)
- **User Services** - Optional services you add (Nextcloud, Jellyfin, etc.)

Both use the same **YAML + Docker Compose** pattern for consistency.

### Service Structure

Every service requires two files:

```
config/services/service-name/
├── container.yaml          # LXC container configuration
└── docker-compose.yml      # Service definition
```

## 🚀 Adding a New Service

### Step 1: Create Service Directory

```bash
# Create directory for your service
mkdir -p config/services/nextcloud
cd config/services/nextcloud
```

### Step 2: Container Configuration

Create `container.yaml`:

```yaml
---
container:
  id: 150                    # Unique container ID (100+)
  hostname: "nextcloud"      # Container hostname
  ip: "10.0.0.60"           # Container IP address
  
  resources:
    cpu: 2                   # CPU cores
    memory: 2048            # RAM in MB
    disk: 20                # Disk space in GB
    
  # Optional: NFS storage mounts
  nfs_mounts:
    - source: "/mnt/tank/nextcloud"
      target: "/data"
      
# Optional: SSL certificate domains
certificates:
  domains:
    - "nextcloud.yourdomain.com"
    
# Optional: External access configuration
external_access:
  cloudflare_tunnel:
    enabled: true
    subdomain: "nextcloud"
```

### Step 3: Docker Compose Configuration

Create `docker-compose.yml`:

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
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      
    volumes:
      - nextcloud-data:/var/www/html
      - /data/nextcloud:/var/www/html/data
      
    depends_on:
      - db
      
  db:
    image: mariadb:latest
    container_name: nextcloud-db
    restart: unless-stopped
    
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}  
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      
    volumes:
      - mysql-data:/var/lib/mysql

volumes:
  nextcloud-data:
  mysql-data:
```

### Step 4: Deploy the Service

```bash
# Add files to git
git add config/services/nextcloud/

# Commit and deploy
git commit -m "feat: add Nextcloud file sharing service"

# Deploy the new service
sudo ./scripts/deploy.sh --services-only

# Or for GitOps deployment:
git push origin main  # Automatically deploys via GitHub Actions
```

## 📋 Service Examples

### Simple Web Application

```yaml
# container.yaml
container:
  id: 151
  hostname: "uptime-kuma"
  ip: "10.0.0.61"
  resources:
    cpu: 1
    memory: 512
    disk: 5
```

```yaml
# docker-compose.yml
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

### Media Server with NFS Storage

```yaml
# container.yaml
container:
  id: 152
  hostname: "jellyfin"
  ip: "10.0.0.62"
  resources:
    cpu: 4
    memory: 4096
    disk: 10
  nfs_mounts:
    - source: "/mnt/tank/media"
      target: "/media"
```

```yaml
# docker-compose.yml
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
      - /media:/media:ro
    environment:
      - JELLYFIN_PublishedServerUrl=https://jellyfin.${DOMAIN}

volumes:
  jellyfin-config:
```

### Download Client with VPN

Services that need privacy (torrents, usenet) can route through the VPN gateway:

```yaml
# container.yaml
container:
  id: 153
  hostname: "qbittorrent"
  ip: "10.0.0.11"  # Download services use 10-19 range
  resources:
    cpu: 2
    memory: 1024
    disk: 10
  nfs_mounts:
    - source: "/mnt/tank/downloads"
      target: "/downloads"
```

```yaml
# docker-compose.yml
version: '3.8'
services:
  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    
    # Route through VPN gateway for privacy
    network_mode: "container:vpn-gateway"
    
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TZ:-UTC}
      - WEBUI_PORT=8080
      
    volumes:
      - qb-config:/config
      - /downloads:/downloads
      
    # Note: No ports section needed - uses VPN gateway ports
    
volumes:
  qb-config:
    
networks:
  # External network access through VPN container
  external:
    name: vpn-gateway_default
```

## 🔧 Service Management

### Update a Service

```bash
# Update docker-compose.yml
nano config/services/nextcloud/docker-compose.yml

# Deploy changes
sudo ./scripts/deploy.sh --services-only

# Or update specific service
sudo ./scripts/update-service.sh nextcloud
```

### Remove a Service

```bash
# Stop and remove containers
sudo ./scripts/remove-service.sh nextcloud

# Remove configuration
rm -rf config/services/nextcloud/

# Commit changes
git add -A
git commit -m "remove: Nextcloud service"
```

### Service Logs

```bash
# View service logs
sudo ./scripts/logs.sh nextcloud

# Follow logs in real-time
sudo ./scripts/logs.sh nextcloud --follow

# View specific container logs
pct exec 150 -- docker logs nextcloud
```

### Service Health

```bash
# Check all services
sudo ./scripts/health-check.sh

# Check specific service
sudo ./scripts/health-check.sh nextcloud

# View service status
pct exec 150 -- docker ps
```

## 📊 Service Configuration Reference

### Container Configuration Options

```yaml
container:
  id: 150                      # Required: Unique container ID
  hostname: "service-name"     # Required: Container hostname
  ip: "10.0.0.60"             # Required: Container IP address
  
  resources:                   # Optional: Resource allocation
    cpu: 2                     # CPU cores (default: 1)
    memory: 2048              # RAM in MB (default: 512)
    disk: 20                  # Disk space in GB (default: 8)
    
  features:                   # Optional: LXC features
    - "nesting=1"             # Enable Docker nesting
    - "keyctl=1"              # Enable keyctl
    
  nfs_mounts:                 # Optional: NFS storage mounts
    - source: "/path/on/nas"  # NFS server path
      target: "/path/in/container"  # Container mount point
      options: "rw,hard,intr" # Optional: Mount options
      
certificates:               # Optional: SSL certificates
  domains:
    - "service.yourdomain.com"
    
external_access:           # Optional: External access
  cloudflare_tunnel:
    enabled: true           # Enable Cloudflare tunnel
    subdomain: "service"    # Subdomain for external access
    
service:                    # Optional: Service metadata
  type: "media"             # Service category
  category: "entertainment" # Service category
  priority: 10              # Deployment priority (lower = earlier)
  
  health_check:             # Optional: Health check configuration
    enabled: true
    endpoint: "/health"     # Health check endpoint
    port: 80               # Health check port
    interval: 30           # Check interval in seconds
    
backup:                    # Optional: Backup configuration
  enabled: true
  paths:
    - "/config"            # Paths to backup
    - "/data"
  schedule: "daily"        # Backup schedule
```

### Docker Compose Best Practices

```yaml
version: '3.8'

services:
  app:
    image: app:latest
    container_name: app-name
    hostname: app.${DOMAIN:-homelab.local}
    restart: unless-stopped
    
    ports:
      - "80:80"            # Port mapping
      
    environment:
      # Use environment variables for secrets
      - DB_PASSWORD=${MYSQL_PASSWORD}
      - API_KEY=${API_KEY}
      - TZ=${TZ:-UTC}
      
    volumes:
      # Use named volumes for data
      - app-data:/data
      
      # Use bind mounts for configuration
      - ./config:/config:ro
      
      # Use NFS mounts for shared storage
      - /shared/media:/media:ro
      
    networks:
      - app-network
      
    # Resource limits
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
          
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      
    # Labels for management
    labels:
      - "com.homelab.service=app-name"
      - "com.homelab.category=productivity"

volumes:
  app-data:
    driver: local

networks:
  app-network:
    driver: bridge
```

## 🎯 IP Address Allocation

### Recommended IP Ranges

| Range | Purpose | Examples |
|-------|---------|----------|
| `10.0.0.10-19` | Download services | qBittorrent, SABnzbd |
| `10.0.0.20-29` | Development | GitLab, code-server |
| `10.0.0.30-39` | Utilities | Uptime Kuma, Portainer |
| `10.0.0.40-49` | Core infrastructure | Pi-hole, Nginx, Grafana |
| `10.0.0.50-59` | Home automation | Home Assistant, ESPHome |
| `10.0.0.60-69` | Productivity | Nextcloud, Vaultwarden |
| `10.0.0.70-79` | Media services | Jellyfin, Photoprism |
| `10.0.0.80-89` | Arr stack | Sonarr, Radarr, Prowlarr |
| `10.0.0.90-99` | Communication | Matrix, Discord bots |
| `10.0.0.100+` | Custom services | Your experimental services |

### Container ID Convention

Container IDs should match the last octet of the IP address + 100:
- IP `10.0.0.60` → Container ID `160`
- IP `10.0.0.75` → Container ID `175`

## 🔐 Security Best Practices

### Environment Variables

**❌ Never hardcode secrets:**
```yaml
environment:
  - MYSQL_PASSWORD=hardcoded123  # Bad!
```

**✅ Use environment variables:**
```yaml
environment:
  - MYSQL_PASSWORD=${MYSQL_PASSWORD}  # Good!
```

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

# Make filesystem read-only
read_only: true
tmpfs:
  - /tmp
  - /var/run

# Security options
security_opt:
  - no-new-privileges:true
```

### Network Security

```yaml
# Use custom networks
networks:
  - app-internal    # Internal-only network
  - homelab        # External access network

# Expose only necessary ports
ports:
  - "127.0.0.1:8080:80"  # Bind to localhost only
```

## 📦 Popular Service Examples

### Productivity Suite

- **[Nextcloud](../examples/nextcloud.md)** - File sharing and collaboration
- **[Vaultwarden](../examples/vaultwarden.md)** - Password manager
- **[Paperless-ngx](../examples/paperless.md)** - Document management
- **[Standard Notes](../examples/standard-notes.md)** - Note taking

### Media Stack

- **[Jellyfin](../examples/jellyfin.md)** - Media server
- **[Photoprism](../examples/photoprism.md)** - Photo management
- **[Immich](../examples/immich.md)** - Google Photos alternative
- **[Navidrome](../examples/navidrome.md)** - Music streaming

### Download Stack

- **[qBittorrent](../examples/qbittorrent.md)** - Torrent client with VPN
- **[SABnzbd](../examples/sabnzbd.md)** - Usenet client
- **[Prowlarr](../examples/prowlarr.md)** - Indexer manager
- **[Arr Stack](../examples/arr-stack.md)** - Sonarr, Radarr, etc.

### Home Automation

- **[Home Assistant](../examples/home-assistant.md)** - Home automation hub
- **[ESPHome](../examples/esphome.md)** - ESP device management
- **[Zigbee2MQTT](../examples/zigbee2mqtt.md)** - Zigbee bridge
- **[Node-RED](../examples/node-red.md)** - Flow-based automation

## 🔧 Troubleshooting Services

### Common Issues

**Service won't start:**
```bash
# Check container status
pct status 150

# Check Docker containers
pct exec 150 -- docker ps -a

# View service logs
pct exec 150 -- docker logs service-name

# Check resource usage
pct exec 150 -- docker stats
```

**Network connectivity issues:**
```bash
# Test container network
pct exec 150 -- ping 8.8.8.8

# Check port binding
pct exec 150 -- netstat -tlnp

# Test service endpoint
curl -I http://10.0.0.60:80
```

**Storage issues:**
```bash
# Check disk space
pct exec 150 -- df -h

# Check NFS mounts
pct exec 150 -- mount | grep nfs

# Test NFS connectivity
pct exec 150 -- ls -la /data
```

### Service Recovery

**Restart service:**
```bash
pct exec 150 -- docker compose restart
```

**Rebuild service:**
```bash
pct exec 150 -- docker compose down
pct exec 150 -- docker compose pull
pct exec 150 -- docker compose up -d
```

**Reset service data:**
```bash
# Stop service
pct exec 150 -- docker compose down

# Remove volumes (careful!)
pct exec 150 -- docker volume rm service_data

# Redeploy
pct exec 150 -- docker compose up -d
```

## 🚀 Advanced Service Features

### Service Dependencies

```yaml
# In cluster.yaml
services:
  deploy_order:
    - "pihole"        # DNS first
    - "nginx-proxy"   # Proxy second
    - "database"      # Database before apps
    - "nextcloud"     # App that needs database
```

### Service Monitoring

```yaml
# Enable monitoring for service
service:
  monitoring:
    enabled: true
    metrics_port: 9090
    dashboards:
      - "nextcloud-overview"
```

### Service Backups

```yaml
# Configure automatic backups
backup:
  enabled: true
  paths:
    - "/config"
    - "/data"
  schedule: "daily"
  retention: "7d"
```

---

📖 **[← Installation Guide](installation.md)** | **[Configuration Reference →](configuration.md)**