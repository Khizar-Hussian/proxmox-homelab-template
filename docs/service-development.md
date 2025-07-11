# 🛠️ Service Development Guide

Complete guide for developing and contributing services to the homelab template.

## 🎯 Overview

This guide covers how to create, test, and contribute new services to the homelab template using the modern Python-based service discovery system.

## 📋 Service Requirements

Every service must have **three configuration files**:

1. **`container.json`** - LXC container configuration
2. **`service.json`** - Service metadata and dependencies  
3. **`docker-compose.yaml`** - Docker service definition

## 🏗️ Service Structure

```
config/services/service-name/
├── container.json           # LXC container settings
├── service.json            # Service metadata
├── docker-compose.yaml     # Docker Compose configuration
├── README.md              # Optional: Service documentation
└── examples/              # Optional: Example configurations
    ├── basic.env
    └── advanced.env
```

## 📝 Configuration Files

### container.json

Defines the LXC container that will host your service:

```json
{
  "container_id": 150,
  "hostname": "service-name",
  "ip_address": "10.0.0.60",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20,
  "features": [
    "nesting=1",
    "keyctl=1"
  ],
  "mounts": [
    {
      "source": "/mnt/media",
      "target": "/media",
      "readonly": true
    }
  ]
}
```

**Required fields:**
- `container_id` - Unique container ID (100+)
- `hostname` - Container hostname
- `ip_address` - Container IP in 10.0.0.0/24 range

**Optional fields:**
- `cpu_cores` - CPU cores (default: 1)
- `memory_mb` - RAM in MB (default: 512)
- `disk_gb` - Disk space in GB (default: 8)
- `features` - LXC features (nesting required for Docker)
- `mounts` - Additional host mounts

### service.json

Defines service metadata and behavior:

```json
{
  "_description": "Service Name Service Metadata",
  "_format_version": "2.0.0",
  
  "service": {
    "name": "service-name",
    "display_name": "Service Display Name",
    "description": "Brief description of what this service does",
    "category": "productivity",
    "subcategory": "collaboration",
    "version": "latest",
    "maintainer": "Service Maintainer",
    "documentation": "https://service-docs.example.com",
    "icon": "service-icon.png",
    "tags": ["tag1", "tag2", "tag3"]
  },
  
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["authentik", "vpn-gateway"],
    "conflicts": [],
    "_note": "Description of dependencies"
  },
  
  "external_access": {
    "enabled": true,
    "subdomain": "service",
    "public": false,
    "authentication_required": true,
    "description": "External access description"
  },
  
  "monitoring": {
    "enabled": true,
    "metrics_available": true,
    "dashboards": [
      {
        "name": "service-overview",
        "description": "Main service dashboard"
      }
    ],
    "alerts": [
      {
        "name": "service_down",
        "description": "Service is not responding"
      }
    ]
  },
  
  "backup": {
    "enabled": true,
    "critical": false,
    "description": "What gets backed up",
    "restore_priority": "medium"
  },
  
  "security": {
    "network_access": "internal",
    "data_sensitivity": "medium",
    "compliance_notes": "Any compliance considerations"
  }
}
```

**Required fields:**
- `service.name` - Service name (must match directory name)
- `service.description` - Brief description
- `service.category` - Service category

**Common categories:**
- `infrastructure` - Core services
- `media` - Media servers and tools
- `productivity` - Office and collaboration
- `security` - Authentication and VPN
- `monitoring` - Metrics and dashboards
- `automation` - Home automation
- `development` - Development tools

### docker-compose.yaml

Standard Docker Compose configuration with Jinja2 templates:

