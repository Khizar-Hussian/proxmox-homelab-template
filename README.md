# Proxmox Homelab Template

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Proxmox](https://img.shields.io/badge/Proxmox-VE%208.0+-orange)](https://www.proxmox.com/)
[![GitHub Workflow Status](https://github.com/Khizar-Hussian/proxmox-homelab-template/workflows/Deploy/badge.svg)](https://github.com/Khizar-Hussian/proxmox-homelab-template/actions)
[![GitHub stars](https://img.shields.io/github/stars/Khizar-Hussian/proxmox-homelab-template?style=social)](https://github.com/Khizar-Hussian/proxmox-homelab-template/stargazers)

> 🏠 **A production-ready homelab template for Proxmox with LXC containers, full TLS, and GitOps automation**

Deploy a complete homelab infrastructure on Proxmox with enterprise-grade reliability and security while maintaining the simplicity needed for home use. Get **6 core services** running automatically with **monitoring**, **authentication**, **VPN privacy**, and **automatic SSL certificates** configured out of the box.

## ✨ What You Get

- 🎯 **5-minute deployment** - From clone to running services with HTTPS
- 🔐 **Automatic SSL certificates** - Let's Encrypt wildcard certificates via Cloudflare DNS
- 🛡️ **VPN privacy gateway** - Route sensitive services through VPN
- 🚀 **GitOps automation** - Push code, infrastructure updates automatically
- 📊 **Complete monitoring** - Prometheus and Grafana with pre-built dashboards
- 🔒 **Single sign-on** - Authentik SSO protecting all services
- 🌐 **Beautiful dashboard** - Homepage showing service status and quick links
- 🐳 **Standard Docker Compose** - Use familiar tools, easy service addition

## 🏗️ Core Services (Auto-Deployed with HTTPS)

| Service | Purpose | Access | Default Credentials |
|---------|---------|---------|-------------------|
| **Homepage** | Service Dashboard | `https://yourdomain.com` | No auth required |
| **Pi-hole** | DNS + Ad-blocking | `https://pihole.yourdomain.com` | admin / [generated] |
| **VPN Gateway** | Privacy Tunnel | `http://10.0.0.39:8000` | Internal monitoring |
| **Nginx Proxy** | SSL + Reverse Proxy | `https://proxy.yourdomain.com` | admin@example.com / changeme |
| **Grafana** | Monitoring Dashboards | `https://grafana.yourdomain.com` | admin / admin |
| **Authentik** | Single Sign-On | `https://auth.yourdomain.com` | admin@yourdomain.com / [your password] |

> 🔒 **All services automatically get trusted SSL certificates** - no browser warnings, works on all devices!

## 🚀 Quick Start

### Prerequisites

- **Proxmox VE 8.0+** with internet access
- **Domain name** with Cloudflare DNS management  
- **4GB+ RAM** and **50GB+ storage** available
- **GitHub account** for GitOps automation

### 1. Clone and Configure

```bash
# Clone your fork of this repository
git clone https://github.com/yourusername/proxmox-homelab-template.git
cd proxmox-homelab-template

# Copy and customize configuration
cp config/cluster.yaml.example config/cluster.yaml
nano config/cluster.yaml  # Edit with your settings
```

### 2. Set Environment Variables

```bash
# Copy environment template
cp .env.example .env
nano .env  # Add your credentials
```

**Required variables:**
- `PROXMOX_HOST` - Your Proxmox server IP
- `PROXMOX_TOKEN` - Proxmox API token  
- `AUTHENTIK_ADMIN_PASSWORD` - Admin password for SSO
- `CLOUDFLARE_API_TOKEN` - For automatic SSL certificates

**Optional but recommended:**
- `NORDVPN_PRIVATE_KEY` - For VPN privacy (NordVPN WireGuard key)
- `VPN_PROVIDER` - VPN provider (nordvpn, surfshark, expressvpn)
- `VPN_COUNTRIES` - Preferred VPN server countries

### 3. Deploy Infrastructure

```bash
# Run deployment (takes 5-10 minutes)
sudo ./scripts/deploy.sh

# Or test first with dry run
sudo ./scripts/deploy.sh --dry-run
```

### 4. Access Your Services

After deployment completes, access your new homelab:

- **🏠 Homepage Dashboard**: `https://yourdomain.com` - Overview of all services
- **📊 Grafana Monitoring**: `https://grafana.yourdomain.com` - System metrics and dashboards  
- **🔐 Authentik SSO**: `https://auth.yourdomain.com` - Manage users and authentication

**Next steps**: Change default passwords, configure SSL certificates, add your own services.

📖 **[Complete installation guide →](docs/installation.md)**

## ⚙️ Essential Configuration

Edit `config/cluster.yaml` with your specific settings:

```yaml
cluster:
  domain: "yourdomain.com"           # Your domain name
  admin_email: "admin@yourdomain.com" # Your email address
  
proxmox:
  host: "192.168.1.10"              # Your Proxmox server IP
  
networks:
  management:
    subnet: "192.168.1.0/24"        # Your home network range
    gateway: "192.168.1.1"          # Your router IP
    
storage:
  nfs_server: "192.168.1.20"        # Your NFS server (optional)
```

📚 **[Complete configuration reference →](docs/configuration.md)**

## 🎯 Architecture Overview

```
┌─────────────────┐    ┌──────────────────────────────────────┐
│   Cloudflare    │    │            Proxmox Host              │
│   DNS + Tunnel  │────┤  ┌─────────────────────────────────┐ │
└─────────────────┘    │  │     Container Network           │ │
                       │  │        (vmbr1)                  │ │
┌─────────────────┐    │  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌────┐ │ │
│   VPN Provider  │────┤  │  │ VPN │ │Pi-  │ │Nginx│ │Graf│ │ │
│ (NordVPN/etc.)  │    │  │  │Gate-│ │hole │ │Proxy│ │ana │ │ │
└─────────────────┘    │  │  │way  │ └─────┘ └─────┘ └────┘ │ │
                       │  │  └─────┘ ┌─────┐ ┌─────┐       │ │
┌─────────────────┐    │  │          │Home │ │Auth │       │ │  
│      Home       │────┤  │          │page │ │entik│       │ │
│     Network     │    │  │          └─────┘ └─────┘       │ │
│    (vmbr0)      │    │  └─────────────────────────────────┘ │
└─────────────────┘    └──────────────────────────────────────┘
```

- **Network isolation** - Containers run on separate bridge (10.0.0.0/24)
- **VPN privacy** - Sensitive services routed through encrypted VPN tunnel
- **Automatic SSL** - Let's Encrypt wildcard certificates via Cloudflare DNS
- **External access** - Cloudflare tunnels for secure remote access
- **Monitoring integration** - All services monitored automatically

📖 **[Detailed architecture guide →](docs/architecture.md)**

## 📦 Adding Your Own Services

Add services by creating configurations in `config/services/`:

```bash
# Create service directory
mkdir config/services/nextcloud

# Define container and resources
cat > config/services/nextcloud/container.yaml << 'EOF'
container:
  id: 150
  ip: "10.0.0.60"
  hostname: "nextcloud"
  resources:
    cpu: 2
    memory: 2048
    disk: 20
EOF

# Standard Docker Compose
cat > config/services/nextcloud/docker-compose.yml << 'EOF'
version: '3.8'
services:
  nextcloud:
    image: nextcloud:latest
    # ... standard Docker Compose configuration
EOF

# Deploy the new service
git add config/services/nextcloud/
git commit -m "Add Nextcloud file sharing"
git push  # Automatically deploys via GitOps!
```

📖 **[Service management guide →](docs/services.md)**

## 🔧 Management Commands

```bash
# Health check all services
./scripts/health-check.sh

# View deployment status  
./scripts/helpers/deployment.sh report

# Update specific service
./scripts/deploy.sh --services-only

# Backup everything
./scripts/backup.sh

# View logs
./scripts/logs.sh [service-name]
```

## 🌟 Why This Template?

### vs. Manual Docker Setup
- ✅ **Infrastructure as Code** - Version controlled, reproducible deployments
- ✅ **Enterprise features** - Monitoring, SSL, authentication out of the box
- ✅ **Network isolation** - Proper segmentation and security
- ✅ **GitOps workflow** - Professional deployment practices

### vs. Kubernetes (like onedr0p/cluster-template)  
- ✅ **Simpler operations** - No Kubernetes complexity
- ✅ **Better isolation** - LXC containers vs shared kernel pods
- ✅ **Lower resources** - No control plane overhead
- ✅ **Familiar tools** - Docker Compose instead of Helm charts

### vs. Individual Install Scripts
- ✅ **Unified management** - One system for everything
- ✅ **Consistent configuration** - Standardized approach
- ✅ **Ongoing maintenance** - Updates and monitoring included
- ✅ **Service integration** - Everything works together

## 📚 Documentation

| Topic | Description |
|-------|-------------|
| **[Installation](docs/installation.md)** | Complete setup guide with prerequisites |
| **[Configuration](docs/configuration.md)** | All configuration options explained |
| **[Services](docs/services.md)** | Adding, updating, and managing services |
| **[Networking](docs/networking.md)** | Network configuration and troubleshooting |
| **[External Access](docs/external-access.md)** | Cloudflare, VPN, and remote access setup |
| **[Monitoring](docs/monitoring.md)** | Prometheus, Grafana, and alerting |
| **[Troubleshooting](docs/troubleshooting.md)** | Common issues and solutions |

## 🤝 Contributing

Contributions are welcome! This template is designed to be:

- **Community-driven** - Built by homelab enthusiasts for homelab enthusiasts
- **Educational** - Learn modern infrastructure practices
- **Extensible** - Easy to add new services and features

### Quick Contributing Guide
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-service`)
3. Add your service or improvement
4. Test on real Proxmox environment
5. Update documentation
6. Submit pull request

**[Complete contributing guide →](CONTRIBUTING.md)**

## 🙏 Acknowledgments

This template is inspired by and builds upon excellent work from:

- **[onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)** - Kubernetes homelab inspiration and GitOps practices
- **[tteck/Proxmox](https://github.com/tteck/Proxmox)** - Proxmox helper scripts and container expertise  
- **[linuxserver.io](https://www.linuxserver.io/)** - High-quality container images and documentation
- **The homelab community** - For sharing knowledge, best practices, and inspiration

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Khizar-Hussian/proxmox-homelab-template&type=Date)](https://star-history.com/#Khizar-Hussian/proxmox-homelab-template&Date)

---

<div align="center">

**[⭐ Star this repository](https://github.com/Khizar-Hussian/proxmox-homelab-template)** if you found it helpful!

Made with ❤️ for the homelab community

</div>