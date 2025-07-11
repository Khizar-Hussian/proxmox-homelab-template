# 📖 Complete Installation Guide

This guide provides step-by-step instructions for setting up the modern Python-based Proxmox Homelab Template from scratch.

## 📋 Prerequisites

### System Requirements

- **Proxmox VE 8.0+** running on dedicated hardware
- **Minimum 8GB RAM** (16GB+ recommended for media services)
- **50GB+ available storage** for containers
- **Python 3.8+** installed on deployment machine
- **Stable internet connection** for downloads
- **SSH access** to Proxmox host

### External Services

- **Domain name** from any registrar (Cloudflare DNS required)
- **Cloudflare account** for DNS management and tunnels
- **NFS server** (required) - TrueNAS, Synology, or any NFS share
- **VPN provider** (optional) - NordVPN supported for privacy

### Network Requirements

- **Management network** - Your existing home network (e.g., 192.168.1.0/24)
- **Container network** - Automatically created isolated network (10.0.0.0/24)
- **Internet access** from Proxmox host for container downloads

## 🚀 Step 1: Proxmox Preparation

### 1.1 Create API Token

1. Login to Proxmox web interface at `https://your-proxmox-ip:8006`
2. Navigate to **Datacenter → Permissions → API Tokens**
3. Click **Add** to create a new token:
   - **User**: `root@pam`
   - **Token ID**: `homelab-deploy`
   - **Privilege Separation**: Unchecked (full privileges)
4. **Copy the generated token** - you'll need this for `.env` configuration

### 1.2 Download LXC Templates

```bash
# SSH to Proxmox host and download Ubuntu template
ssh root@your-proxmox-ip

# Download the Ubuntu 24.04 LXC template
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst

# Verify template downloaded
pveam list local
```

### 1.3 Verify Storage Configuration

```bash
# Check available storage pools
pvesm status

# Ensure you have at least 50GB available
df -h /var/lib/vz
```

## 🌐 Step 2: Network Planning

### 2.1 Document Your Current Network

Identify your current network configuration:

```bash
# Find your home network details
ip route | grep default
ip addr show

# Example outputs to note:
# Management network: 192.168.1.0/24
# Gateway: 192.168.1.1
# Proxmox IP: 192.168.1.100
```

### 2.2 Plan IP Allocations

The system will create this network architecture:

```
Management Network (Your existing network)
├── Proxmox Host: 192.168.1.100
├── NFS Server: 192.168.1.200
└── Your devices: 192.168.1.2-50

Container Network (Automatically created)
├── Core Services: 10.0.0.40-49
├── Media Services: 10.0.0.10-19
└── User Services: 10.0.0.70+
```

## ☁️ Step 3: Cloudflare Setup

### 3.1 Configure DNS

1. **Transfer domain to Cloudflare DNS** (if not already):
   - Add your domain to Cloudflare
   - Update nameservers at your registrar
   - Verify DNS is active

2. **Create API Token**:
   - Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
   - Click **Create Token**
   - Use **Edit zone DNS** template
   - **Zone Resources**: Include your domain
   - **Copy the generated token**

### 3.2 Create Cloudflare Tunnel (Optional)

For external access to your services:

1. Go to **Zero Trust → Access → Tunnels**
2. Click **Create a tunnel**
3. Choose **Cloudflared**
4. Name your tunnel: `homelab-tunnel`
5. **Copy the tunnel token** for `.env` configuration

## 💾 Step 4: NFS Server Setup

### 4.1 Configure NFS Exports

On your NFS server (TrueNAS, Synology, etc.), create these directories:

```bash
# Required directory structure
/mnt/tank/config     # Service configurations
/mnt/tank/media      # Media files (optional)
/mnt/tank/backups    # Backup storage
```

### 4.2 Configure NFS Exports

Example `/etc/exports` configuration:

```bash
# Allow access from your management network
/mnt/tank/config    192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/mnt/tank/media     192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
/mnt/tank/backups   192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
```

### 4.3 Test NFS Access

```bash
# From Proxmox host, test NFS connectivity
showmount -e 192.168.1.200
mount -t nfs 192.168.1.200:/mnt/tank/config /tmp/test
ls /tmp/test
umount /tmp/test
```

## 🐍 Step 5: Python Environment Setup

### 5.1 Clone Repository

```bash
# Clone to your deployment machine (can be your laptop)
git clone https://github.com/Khizar-Hussian/proxmox-homelab-template.git
cd proxmox-homelab-template
```

### 5.2 Install Dependencies

```bash
# Install Python dependencies
pip install -r requirements.txt

# Or use virtual environment (recommended)
python -m venv venv
source venv/bin/activate  # Linux/Mac
# or
venv\Scripts\activate     # Windows
pip install -r requirements.txt
```

### 5.3 Verify Installation

```bash
# Test the CLI
python scripts/deploy.py --help

# You should see the help output with available commands
```

## ⚙️ Step 6: Configuration

### 6.1 Create Environment File

```bash
# Copy the example configuration
cp .env.example .env
```

### 6.2 Configure Required Settings

Edit `.env` with your specific values:

```bash
# Domain and Admin
DOMAIN=yourdomain.com
ADMIN_EMAIL=admin@yourdomain.com

# Network Configuration
PROXMOX_HOST=192.168.1.100
MANAGEMENT_SUBNET=192.168.1.0/24
MANAGEMENT_GATEWAY=192.168.1.1

# Storage
NFS_SERVER=192.168.1.200

# API Tokens (from previous steps)
PROXMOX_TOKEN=root@pam!homelab-deploy=your-proxmox-token-here
CLOUDFLARE_API_TOKEN=your-cloudflare-api-token-here

# Passwords
AUTHENTIK_ADMIN_PASSWORD=your-strong-password-here
```

### 6.3 Configure Optional Settings

```bash
# External Access (optional)
CLOUDFLARE_TUNNEL_TOKEN=your-tunnel-token-here

# VPN Privacy (optional)
NORDVPN_PRIVATE_KEY=your-nordvpn-wireguard-key
# or
NORDVPN_USERNAME=your-nordvpn-username
NORDVPN_PASSWORD=your-nordvpn-password

# Notifications (optional)
DISCORD_WEBHOOK=https://discord.com/api/webhooks/your-webhook-url
```

## ✅ Step 7: Validation and Deployment

### 7.1 Validate Configuration

```bash
# Run comprehensive validation
python scripts/deploy.py validate-only

# This will check:
# - Network configuration
# - Proxmox connectivity
# - NFS server access
# - Required secrets
# - Service discovery
```

### 7.2 List Discovered Services

```bash
# See what services will be deployed
python scripts/deploy.py list-services --details
```

### 7.3 Test Deployment (Dry Run)

```bash
# See what would be deployed without making changes
python scripts/deploy.py deploy --dry-run
```

### 7.4 Deploy Infrastructure

```bash
# Deploy all auto-deploy services
python scripts/deploy.py deploy

# Or deploy specific services
python scripts/deploy.py deploy --services pihole,nginx-proxy
```

## 🎯 Step 8: Post-Deployment Configuration

### 8.1 Access Your Services

After successful deployment, access your services:

- **Homepage**: `https://yourdomain.com`
- **Pi-hole**: `https://pihole.yourdomain.com/admin`
- **Nginx Proxy Manager**: `https://proxy.yourdomain.com:81`
- **Grafana**: `https://grafana.yourdomain.com`
- **Authentik**: `https://auth.yourdomain.com`

### 8.2 Change Default Passwords

1. **Nginx Proxy Manager**:
   - Login: `admin@example.com` / `changeme`
   - Change password in admin interface

2. **Grafana**:
   - Login: `admin` / `admin`
   - Change password on first login

3. **Pi-hole**:
   - Password auto-generated, check container logs

### 8.3 Configure SSL Certificates

1. Login to **Nginx Proxy Manager**
2. Go to **SSL Certificates**
3. Add **Let's Encrypt Certificate**:
   - Domain: `*.yourdomain.com`
   - Email: Your admin email
   - DNS Provider: Cloudflare
   - API Token: Your Cloudflare token

### 8.4 Set Up Proxy Hosts

Create proxy hosts for each service:
- **Homepage**: `yourdomain.com` → `10.0.0.44:3000`
- **Pi-hole**: `pihole.yourdomain.com` → `10.0.0.41:80`
- **Grafana**: `grafana.yourdomain.com` → `10.0.0.45:3000`

## 🔧 Step 9: Adding Custom Services

### 9.1 Create Service Directory

```bash
# Example: Adding Sonarr
mkdir config/services/sonarr
```

### 9.2 Configure Service Files

Create the three required files:

```bash
# Service metadata
cat > config/services/sonarr/service.json << 'EOF'
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
EOF

# Container configuration
cat > config/services/sonarr/container.json << 'EOF'
{
  "container_id": 110,
  "hostname": "sonarr",
  "ip_address": "10.0.0.10",
  "cpu_cores": 2,
  "memory_mb": 2048,
  "disk_gb": 20
}
EOF

# Docker Compose configuration
cat > config/services/sonarr/docker-compose.yaml << 'EOF'
version: '3.8'
services:
  sonarr:
    image: linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
    volumes:
      - /opt/appdata/sonarr:/config
      - /mnt/media:/media
    ports:
      - "8989:8989"
    restart: unless-stopped
EOF
```

### 9.3 Deploy New Service

```bash
# Deploy the new service
python scripts/deploy.py deploy --services sonarr
```

## 🔍 Troubleshooting

### Common Issues

1. **Validation Failures**:
   ```bash
   # Check specific error messages
   python scripts/deploy.py validate-only
   ```

2. **Network Connectivity**:
   ```bash
   # Test Proxmox API
   curl -k https://192.168.1.100:8006/api2/json/version
   
   # Test NFS server
   ping 192.168.1.200
   showmount -e 192.168.1.200
   ```

3. **Service Discovery Issues**:
   ```bash
   # Check service file structure
   python scripts/deploy.py list-services --details
   ```

4. **Container Issues**:
   ```bash
   # Check container status on Proxmox
   pct list
   pct status 100
   ```

### Getting Help

1. **Review validation output** for specific error messages
2. **Check prerequisites** are met
3. **Verify network connectivity** between components
4. **Create GitHub issue** with error details if needed

## 🎉 Next Steps

- **[Service Management Guide](services.md)** - Adding and managing services
- **[Configuration Reference](configuration.md)** - All configuration options
- **[CLI Reference](cli-reference.md)** - Complete command documentation
- **[Troubleshooting Guide](troubleshooting.md)** - Common issues and solutions

---

**Congratulations!** Your modern Python-based Proxmox homelab is now ready to use! 🎉