```yaml
version: '3.8'

services:
  service-name:
    image: service/image:latest
    container_name: service-name
    hostname: service-name.{{ domain }}
    restart: unless-stopped
    
    ports:
      - "80:80"
      - "443:443"
      
    environment:
      # Use template variables for configuration
      - DOMAIN={{ domain }}
      - ADMIN_EMAIL={{ admin_email }}
      - DATABASE_URL=postgres://{{ postgres_user }}:{{ postgres_password }}@db:5432/{{ postgres_db }}
      - REDIS_URL=redis://redis:6379/{{ redis_db | default('0') }}
      - TZ={{ timezone | default('UTC') }}
      
      # Service-specific environment variables
      - SERVICE_CONFIG={{ service_config | default('default') }}
      - API_KEY={{ api_key }}
      
    volumes:
      # Use named volumes for service data
      - service-data:/data
      
      # Use host paths for configuration
      - /opt/appdata/service-name:/config
      
      # Use NFS mounts for shared storage
      - /mnt/media:/media:ro
      
    depends_on:
      - db
      - redis
      
    networks:
      - service-network
      
    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
      
    # Resource limits
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 512M
          
    # Labels for service management
    labels:
      - "homelab.service=service-name"
      - "homelab.category=productivity"
      - "homelab.url=https://service.{{ domain }}"
      - "homelab.description=Service description"

  # Supporting services (database, cache, etc.)
  db:
    image: postgres:15
    container_name: service-name-db
    restart: unless-stopped
    
    environment:
      - POSTGRES_DB={{ postgres_db }}
      - POSTGRES_USER={{ postgres_user }}
      - POSTGRES_PASSWORD={{ postgres_password }}
      
    volumes:
      - db-data:/var/lib/postgresql/data
      
    networks:
      - service-network
      
    # Don't expose database ports externally
    # ports: []

  redis:
    image: redis:7-alpine
    container_name: service-name-redis
    restart: unless-stopped
    
    volumes:
      - redis-data:/data
      
    networks:
      - service-network

volumes:
  service-data:
    driver: local
  db-data:
    driver: local
  redis-data:
    driver: local

networks:
  service-network:
    driver: bridge
```

## 🎨 Template Variables

Services can use **Jinja2 template variables** in their docker-compose.yaml:

### System Variables

```yaml
# Domain and admin
- DOMAIN={{ domain }}
- ADMIN_EMAIL={{ admin_email }}

# Network configuration
- MANAGEMENT_SUBNET={{ management_subnet }}
- CONTAINER_SUBNET={{ container_subnet }}

# Timezone
- TZ={{ timezone | default('UTC') }}
```

### Service Variables

```yaml
# Database configuration
- DATABASE_URL=postgres://{{ postgres_user }}:{{ postgres_password }}@db:5432/{{ postgres_db }}
- MYSQL_ROOT_PASSWORD={{ mysql_root_password }}
- MYSQL_DATABASE={{ mysql_database }}

# Redis configuration
- REDIS_URL=redis://redis:6379/{{ redis_db | default('0') }}

# API keys and tokens
- API_KEY={{ api_key }}
- WEBHOOK_URL={{ webhook_url }}
```

### Conditional Configuration

```yaml
# Optional features
{% if backup_enabled %}
- BACKUP_ENABLED=true
- BACKUP_SCHEDULE={{ backup_schedule | default('daily') }}
{% endif %}

# VPN routing for download services
{% if vpn_enabled %}
network_mode: "container:vpn-gateway"
{% else %}
ports:
  - "8080:8080"
{% endif %}
```

## 📊 Service Categories and IP Allocation

### IP Address Ranges

| Range | Category | Purpose |
|-------|----------|---------|
| `10.0.0.10-19` | media | Download services |
| `10.0.0.20-29` | development | Development tools |
| `10.0.0.30-39` | utility | Utility services |
| `10.0.0.40-49` | infrastructure | Core infrastructure |
| `10.0.0.50-59` | automation | Home automation |
| `10.0.0.60-69` | productivity | Productivity tools |
| `10.0.0.70-79` | media | Media servers |
| `10.0.0.80-89` | media | Arr stack |
| `10.0.0.90-99` | communication | Communication tools |
| `10.0.0.100+` | custom | Custom services |

