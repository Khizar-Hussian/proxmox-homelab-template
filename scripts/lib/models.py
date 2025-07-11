"""
Pydantic models for configuration management
"""
from pydantic import BaseModel, Field, validator
from typing import Optional, List, Dict, Any
import ipaddress
import os
from pathlib import Path


class NetworkConfig(BaseModel):
    """Network configuration settings"""
    management_subnet: str = Field(..., description="Management network subnet (e.g., 192.168.1.0/24)")
    management_gateway: str = Field(..., description="Management network gateway IP")
    management_bridge: str = Field(default="vmbr0", description="Management bridge name")
    container_subnet: str = Field(default="10.0.0.0/24", description="Container network subnet")
    container_gateway: str = Field(default="10.0.0.1", description="Container network gateway")
    container_bridge: str = Field(default="vmbr1", description="Container bridge name")

    @validator('management_subnet', 'container_subnet')
    def validate_subnet(cls, v):
        try:
            ipaddress.ip_network(v, strict=False)
        except ValueError:
            raise ValueError(f"Invalid subnet format: {v}")
        return v

    @validator('management_gateway', 'container_gateway')
    def validate_ip(cls, v):
        try:
            ipaddress.ip_address(v)
        except ValueError:
            raise ValueError(f"Invalid IP address: {v}")
        return v


class ClusterConfig(BaseModel):
    """Cluster configuration settings"""
    name: str = Field(default="homelab", description="Cluster name")
    domain: str = Field(..., description="Domain name")
    internal_domain: Optional[str] = Field(None, description="Internal domain (defaults to domain)")
    admin_email: str = Field(..., description="Administrator email")
    timezone: str = Field(default="America/New_York", description="Timezone")

    @validator('internal_domain', always=True)
    def set_internal_domain(cls, v, values):
        return v or values.get('domain')


class ProxmoxConfig(BaseModel):
    """Proxmox server configuration"""
    host: str = Field(..., description="Proxmox server IP address")
    api_port: int = Field(default=8006, description="Proxmox API port")
    token: str = Field(..., description="Proxmox API token")
    storage: str = Field(default="local-lvm", description="Default storage")
    template: str = Field(
        default="local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst",
        description="LXC template"
    )

    @validator('host')
    def validate_host(cls, v):
        try:
            ipaddress.ip_address(v)
        except ValueError:
            raise ValueError(f"Invalid Proxmox host IP: {v}")
        return v


class StorageConfig(BaseModel):
    """Storage configuration"""
    nfs_server: str = Field(..., description="NFS server IP address")
    media_path: str = Field(default="/mnt/tank/media", description="Media storage path")
    config_path: str = Field(default="/mnt/tank/config", description="Config storage path")
    backup_path: str = Field(default="/mnt/tank/backups", description="Backup storage path")

    @validator('nfs_server')
    def validate_nfs_server(cls, v):
        try:
            ipaddress.ip_address(v)
        except ValueError:
            raise ValueError(f"Invalid NFS server IP: {v}")
        return v


class VPNConfig(BaseModel):
    """VPN configuration"""
    enabled: bool = Field(default=True, description="Enable VPN")
    provider: str = Field(default="nordvpn", description="VPN provider")
    protocol: str = Field(default="openvpn", description="VPN protocol")
    countries: str = Field(default="United States,Canada,Netherlands", description="VPN countries")
    kill_switch: bool = Field(default=True, description="Enable kill switch")
    auto_reconnect: bool = Field(default=True, description="Auto reconnect")


class ExternalAccessConfig(BaseModel):
    """External access configuration"""
    cloudflare_enabled: bool = Field(default=True, description="Enable Cloudflare tunnel")
    tunnel_name: str = Field(default="homelab-tunnel", description="Cloudflare tunnel name")


class DefaultsConfig(BaseModel):
    """Default resource allocation"""
    cpu: int = Field(default=1, description="Default CPU cores")
    memory: int = Field(default=512, description="Default memory in MB")
    disk: int = Field(default=8, description="Default disk space in GB")


