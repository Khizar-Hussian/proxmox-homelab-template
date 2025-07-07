# 📖 Complete Installation Guide

This guide provides step-by-step instructions for setting up the Proxmox Homelab Template from scratch.

## 📋 Prerequisites

### System Requirements

- **Proxmox VE 8.0+** running on dedicated hardware
- **Minimum 4GB RAM** (8GB+ recommended)
- **50GB+ available storage** for containers
- **Stable internet connection** for downloads
- **SSH access** to Proxmox host

### External Services

- **Domain name** from any registrar (Cloudflare DNS required)
- **Cloudflare account** for DNS management and tunnels
- **GitHub account** for repository and GitOps automation
- **NFS server** (optional) - TrueNAS, Synology, or any NFS share

### Network Requirements

- **Static IP** for Proxmox host
- **Port 22 (SSH)** accessible from your computer
- **Outbound internet** access from Proxmox host
- **No conflicting 10.0.0.0/24** subnet (containers will use this range)

## 🔧 Step 1: Proxmox Preparation

### 1.1 Update Proxmox

```bash
# SSH to your Proxmox host
ssh root@your-proxmox-ip

# Update system
apt update && apt upgrade -y

# Install required packages
apt install -y curl jq git
```

### 1.2 Create API Token

1. **Access Proxmox web interface**: `https://your-proxmox-ip:8006`
2. **Navigate**: Datacenter → Permissions → API Tokens
3. **Add token**: 
   - Token ID: `homelab`
   - User: `root@pam`
   - Privilege Separation: **Unchecked**
4. **Copy the token** - you'll need this for configuration

### 1.3 Download Container Template

```bash
# Update available templates
pveam update

# Download Ubuntu 22.04 template
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# Verify download
pveam list local
```

## 🌐 Step 2: External Services Setup

### 2.1 Cloudflare DNS Setup

1. **Transfer domain to Cloudflare DNS**:
   - Add domain to Cloudflare account
   - Update nameservers at your registrar
   - Wait for DNS propagation (up to 24 hours)

2. **Create API token**:
   - Go to **My Profile → API Tokens**
   - **Create Token** with:
     - Zone: `Zone:Read`, `DNS:Edit` for your domain
     - Account: `Account:Read`
   - **Copy the token**

3. **Create Cloudflare tunnel**:
   - Go to **Zero Trust → Access → Tunnels**
   - **Create tunnel** named `homelab-tunnel`
   - **Copy tunnel token**

### 2.2 GitHub Repository Setup

1. **Fork this repository**:
   - Go to the template repository
   - Click **Fork** → **Create fork**

2. **Clone your fork**:
   ```bash
   git clone https://github.com/yourusername/proxmox-homelab-template.git
   cd proxmox-homelab-template
   ```

3. **Set up GitHub Secrets** (Repository → Settings → Secrets → Actions):

   | Secret Name | Value | Description |
   |-------------|-------|-------------|
   | `PROXMOX_HOST` | `192.168.1.10` | Your Proxmox IP |
   | `PROXMOX_TOKEN` | `PVEAPIToken=root@pam!homelab=...` | From step 1.2 |
   | `CLOUDFLARE_API_TOKEN` | `...` | From step 2.1 |
   | `CLOUDFLARE_TUNNEL_TOKEN` | `...` | From step 2.1 |
   | `AUTHENTIK_ADMIN_PASSWORD` | `your-secure-password` | SSO admin password |

## ⚙️ Step 3: Configuration

### 3.1 Basic Configuration

```bash
# Copy configuration template
cp config/cluster.yaml.example config/cluster.yaml

# Edit with your settings
nano config/cluster.yaml
```

**Required changes**:
```yaml
cluster:
  domain: "yourdomain.com"              # Your actual domain
  admin_email: "admin@yourdomain.com"   # Your email

proxmox:
  host: "192.168.1.10"                  # Your Proxmox IP

networks:
  management:
    subnet: "192.168.1.0/24"            # Your home network
    gateway: "192.168.1.1"              # Your router IP
    
storage:
  nfs_server: "192.168.1.20"            # Your NFS server (if any)
```

### 3.2 Environment Variables

```bash
# Copy environment template
cp .env.example .env

# Edit with your credentials
nano .env
```

**Required variables**:
```bash
PROXMOX_HOST=192.168.1.10
PROXMOX_TOKEN=PVEAPIToken=root@pam!homelab=your-token-here
AUTHENTIK_ADMIN_PASSWORD=your-secure-password

# Optional but recommended
CLOUDFLARE_API_TOKEN=your-cloudflare-token
DISCORD_WEBHOOK=your-discord-webhook-url
EMAIL_RECIPIENT=admin@yourdomain.com
```