### Container ID Convention

- Use unique container IDs starting from 100
- Core services: 100-119
- User services: 120+
- **Do not** base container ID on IP address

## 🔧 Development Workflow

### 1. Create Service Directory

```bash
# Create service directory
mkdir config/services/my-service
cd config/services/my-service
```

### 2. Create Configuration Files

Create all three required files:

```bash
# Create container configuration
cat > container.json << 'EOF'
{
  "container_id": 150,
  "hostname": "my-service",
  "ip_address": "10.0.0.60",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20
}
EOF

# Create service metadata
cat > service.json << 'EOF'
{
  "service": {
    "name": "my-service",
    "description": "My custom service",
    "category": "productivity"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": []
  }
}
EOF

# Create docker-compose configuration
cat > docker-compose.yaml << 'EOF'
version: '3.8'
services:
  my-service:
    image: my-service:latest
    container_name: my-service
    restart: unless-stopped
    ports:
      - "80:80"
    environment:
      - DOMAIN={{ domain }}
    volumes:
      - my-service-data:/data
volumes:
  my-service-data:
EOF
```

### 3. Validate Configuration

```bash
# Check if service is discovered
python scripts/deploy.py list-services | grep my-service

# Validate configuration
python scripts/deploy.py validate-only

# Check detailed service info
python scripts/deploy.py list-services --details
```

### 4. Test Deployment

```bash
# Test deployment without making changes
python scripts/deploy.py deploy --services my-service --dry-run

# Deploy the service
python scripts/deploy.py deploy --services my-service
```

### 5. Test Service

```bash
# Check container status
pct status 150

# Check service logs
pct exec 150 -- docker logs my-service

# Test service endpoint
curl -I http://10.0.0.60
```

## 🧪 Testing and Validation

### Service Discovery Testing

```bash
# List all services
python scripts/deploy.py list-services

# Check service details
python scripts/deploy.py list-services --details

# Validate service configuration
python scripts/deploy.py validate-only
```

### Configuration Testing

```bash
# Test JSON syntax
jq . config/services/my-service/container.json
jq . config/services/my-service/service.json

# Test YAML syntax
python -c "import yaml; yaml.safe_load(open('config/services/my-service/docker-compose.yaml'))"
```

### Deployment Testing

```bash
# Dry run deployment
python scripts/deploy.py deploy --services my-service --dry-run

# Deploy to test environment
python scripts/deploy.py deploy --services my-service

# Check deployment status
pct status 150
pct exec 150 -- docker ps
```

## 📋 Best Practices

### Service Design

1. **Single responsibility** - Each service should have a clear, single purpose
2. **Minimal dependencies** - Only depend on services you actually need
3. **Proper categorization** - Use appropriate category for IP allocation
4. **Resource limits** - Set reasonable CPU and memory limits
5. **Health checks** - Include health check endpoints when possible

### Configuration Management

1. **Use templates** - Leverage Jinja2 for dynamic configuration
2. **Environment variables** - Use environment variables for all configuration
3. **Secure secrets** - Never hardcode passwords or API keys
4. **Validation** - Test all configuration files before deployment
5. **Documentation** - Include README.md with service-specific instructions

### Container Security

1. **Non-root user** - Run services as non-root when possible
2. **Read-only mounts** - Use read-only mounts for shared storage
3. **Minimal privileges** - Only grant necessary container capabilities
4. **Resource limits** - Set memory and CPU limits
5. **Network isolation** - Use appropriate network configuration

### Storage Management

1. **Named volumes** - Use named volumes for service data
2. **Host paths** - Use host paths for configuration files
3. **NFS mounts** - Use NFS for shared media storage
4. **Backup strategy** - Consider what needs to be backed up
5. **Cleanup** - Remove unused volumes and containers

## 🔍 Troubleshooting

### Service Not Discovered

```bash
# Check directory structure
ls -la config/services/my-service/
# Should show: container.json, service.json, docker-compose.yaml

# Check file syntax
python scripts/deploy.py validate-only
```

