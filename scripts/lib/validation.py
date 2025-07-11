"""
Validation system for configuration and infrastructure
"""
import json
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import ipaddress
import requests
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

from .models import Config
from .service_discovery import ServiceDiscovery

console = Console()


class ValidationError(Exception):
    """Custom exception for validation errors"""
    pass


class ConfigValidator:
    """Validates configuration settings"""
    
    def __init__(self, config: Config):
        self.config = config
        self.errors: List[str] = []
        self.warnings: List[str] = []
    
    def validate_all(self) -> bool:
        """Run all validation checks"""
        console.print("🔍 Running configuration validation...", style="blue")
        
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            
            # Network validation
            task = progress.add_task("Validating network configuration...", total=None)
            self._validate_network()
            progress.update(task, description="✅ Network validation complete")
            
            # Proxmox validation
            task = progress.add_task("Validating Proxmox connectivity...", total=None)
            self._validate_proxmox_connectivity()
            progress.update(task, description="✅ Proxmox validation complete")
            
            # Storage validation
            task = progress.add_task("Validating storage configuration...", total=None)
            self._validate_storage()
            progress.update(task, description="✅ Storage validation complete")
            
            # Required secrets validation
            task = progress.add_task("Validating required secrets...", total=None)
            self._validate_required_secrets()
            progress.update(task, description="✅ Secrets validation complete")
            
            # VPN validation (if enabled)
            if self.config.vpn.enabled:
                task = progress.add_task("Validating VPN configuration...", total=None)
                self._validate_vpn()
                progress.update(task, description="✅ VPN validation complete")
            
            # External access validation (if enabled)
            if self.config.external_access.cloudflare_enabled:
                task = progress.add_task("Validating external access...", total=None)
                self._validate_external_access()
                progress.update(task, description="✅ External access validation complete")
        
        # Report results
        if self.warnings:
            console.print("\n⚠️  Warnings:", style="yellow")
            for warning in self.warnings:
                console.print(f"  • {warning}", style="yellow")
        
        if self.errors:
            console.print("\n❌ Validation Errors:", style="red")
            for error in self.errors:
                console.print(f"  • {error}", style="red")
            return False
        
        console.print("\n✅ All validations passed!", style="green")
        return True
    
    def _validate_network(self) -> None:
        """Validate network configuration"""
        try:
            # Validate management network
            mgmt_network = ipaddress.ip_network(self.config.network.management_subnet, strict=False)
            mgmt_gateway = ipaddress.ip_address(self.config.network.management_gateway)
            
            # Check if gateway is in management network
            if mgmt_gateway not in mgmt_network:
                self.errors.append(
                    f"Management gateway {mgmt_gateway} is not in management subnet {mgmt_network}"
                )
            
            # Validate container network
            container_network = ipaddress.ip_network(self.config.network.container_subnet, strict=False)
            container_gateway = ipaddress.ip_address(self.config.network.container_gateway)
            
            # Check if gateway is in container network
            if container_gateway not in container_network:
                self.errors.append(
                    f"Container gateway {container_gateway} is not in container subnet {container_network}"
                )
            
            # Check for network overlap
            if mgmt_network.overlaps(container_network):
                self.errors.append(
                    f"Management network {mgmt_network} overlaps with container network {container_network}"
                )
            
            # Validate Proxmox and NFS IPs are in management network
            proxmox_ip = ipaddress.ip_address(self.config.proxmox.host)
            nfs_ip = ipaddress.ip_address(self.config.storage.nfs_server)
            
            if proxmox_ip not in mgmt_network:
                self.errors.append(
                    f"Proxmox host {proxmox_ip} is not in management network {mgmt_network}"
                )
            
            if nfs_ip not in mgmt_network:
                self.errors.append(
                    f"NFS server {nfs_ip} is not in management network {mgmt_network}"
                )
                
        except ValueError as e:
            self.errors.append(f"Network configuration error: {e}")
    
    def _validate_proxmox_connectivity(self) -> None:
        """Validate Proxmox server connectivity and API access"""
        try:
            # Basic connectivity check
            response = requests.get(
                f"https://{self.config.proxmox.host}:{self.config.proxmox.api_port}/api2/json/version",
                verify=False,
                timeout=10
            )
            
            if response.status_code == 200:
                version_info = response.json()
                console.print(
                    f"✅ Connected to Proxmox VE {version_info['data']['version']}", 
                    style="green"
                )
            else:
                self.errors.append(f"Failed to connect to Proxmox API: HTTP {response.status_code}")
                
        except requests.exceptions.RequestException as e:
            self.errors.append(f"Proxmox connectivity error: {e}")
    
    def _validate_storage(self) -> None:
        """Validate storage configuration"""
        # For now, just validate that NFS server IP is reachable
        try:
            # Simple ping test
            result = subprocess.run(
                ["ping", "-c", "1", "-W", "5", self.config.storage.nfs_server],
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                self.warnings.append(f"NFS server {self.config.storage.nfs_server} is not reachable")
            
        except Exception as e:
            self.warnings.append(f"Could not test NFS connectivity: {e}")
    
    def _validate_required_secrets(self) -> None:
        """Validate that all required secrets are present"""
        required_secrets = [
            ('proxmox_token', 'Proxmox API token'),
            ('cloudflare_api_token', 'Cloudflare API token'),
            ('authentik_admin_password', 'Authentik admin password')
        ]
        
        for secret_attr, description in required_secrets:
            if not getattr(self.config.secrets, secret_attr):
                self.errors.append(f"Missing required secret: {description}")
    
    def _validate_vpn(self) -> None:
        """Validate VPN configuration"""
        if not self.config.vpn.enabled:
            return
        
        # Check VPN credentials based on protocol
        if self.config.vpn.protocol == "openvpn":
            if not self.config.secrets.nordvpn_username or not self.config.secrets.nordvpn_password:
                self.errors.append("OpenVPN requires nordvpn_username and nordvpn_password")
        elif self.config.vpn.protocol == "wireguard":
            if not self.config.secrets.nordvpn_private_key:
                self.errors.append("WireGuard requires nordvpn_private_key")
        else:
            self.errors.append(f"Unsupported VPN protocol: {self.config.vpn.protocol}")
    
    def _validate_external_access(self) -> None:
        """Validate external access configuration"""
        if not self.config.external_access.cloudflare_enabled:
            return
        
        # Check if tunnel token is provided
        if not self.config.secrets.cloudflare_tunnel_token:
            self.warnings.append("Cloudflare tunnel enabled but no tunnel token provided")


class ServiceValidator:
    """Validates service configurations"""
    
    def __init__(self, service_discovery: ServiceDiscovery):
        self.service_discovery = service_discovery
        self.errors: List[str] = []
        self.warnings: List[str] = []
    
    def validate_all_services(self) -> bool:
        """Validate all discovered services"""
        console.print("🔧 Validating service configurations...", style="blue")
        
        service_infos = self.service_discovery.get_all_service_info()
        
        if not service_infos:
            console.print("No services found to validate", style="yellow")
            return True
        
        for service_info in service_infos:
            self._validate_service(service_info.name)
        
        # Report results
        if self.warnings:
            console.print("\n⚠️  Service Warnings:", style="yellow")
            for warning in self.warnings:
                console.print(f"  • {warning}", style="yellow")
        
        if self.errors:
            console.print("\n❌ Service Validation Errors:", style="red")
            for error in self.errors:
                console.print(f"  • {error}", style="red")
            return False
        
        console.print("✅ All service configurations are valid", style="green")
        return True
    
    def _validate_service(self, service_name: str) -> None:
        """Validate a single service"""
        service_files = self.service_discovery.get_service_files(service_name)
        
        # Validate JSON files
        for file_type, file_path in service_files.items():
            if file_type in ["container", "service"]:
                self._validate_json_file(file_path, service_name, file_type)
        
        # Validate docker-compose file (if it exists)
        if "compose" in service_files:
            self._validate_docker_compose(service_files["compose"], service_name)
    
    def _validate_json_file(self, file_path: Path, service_name: str, file_type: str) -> None:
        """Validate JSON file syntax"""
        try:
            with open(file_path, 'r') as f:
                json.load(f)
        except json.JSONDecodeError as e:
            self.errors.append(f"Invalid JSON in {service_name}/{file_type}.json: {e}")
        except FileNotFoundError:
            self.errors.append(f"Missing {file_type}.json for service {service_name}")
    
    def _validate_docker_compose(self, file_path: Path, service_name: str) -> None:
        """Validate docker-compose file syntax"""
        if not file_path.exists():
            self.errors.append(f"Missing docker-compose file for service {service_name}")
            return
            
        try:
            import yaml
            with open(file_path, 'r') as f:
                yaml.safe_load(f)
        except yaml.YAMLError as e:
            self.errors.append(f"Invalid YAML in {service_name}/{file_path.name}: {e}")
        except Exception as e:
            self.errors.append(f"Error reading {service_name}/{file_path.name}: {e}")


class SystemValidator:
    """Validates system prerequisites"""
    
    def __init__(self):
        self.errors: List[str] = []
        self.warnings: List[str] = []
    
    def validate_prerequisites(self) -> bool:
        """Validate system prerequisites"""
        console.print("🔧 Checking system prerequisites...", style="blue")
        
        # Check required commands (only those needed on deployment host)
        required_commands = [
            "curl",
            "ping"
        ]
        
        # Optional but recommended commands
        optional_commands = [
            "jq"
        ]
        
        for command in required_commands:
            if not self._check_command(command):
                self.errors.append(f"Required command not found: {command}")
        
        # Check optional commands
        for command in optional_commands:
            if not self._check_command(command):
                self.warnings.append(f"Optional command not found: {command} (recommended for troubleshooting)")
        
        # Check Python version
        import sys
        if sys.version_info < (3, 8):
            self.errors.append(f"Python 3.8+ required, found {sys.version}")
        
        # Check permissions (if running as root)
        import os
        if os.geteuid() != 0:
            self.warnings.append("Not running as root - some operations may fail")
        
        # Report results
        if self.warnings:
            console.print("\n⚠️  System Warnings:", style="yellow")
            for warning in self.warnings:
                console.print(f"  • {warning}", style="yellow")
        
        if self.errors:
            console.print("\n❌ System Validation Errors:", style="red")
            for error in self.errors:
                console.print(f"  • {error}", style="red")
            return False
        
        console.print("✅ All system prerequisites satisfied", style="green")
        return True
    
    def _check_command(self, command: str) -> bool:
        """Check if a command is available"""
        try:
            subprocess.run(
                ["which", command], 
                capture_output=True, 
                check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False


class ComprehensiveValidator:
    """Comprehensive validation orchestrator"""
    
    def __init__(self, config: Config):
        self.config = config
        self.service_discovery = ServiceDiscovery()
        
        self.config_validator = ConfigValidator(config)
        self.service_validator = ServiceValidator(self.service_discovery)
        self.system_validator = SystemValidator()
    
    def validate_all(self) -> bool:
        """Run all validation checks"""
        console.print("🔍 Running comprehensive validation...", style="bold blue")
        console.print("=" * 80, style="dim")
        
        # System prerequisites
        if not self.system_validator.validate_prerequisites():
            return False
        
        print()  # Spacing
        
        # Configuration validation
        if not self.config_validator.validate_all():
            return False
        
        print()  # Spacing
        
        # Service validation
        if not self.service_validator.validate_all_services():
            return False
        
        console.print("=" * 80, style="dim")
        console.print("✅ All validations passed successfully!", style="bold green")
        
        return True