## 🚀 Step 4: Deployment

### 4.1 Prerequisites Check

```bash
# Verify system is ready
sudo ./scripts/helpers/prerequisites.sh

# Validate configuration
./scripts/helpers/validation.sh config/cluster.yaml
```

### 4.2 Dry Run (Recommended)

```bash
# See what will be deployed without making changes
sudo ./scripts/deploy.sh --dry-run --verbose

# Expected output:
# ✓ Network bridge creation
# ✓ 5 LXC containers 
# ✓ Docker installation
# ✓ Service deployment
```

### 4.3 Production Deployment

```bash
# Deploy everything (takes 5-10 minutes)
sudo ./scripts/deploy.sh --verbose

# Monitor progress in real-time
tail -f /var/log/homelab-deployment.log
```

### 4.4 Deployment Verification

```bash
# Check container status
pct list

# Expected output:
# VMID  Status  Name
# 140   running pihole
# 141   running nginx-proxy  
# 142   running monitoring
# 143   running authentik
# 144   running homepage

# Verify services are responding
./scripts/health-check.sh
```

## 🎯 Step 5: First Access

### 5.1 Service Access

After deployment, access your services:

| Service | URL | Purpose |
|---------|-----|---------|
| **Homepage** | `https://yourdomain.com` | Main dashboard |
| **Pi-hole** | `https://pihole.yourdomain.com/admin` | DNS management |
| **Nginx Proxy** | `https://proxy.yourdomain.com:81` | SSL certificate management |
| **Grafana** | `https://grafana.yourdomain.com` | Monitoring dashboards |
| **Authentik** | `https://auth.yourdomain.com` | User management |

### 5.2 Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| **Pi-hole** | `admin` | Check container logs or deployment output |
| **Nginx Proxy Manager** | `admin@example.com` | `changeme` |
| **Grafana** | `admin` | `admin` |
| **Authentik** | `admin@yourdomain.com` | Your `AUTHENTIK_ADMIN_PASSWORD` |

### 5.3 Initial Setup Tasks

1. **Change all default passwords** immediately
2. **Configure SSL certificates** in Nginx Proxy Manager
3. **Set up DNS records** for your services in Pi-hole
4. **Review monitoring dashboards** in Grafana
5. **Configure authentication** in Authentik

## 🔧 Step 6: Post-Deployment Configuration

### 6.1 SSL Certificates

1. **Access Nginx Proxy Manager**: `https://proxy.yourdomain.com:81`
2. **Add proxy hosts** for each service:
   - Domain: `pihole.yourdomain.com`
   - Forward to: `10.0.0.40:80`
   - Request SSL certificate
3. **Repeat for all services**

### 6.2 DNS Configuration

1. **Access Pi-hole**: `https://pihole.yourdomain.com/admin`
2. **Add local DNS records**:
   - `yourdomain.com` → `10.0.0.44` (Homepage)
   - `pihole.yourdomain.com` → `10.0.0.40`
   - `proxy.yourdomain.com` → `10.0.0.41`
   - `grafana.yourdomain.com` → `10.0.0.42`
   - `auth.yourdomain.com` → `10.0.0.43`

### 6.3 Monitoring Setup

1. **Access Grafana**: `https://grafana.yourdomain.com`
2. **Review pre-installed dashboards**:
   - Infrastructure Overview
   - Service Health
   - Network Monitoring
3. **Configure alert notifications** (Discord, email)

## 🔍 Troubleshooting

### Common Issues

**Container creation fails**:
```bash
# Check Proxmox storage
pvesm status

# Verify template exists
pveam list local

# Check available resources
free -h && df -h
```

**Network connectivity issues**:
```bash
# Verify bridge creation
ip addr show vmbr1

# Test container network
pct exec 140 -- ping 8.8.8.8

# Check firewall rules
iptables -L -n
```

**Service not responding**:
```bash
# Check container status
pct status 140

# View container logs
pct exec 140 -- docker logs pihole

# Restart service
pct exec 140 -- docker compose restart
```

For more troubleshooting help, see **[docs/troubleshooting.md](troubleshooting.md)**.

## 🎉 Next Steps

- **[Add your first service](services.md)** - Deploy Nextcloud, Jellyfin, etc.
- **[Configure external access](external-access.md)** - Set up remote access
- **[Set up backups](backup.md)** - Protect your configuration and data
- **[Join the community](../CONTRIBUTING.md)** - Share your experience and contribute

---

📖 **[← Back to README](../README.md)** | **[Configuration Guide →](configuration.md)**