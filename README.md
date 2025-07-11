# 🏠 Proxmox Homelab Template

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Proxmox VE](https://img.shields.io/badge/proxmox-8.0+-orange.svg)](https://www.proxmox.com/en/proxmox-ve)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![GitHub stars](https://img.shields.io/github/stars/Khizar-Hussian/proxmox-homelab-template?style=social)](https://github.com/Khizar-Hussian/proxmox-homelab-template/stargazers)

> 🏠 **A modern Python-based homelab template for Proxmox with LXC containers, network segmentation, and robust configuration management**

Deploy a complete homelab infrastructure on Proxmox with enterprise-grade reliability and security while maintaining the simplicity needed for home use. Get **6 core services** running automatically with **monitoring**, **authentication**, **VPN privacy**, **network isolation**, and **automatic SSL certificates** configured out of the box.

## ✨ What You Get

- 🎯 **Modern Python CLI** - Beautiful terminal UI with automatic service discovery
- 🛡️ **Network segmentation** - Isolated container network for enhanced security
- 🔐 **Type-safe configuration** - Pydantic validation prevents configuration errors  
- 🎨 **Jinja2 templates** - Reliable template processing (no more bash variable issues)
- 🚀 **Automatic service discovery** - Add services by creating directories
- 📊 **Complete monitoring** - Prometheus and Grafana with pre-built dashboards
- 🔒 **Single sign-on** - Authentik SSO protecting all services
- 🌐 **Beautiful dashboard** - Homepage showing service status and quick links
- 🐳 **Standard Docker Compose** - Use familiar tools, easy service addition

## 🏗️ Core Services (Auto-Deployed with HTTPS)

| Service | Purpose | Access | Default Credentials |
|---------|---------|---------|-------------------|
| **Homepage** | Service Dashboard | `https://yourdomain.com` | No auth required |
| **Pi-hole** | DNS + Ad-blocking | `https://pihole.yourdomain.com` | admin / [generated] |
| **VPN Gateway** | Privacy Tunnel | `http://10.0.0.42:8000` | Internal monitoring |
| **Nginx Proxy** | SSL + Reverse Proxy | `https://proxy.yourdomain.com` | admin@example.com / changeme |
| **Grafana** | Monitoring Dashboards | `https://grafana.yourdomain.com` | admin / admin |
| **Authentik** | Single Sign-On | `https://auth.yourdomain.com` | admin@yourdomain.com / [your password] |

> 🔒 **All services automatically get trusted SSL certificates** - no browser warnings, works on all devices!

## 🛡️ Network Segmentation Architecture

### **Two Isolated Networks for Enhanced Security**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Management Network (vmbr0)                  │
│                      192.168.1.0/24                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │
│  │ Proxmox     │  │ NFS Server  │  │ Your        │           │
│  │ Host        │  │ (TrueNAS)   │  │ Devices     │           │
│  │ .100        │  │ .200        │  │ .2-.50      │           │
│  └─────────────┘  └─────────────┘  └─────────────┘           │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │  Bridge & Firewall │
                    └─────────┬─────────┘
                              │
┌─────────────────────────────────────────────────────────────────┐
│                   Container Network (vmbr1)                    │
│                        10.0.0.0/24                            │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │            Core Services (10.0.0.40-49)                │  │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐      │  │
│  │  │Pi-  │ │VPN  │ │Nginx│ │Home │ │Moni-│ │Auth │      │  │
│  │  │hole │ │Gate │ │Proxy│ │page │ │tor  │ │entik│      │  │
│  │  │ .41 │ │ .42 │ │ .43 │ │ .44 │ │ .45 │ │ .46 │      │  │
│  │  └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │           Media Services (10.0.0.10-19)                │  │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐                      │  │
│  │  │Sonarr│ │Radarr│ │Prowl│ │qBit │                     │  │
│  │  │ .10 │ │ .11 │ │ .12 │ │ .13 │                      │  │
│  │  └─────┘ └─────┘ └─────┘ └─────┘                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │          User Services (10.0.0.70+)                    │  │
│  │  ┌─────┐ ┌─────┐ ┌─────┐                              │  │
│  │  │Next │ │Bitwa│ │Your │                              │  │
│  │  │cloud│ │rden │ │Apps │                              │  │
│  │  │ .70 │ │ .71 │ │ .72+│                              │  │
│  │  └─────┘ └─────┘ └─────┘                              │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### **Security Benefits**
- ✅ **Network isolation** - Services can't directly access your home network devices
- ✅ **Controlled routing** - All traffic flows through defined bridges with firewall rules
- ✅ **VPN privacy** - Download services automatically routed through VPN gateway
- ✅ **DNS security** - All container DNS queries filtered through Pi-hole
- ✅ **Intrusion prevention** - Compromised service can't lateral move to home network
- ✅ **Traffic monitoring** - All inter-network traffic is logged and controlled

### **Automatic Network Setup**
The deployment automatically creates:
- **Container bridge (vmbr1)** with proper IP allocation
- **Firewall rules** allowing necessary traffic (DNS, web access, monitoring)
- **NAT/masquerading** for container internet access
- **Pi-hole DNS** resolution for the container network
- **VPN routing** for privacy-sensitive services

## 🚀 Quick Start

### Prerequisites

- **Proxmox VE 8.0+** with internet access
- **Domain name** with Cloudflare DNS management  
- **8GB+ RAM** and **50GB+ storage** available
- **Python 3.8+** installed
- **NFS server** (TrueNAS, Synology, etc.) for persistent storage

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/Khizar-Hussian/proxmox-homelab-template.git
cd proxmox-homelab-template

# Install Python dependencies
pip install -r requirements.txt

# Copy configuration template
cp .env.example .env
```

### 2. Configure Your Environment

Edit the `.env` file with your settings:

**Required network configuration:**
```bash
# Your existing home network
MANAGEMENT_SUBNET=192.168.1.0/24
MANAGEMENT_GATEWAY=192.168.1.1

# Automatically created isolated container network
CONTAINER_SUBNET=10.0.0.0/24
CONTAINER_GATEWAY=10.0.0.1
```

**Required service configuration:**
- `DOMAIN` - Your domain name (managed by Cloudflare)
- `ADMIN_EMAIL` - Admin email for certificates and notifications
- `PROXMOX_HOST` - Your Proxmox server IP (e.g., 192.168.1.100)
- `PROXMOX_TOKEN` - Proxmox API token  
- `AUTHENTIK_ADMIN_PASSWORD` - Admin password for SSO
- `CLOUDFLARE_API_TOKEN` - For automatic SSL certificates
- `NFS_SERVER` - Your NFS server IP (e.g., 192.168.1.200)

**Optional but recommended:**
- `CLOUDFLARE_TUNNEL_TOKEN` - For external access to services
- `NORDVPN_PRIVATE_KEY` - For VPN privacy (NordVPN WireGuard key)
- `DISCORD_WEBHOOK` - For deployment notifications

### 3. Validate Configuration

```bash
# Validate your configuration with the new Python system
python scripts/deploy.py validate-only
```

The new Python-based configuration system provides:
- **Network validation** - Ensures proper IP allocation and no conflicts
- **Type safety** - Pydantic models prevent configuration errors
- **Automatic discovery** - Dynamic service detection from directories
- **Beautiful output** - Rich terminal UI with progress bars

### 4. Deploy Infrastructure

```bash
# List discovered services
python scripts/deploy.py list-services --details

# Run deployment (takes 5-10 minutes)
python scripts/deploy.py deploy

# Or test first with dry run
python scripts/deploy.py deploy --dry-run

# Deploy specific services only
python scripts/deploy.py deploy --services pihole,nginx-proxy
```

### 5. Access Your Services

After deployment completes, access your new homelab:

- **🏠 Homepage Dashboard**: `https://yourdomain.com` - Overview of all services
- **📊 Grafana Monitoring**: `https://grafana.yourdomain.com` - System metrics and dashboards  
- **🔐 Authentik SSO**: `https://auth.yourdomain.com` - Manage users and authentication

**Next steps**: Change default passwords, configure SSL certificates, add your own services.

## 📦 Adding Your Own Services

The new Python system makes adding services incredibly easy. Just create a directory with the required files:

```bash
# Create service directory
mkdir config/services/sonarr

# Service metadata (JSON)
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

# Container configuration (JSON) - automatically gets IP in media range
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

# Standard Docker Compose (YAML)
cat > config/services/sonarr/docker-compose.yaml << 'EOF'
version: '3.8'
services:
  sonarr:
    image: linuxserver/sonarr:latest
    # ... standard Docker Compose configuration
EOF

# Deploy the new service - it's automatically discovered!
python scripts/deploy.py deploy --services sonarr
```

**Automatic service discovery** - No need to modify any central configuration files!

## 🔧 Management Commands

```bash
# List all discovered services
python scripts/deploy.py list-services --details

# Validate configuration and network setup
python scripts/deploy.py validate-only

# Deploy all auto-deploy services
python scripts/deploy.py deploy

# Deploy specific services
python scripts/deploy.py deploy --services pihole,nginx-proxy

# Dry run (show what would be deployed)
python scripts/deploy.py deploy --dry-run

# Coming soon: service status and management
python scripts/deploy.py status
python scripts/deploy.py logs pihole --follow
python scripts/deploy.py remove old-service
```

## 🌟 Why This Template?

### vs. Manual Docker Setup
- ✅ **Infrastructure as Code** - Version controlled, reproducible deployments
- ✅ **Type-safe configuration** - Pydantic validation prevents errors
- ✅ **Network segmentation** - Enterprise-level security isolation
- ✅ **Automatic discovery** - Services discovered from directories
- ✅ **Enterprise features** - Monitoring, SSL, authentication out of the box

### vs. Bash Scripts  
- ✅ **Reliable templates** - Jinja2 instead of error-prone envsubst
- ✅ **Clear error messages** - Python stack traces vs cryptic bash failures
- ✅ **Rich terminal UI** - Beautiful progress bars and tables
- ✅ **Type safety** - Configuration validated before deployment

### vs. Kubernetes (like onedr0p/cluster-template)  
- ✅ **Simpler operations** - No Kubernetes complexity
- ✅ **Better isolation** - LXC containers + network segmentation vs shared kernel pods
- ✅ **Lower resources** - No control plane overhead
- ✅ **Familiar tools** - Docker Compose instead of Helm charts

### vs. Docker on Single Host
- ✅ **True isolation** - LXC containers vs shared Docker daemon
- ✅ **Network segmentation** - Isolated networks vs Docker bridge
- ✅ **Resource control** - Per-container resource limits
- ✅ **Security** - Container escape protection

## 📚 Documentation

| Topic | Description |
|-------|-------------|
| **[Installation](docs/installation.md)** | Complete setup guide with prerequisites |
| **[Configuration](docs/configuration.md)** | All configuration options explained |
| **[Network Architecture](docs/networking.md)** | Network segmentation and security details |
| **[Services](docs/services.md)** | Adding, updating, and managing services |
| **[Python CLI Reference](docs/cli-reference.md)** | Complete CLI command documentation |
| **[Service Development](docs/service-development.md)** | Creating custom services |
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

Special thanks to the maintainers of the Python libraries that make this possible:
- **[Pydantic](https://pydantic.dev/)** - Data validation and settings management
- **[Typer](https://typer.tiangolo.com/)** - Building great CLIs
- **[Rich](https://rich.readthedocs.io/)** - Beautiful terminal output
- **[Jinja2](https://jinja.palletsprojects.com/)** - Modern template engine

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=Khizar-Hussian/proxmox-homelab-template&type=Date)](https://star-history.com/#Khizar-Hussian/proxmox-homelab-template&Date)

---

<div align="center">

**[⭐ Star this repository](https://github.com/Khizar-Hussian/proxmox-homelab-template)** if you found it helpful!

Made with ❤️ for the homelab community

</div>