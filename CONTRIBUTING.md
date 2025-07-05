# Contributing to Proxmox Homelab Template

Thank you for your interest in contributing! This is a new project aimed at creating a production-ready homelab template using Proxmox LXC containers with Docker Compose and GitOps automation.

## 🚀 Project Status

**🏗️ This project is in early development.** We're actively building:
- Core infrastructure scripts
- Service templates and examples  
- Documentation and guides
- GitOps automation workflows

## 🤝 How to Contribute

### 🐛 Reporting Issues

Found a bug or have a suggestion? Please:

1. **Check existing issues** to avoid duplicates
2. **Use the issue templates** when available
3. **Provide clear details** about your environment and the problem

**Basic issue template:**
```markdown
**Environment:**
- Proxmox version: 
- OS: 
- Hardware: 

**Expected vs Actual Behavior:**
What you expected vs what happened

**Steps to Reproduce:**
1. Step one
2. Step two

**Logs:**
Include relevant error messages
```

### 💡 Feature Requests

We welcome ideas! Please describe:
- **The problem** you're trying to solve
- **Your proposed solution**
- **Why this would benefit** other homelab users

### 🔧 Contributing Code

#### Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork**:
   ```bash
   git clone https://github.com/yourusername/proxmox-homelab-template.git
   cd proxmox-homelab-template
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

#### Development Guidelines

**Shell Scripts:**
- Use `#!/bin/bash` with `set -euo pipefail`
- Include error handling and meaningful error messages
- Add comments for complex logic
- Use descriptive variable names

**YAML Files:**
- Use 2-space indentation
- Quote strings when needed
- Add comments to explain configuration sections

**Docker Compose Files:**
- Follow Docker Compose best practices
- Use environment variables for passwords (never hardcode)
- Include health checks when possible
- Document any special requirements

#### Testing

Since this is early development:
- **Test manually** on a Proxmox environment when possible
- **Validate YAML syntax** with `yq` or similar tools
- **Check shell script syntax** with `shellcheck` if available
- **Document any testing** you've done in your PR

#### Commit Messages

Use clear, descriptive commit messages:
```bash
feat: add Nextcloud service template
fix: resolve certificate generation issue  
docs: update installation instructions
```

## 📦 Adding New Services

Our goal is to make adding services as simple as creating two files:

### Service Structure
```
config/services/servicename/
├── container.yaml          # LXC container configuration
└── docker-compose.yml      # Standard Docker Compose file
```

### Example: Adding a New Service

**1. Container Configuration (`container.yaml`):**
```yaml
---
container:
  id: 130                    # Use next available ID
  hostname: "servicename"
  ip: "10.0.0.70"           # Use next available IP
  resources:
    cpu: 1
    memory: 512
    disk: 8
  nfs_mounts:
    - source: "/mnt/tank/servicename"
      target: "/data"
      
certificates:
  domains:
    - "servicename.yourdomain.com"
    
external_access:
  cloudflare_tunnel:
    enabled: true            # Set false for internal-only
```

**2. Docker Compose (`docker-compose.yml`):**
```yaml
version: '3.8'

services:
  servicename:
    image: servicename:latest
    container_name: servicename
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - /data:/app/data
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=${TZ:-America/New_York}
      # Use environment variables for passwords
      - ADMIN_PASSWORD=${ADMIN_PASSWORD}
```

### Service Categories

We're organizing services into:
- **📁 Productivity**: Nextcloud, Vaultwarden, Paperless-ngx
- **🎬 Media**: Jellyfin, Plex, Photoprism  
- **⬇️ Downloads**: qBittorrent, SABnzbd
- **📺 *arr Stack**: Sonarr, Radarr, Prowlarr, Lidarr
- **🏠 Home Automation**: Home Assistant, ESPHome
- **🔧 Utilities**: Uptime Kuma, Portainer
- **🔍 Monitoring**: Grafana, Prometheus

## 📚 Documentation

Help us improve documentation by:
- **Fixing errors** or unclear instructions
- **Adding examples** for common scenarios
- **Improving readability** and organization
- **Testing procedures** and reporting issues

## 🔍 Pull Request Process

1. **Create a descriptive PR title**
2. **Describe your changes** and why they're needed
3. **Test your changes** (document what testing you did)
4. **Be responsive** to feedback and questions

**Basic PR template:**
```markdown
## What This Changes
Brief description of your changes

## Why This Change
What problem does this solve?

## Testing Done
- [ ] Tested on Proxmox (describe setup)
- [ ] Validated YAML syntax
- [ ] Checked shell scripts
- [ ] Updated documentation

## Additional Notes
Anything else reviewers should know
```

## 🚧 Current Priorities

We're actively working on:

1. **Core Infrastructure**
   - Basic deployment scripts
   - Network and certificate setup
   - Monitoring foundation

2. **Service Templates**
   - Common homelab services
   - Secure configuration examples
   - Documentation for each service

3. **GitOps Integration**
   - GitHub Actions workflows
   - Automated deployment
   - Change detection

4. **Documentation**
   - Installation guide
   - Service management
   - Troubleshooting

## 🤔 Questions?

Since this is a new project:
- **Open an issue** for questions or suggestions
- **Start a discussion** for broader topics
- **Check the README** for current project status

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for helping build a better homelab template!** 🏠

Every contribution, no matter how small, helps make self-hosting more accessible for everyone.