### Validation Errors

```bash
# Check JSON syntax
jq . config/services/my-service/container.json
jq . config/services/my-service/service.json

# Check YAML syntax
python -c "import yaml; yaml.safe_load(open('config/services/my-service/docker-compose.yaml'))"
```

### Deployment Issues

```bash
# Check container creation
pct status 150
pct config 150

# Check Docker service
pct exec 150 -- docker ps -a
pct exec 150 -- docker logs my-service
```

### Network Issues

```bash
# Test container connectivity
pct exec 150 -- ping 8.8.8.8
pct exec 150 -- ping 10.0.0.41  # Pi-hole

# Test service endpoint
curl -I http://10.0.0.60
telnet 10.0.0.60 80
```

## 📚 Service Examples

### Simple Web Application

```json
// container.json
{
  "container_id": 151,
  "hostname": "uptime-kuma",
  "ip_address": "10.0.0.30",
  "cpu_cores": 1,
  "memory_mb": 512,
  "disk_gb": 5
}
```

```json
// service.json
{
  "service": {
    "name": "uptime-kuma",
    "description": "Uptime monitoring tool",
    "category": "utility"
  },
  "dependencies": {
    "required": ["pihole"],
    "optional": ["nginx-proxy"]
  }
}
```

```yaml
# docker-compose.yaml
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

### Database-Backed Service

```json
// container.json
{
  "container_id": 152,
  "hostname": "nextcloud",
  "ip_address": "10.0.0.60",
  "cpu_cores": 2,
  "memory_mb": 4096,
  "disk_gb": 20
}
```

```json
// service.json
{
  "service": {
    "name": "nextcloud",
    "description": "File sharing and collaboration",
    "category": "productivity"
  },
  "dependencies": {
    "required": ["pihole", "nginx-proxy"],
    "optional": ["authentik"]
  }
}
```

```yaml
# docker-compose.yaml
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
      - NEXTCLOUD_ADMIN_USER={{ admin_user | default('admin') }}
      - NEXTCLOUD_ADMIN_PASSWORD={{ admin_password }}
      - TRUSTED_DOMAINS={{ domain }}
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
      - db-data:/var/lib/mysql
      
volumes:
  nextcloud-data:
  db-data:
```

## 🤝 Contributing Services

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
git clone https://github.com/yourusername/proxmox-homelab-template.git
cd proxmox-homelab-template
```

### 2. Create Feature Branch

```bash
git checkout -b feature/add-service-name
```

### 3. Develop Service

Follow the development workflow above to create your service.

### 4. Test Thoroughly

```bash
# Validate configuration
python scripts/deploy.py validate-only

# Test deployment
python scripts/deploy.py deploy --services your-service --dry-run

# Test actual deployment
python scripts/deploy.py deploy --services your-service
```

### 5. Document Service

Create a README.md in your service directory:

```markdown
# Service Name

Brief description of what the service does.

## Configuration

### Required Environment Variables

- `VARIABLE_NAME` - Description of variable

### Optional Environment Variables

- `OPTIONAL_VAR` - Description with default value

## Usage

How to use the service after deployment.

## Troubleshooting

Common issues and solutions.
```

### 6. Submit Pull Request

```bash
# Commit changes
git add config/services/your-service/
git commit -m "feat: add your-service integration"

# Push to your fork
git push origin feature/add-service-name
```

Create a pull request with:
- Clear description of the service
- Testing instructions
- Screenshots if applicable
- Documentation updates

## 📋 Service Template

Use this template for new services:

```bash
# Create service from template
mkdir config/services/template-service
cd config/services/template-service

# Copy template files
cp ../../../templates/service/* .

# Edit files with your service details
nano container.json
nano service.json
nano docker-compose.yaml
```

---

📖 **[← CLI Reference](cli-reference.md)** | **[Services Guide →](services.md)**