class SecretsConfig(BaseModel):
    """Secret configuration values"""
    proxmox_token: str = Field(..., description="Proxmox API token")
    cloudflare_api_token: str = Field(..., description="Cloudflare API token")
    cloudflare_tunnel_token: Optional[str] = Field(None, description="Cloudflare tunnel token")
    authentik_admin_password: str = Field(..., description="Authentik admin password")
    nordvpn_username: Optional[str] = Field(None, description="NordVPN username")
    nordvpn_password: Optional[str] = Field(None, description="NordVPN password")
    nordvpn_private_key: Optional[str] = Field(None, description="NordVPN private key")
    discord_webhook: Optional[str] = Field(None, description="Discord webhook URL")
    backup_encryption_key: Optional[str] = Field(None, description="Backup encryption key")


class Config(BaseModel):
    """Main configuration class"""
    cluster: ClusterConfig
    network: NetworkConfig
    proxmox: ProxmoxConfig
    storage: StorageConfig
    vpn: VPNConfig
    external_access: ExternalAccessConfig
    defaults: DefaultsConfig
    secrets: SecretsConfig

    @classmethod
    def from_env(cls, env_file: Optional[Path] = None) -> 'Config':
        """Load configuration from environment variables"""
        if env_file:
            from dotenv import load_dotenv
            load_dotenv(env_file)
        
        return cls(
            cluster=ClusterConfig(
                name=os.getenv('CLUSTER_NAME', 'homelab'),
                domain=os.getenv('DOMAIN'),
                internal_domain=os.getenv('INTERNAL_DOMAIN'),
                admin_email=os.getenv('ADMIN_EMAIL'),
                timezone=os.getenv('TIMEZONE', 'America/New_York')
            ),
            network=NetworkConfig(
                management_subnet=os.getenv('MANAGEMENT_SUBNET'),
                management_gateway=os.getenv('MANAGEMENT_GATEWAY'),
                management_bridge=os.getenv('MANAGEMENT_BRIDGE', 'vmbr0'),
                container_subnet=os.getenv('CONTAINER_SUBNET', '10.0.0.0/24'),
                container_gateway=os.getenv('CONTAINER_GATEWAY', '10.0.0.1'),
                container_bridge=os.getenv('CONTAINER_BRIDGE', 'vmbr1')
            ),
            proxmox=ProxmoxConfig(
                host=os.getenv('PROXMOX_HOST'),
                api_port=int(os.getenv('PROXMOX_API_PORT', '8006')),
                token=os.getenv('PROXMOX_TOKEN'),
                storage=os.getenv('PROXMOX_STORAGE', 'local-lvm'),
                template=os.getenv('PROXMOX_TEMPLATE', 'local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst')
            ),
            storage=StorageConfig(
                nfs_server=os.getenv('NFS_SERVER'),
                media_path=os.getenv('NFS_MEDIA_PATH', '/mnt/tank/media'),
                config_path=os.getenv('NFS_CONFIG_PATH', '/mnt/tank/config'),
                backup_path=os.getenv('NFS_BACKUP_PATH', '/mnt/tank/backups')
            ),
            vpn=VPNConfig(
                enabled=os.getenv('VPN_ENABLED', 'true').lower() == 'true',
                provider=os.getenv('VPN_PROVIDER', 'nordvpn'),
                protocol=os.getenv('VPN_PROTOCOL', 'openvpn'),
                countries=os.getenv('VPN_COUNTRIES', 'United States,Canada,Netherlands'),
                kill_switch=os.getenv('VPN_KILL_SWITCH', 'true').lower() == 'true',
                auto_reconnect=os.getenv('VPN_AUTO_RECONNECT', 'true').lower() == 'true'
            ),
            external_access=ExternalAccessConfig(
                cloudflare_enabled=os.getenv('CLOUDFLARE_ENABLED', 'true').lower() == 'true',
                tunnel_name=os.getenv('CLOUDFLARE_TUNNEL_NAME', 'homelab-tunnel')
            ),
            defaults=DefaultsConfig(
                cpu=int(os.getenv('DEFAULT_CPU', '1')),
                memory=int(os.getenv('DEFAULT_MEMORY', '512')),
                disk=int(os.getenv('DEFAULT_DISK', '8'))
            ),
            secrets=SecretsConfig(
                proxmox_token=os.getenv('PROXMOX_TOKEN'),
                cloudflare_api_token=os.getenv('CLOUDFLARE_API_TOKEN'),
                cloudflare_tunnel_token=os.getenv('CLOUDFLARE_TUNNEL_TOKEN'),
                authentik_admin_password=os.getenv('AUTHENTIK_ADMIN_PASSWORD'),
                nordvpn_username=os.getenv('NORDVPN_USERNAME'),
                nordvpn_password=os.getenv('NORDVPN_PASSWORD'),
                nordvpn_private_key=os.getenv('NORDVPN_PRIVATE_KEY'),
                discord_webhook=os.getenv('DISCORD_WEBHOOK'),
                backup_encryption_key=os.getenv('BACKUP_ENCRYPTION_KEY')
            )
        )

    def to_template_vars(self) -> Dict[str, Any]:
        """Convert config to template variables for Jinja2"""
        return {
            # Cluster
            'cluster_name': self.cluster.name,
            'domain': self.cluster.domain,
            'internal_domain': self.cluster.internal_domain,
            'admin_email': self.cluster.admin_email,
            'timezone': self.cluster.timezone,
            
            # Network
            'management_subnet': self.network.management_subnet,
            'management_gateway': self.network.management_gateway,
            'management_bridge': self.network.management_bridge,
            'container_subnet': self.network.container_subnet,
            'container_gateway': self.network.container_gateway,
            'container_bridge': self.network.container_bridge,
            
            # Proxmox
            'proxmox_host': self.proxmox.host,
            'proxmox_api_port': self.proxmox.api_port,
            'proxmox_storage': self.proxmox.storage,
            'proxmox_template': self.proxmox.template,
            
            # Storage
            'nfs_server': self.storage.nfs_server,
            'nfs_media_path': self.storage.media_path,
            'nfs_config_path': self.storage.config_path,
            'nfs_backup_path': self.storage.backup_path,
            
            # VPN
            'vpn_enabled': self.vpn.enabled,
            'vpn_provider': self.vpn.provider,
            'vpn_protocol': self.vpn.protocol,
            'vpn_countries': self.vpn.countries,
            
            # External Access
            'cloudflare_enabled': self.external_access.cloudflare_enabled,
            'cloudflare_tunnel_name': self.external_access.tunnel_name,
            
            # Defaults
            'default_cpu': self.defaults.cpu,
            'default_memory': self.defaults.memory,
            'default_disk': self.defaults.disk,
            
            # Secrets (for template use)
            'proxmox_token': self.secrets.proxmox_token,
            'cloudflare_api_token': self.secrets.cloudflare_api_token,
            'cloudflare_tunnel_token': self.secrets.cloudflare_tunnel_token,
            'authentik_admin_password': self.secrets.authentik_admin_password,
            'nordvpn_username': self.secrets.nordvpn_username,
            'nordvpn_password': self.secrets.nordvpn_password,
            'nordvpn_private_key': self.secrets.nordvpn_private_key,
            'discord_webhook': self.secrets.discord_webhook,
            'backup_encryption_key': self.secrets.backup_encryption_key
        }

    def print_summary(self):
        """Print configuration summary"""
        from rich.console import Console
        from rich.table import Table
        
        console = Console()
        
        table = Table(title="📋 Configuration Summary")
        table.add_column("Setting", style="cyan")
        table.add_column("Value", style="green")
        
        table.add_row("Domain", self.cluster.domain)
        table.add_row("Cluster", self.cluster.name)
        table.add_row("Admin Email", self.cluster.admin_email)
        table.add_row("Proxmox Host", self.proxmox.host)
        table.add_row("NFS Server", self.storage.nfs_server)
        table.add_row("Management Network", f"{self.network.management_subnet} (Gateway: {self.network.management_gateway})")
        table.add_row("Container Network", f"{self.network.container_subnet} (Gateway: {self.network.container_gateway})")
        
        console.print(table)
        
        # Optional features
        console.print("\n🔧 Optional Features:")
        console.print(f"  VPN: {'enabled' if self.vpn.enabled else 'disabled'}")
        console.print(f"  Cloudflare Tunnel: {'enabled' if self.external_access.cloudflare_enabled else 'disabled'}")
        console.print(f"  Monitoring: enabled")
        console.print(f"  Backups: enabled")