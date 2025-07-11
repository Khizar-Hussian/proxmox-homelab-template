"""
Template processing system using Jinja2 for configuration files
"""
import json
from pathlib import Path
from typing import Dict, Any, Optional
from jinja2 import Environment, FileSystemLoader, Template
from rich.console import Console

from .models import Config

console = Console()


class TemplateProcessor:
    """Processes Jinja2 templates with configuration data"""
    
    def __init__(self, config: Config, template_dir: Optional[Path] = None):
        self.config = config
        self.template_dir = template_dir or Path("config")
        
        # Create Jinja2 environment
        self.env = Environment(
            loader=FileSystemLoader(str(self.template_dir)),
            trim_blocks=True,
            lstrip_blocks=True,
            keep_trailing_newline=True
        )
        
        # Add custom filters
        self.env.filters['default'] = self._default_filter
    
    def process_template(self, template_path: Path) -> str:
        """Process a template file with configuration data"""
        try:
            # Load template content
            with open(template_path, 'r') as f:
                template_content = f.read()
            
            template = Template(template_content)
            
            # Prepare template variables from config
            template_vars = self._get_template_vars()
            
            return template.render(template_vars)
            
        except Exception as e:
            console.print(f"❌ Error processing template {template_path}: {e}", style="red")
            raise
    
    def _get_template_vars(self) -> Dict[str, Any]:
        """Get template variables from configuration"""
        return {
            'domain': self.config.cluster.domain,
            'admin_email': self.config.cluster.admin_email,
            'timezone': self.config.cluster.timezone,
            'management_subnet': self.config.network.management_subnet,
            'container_subnet': self.config.network.container_subnet,
            'container_gateway': self.config.network.container_gateway,
            'nfs_server': self.config.storage.nfs_server,
            'cloudflare_api_token': self.config.secrets.cloudflare_api_token,
            'authentik_admin_password': self.config.secrets.authentik_admin_password,
            'mysql_root_password': self.config.secrets.mysql_root_password or 'defaultroot123',
            'mysql_database': 'homelab',
            'mysql_user': 'homelab',
            'mysql_password': self.config.secrets.mysql_password or 'defaultuser123',
            'redis_password': self.config.secrets.redis_password or 'defaultredis123',
            'vpn_enabled': self.config.vpn.enabled,
            'nordvpn_private_key': self.config.secrets.nordvpn_private_key,
            'nordvpn_username': self.config.secrets.nordvpn_username,
            'nordvpn_password': self.config.secrets.nordvpn_password,
            'discord_webhook': self.config.secrets.discord_webhook,
        }
    
    def _default_filter(self, value: Any, default_value: Any = '') -> Any:
        """Custom default filter that handles None and empty strings"""
        if value is None or value == '':
            return default_value
        return value
    
    def process_cluster_config(self, config: Config) -> Dict[str, Any]:
        """Process cluster configuration template"""
        template_path = self.template_dir / "cluster.json.j2"
        
        if not template_path.exists():
            # Fall back to original cluster.json if template doesn't exist
            original_path = self.template_dir / "cluster.json"
            if original_path.exists():
                console.print(f"⚠️  Using original cluster.json (template not found)", style="yellow")
                with open(original_path, 'r') as f:
                    return json.load(f)
            else:
                raise FileNotFoundError(f"Neither {template_path} nor {original_path} found")
        
        try:
            # Load and render template
            template = self.env.get_template("cluster.json.j2")
            rendered_json = template.render(config.to_template_vars())
            
            # Parse and return as dictionary
            return json.loads(rendered_json)
            
        except Exception as e:
            console.print(f"❌ Error processing cluster template: {e}", style="red")
            raise
    
    def process_service_template(self, service_name: str, template_name: str, config: Config) -> str:
        """Process a service template (container.json, docker-compose.yml, etc.)"""
        template_path = f"services/{service_name}/{template_name}"
        
        try:
            template = self.env.get_template(template_path)
            
            # Create service-specific template variables
            template_vars = config.to_template_vars()
            template_vars.update({
                'service_name': service_name,
                'service_hostname': f"{service_name}.{config.cluster.domain}",
                'service_ip': self._get_service_ip(service_name, config),
            })
            
            return template.render(template_vars)
            
        except Exception as e:
            console.print(f"❌ Error processing service template {template_path}: {e}", style="red")
            raise
    
    def _get_service_ip(self, service_name: str, config: Config) -> str:
        """Get IP address for a service based on naming convention"""
        # Simple IP allocation based on service name
        # This is a basic implementation - could be made more sophisticated
        
        service_ips = {
            'pihole': '10.0.0.41',
            'vpn-gateway': '10.0.0.42',
            'nginx-proxy': '10.0.0.43',
            'homepage': '10.0.0.44',
            'monitoring': '10.0.0.45',
            'authentik': '10.0.0.46',
            'sonarr': '10.0.0.10',
            'radarr': '10.0.0.11',
            'prowlarr': '10.0.0.12',
            'qbittorrent': '10.0.0.13',
        }
        
        return service_ips.get(service_name, '10.0.0.100')  # Default IP
    
    def process_file_template(self, template_path: Path, config: Config, extra_vars: Optional[Dict[str, Any]] = None) -> str:
        """Process any template file with configuration data"""
        try:
            # Load template
            with open(template_path, 'r') as f:
                template_content = f.read()
            
            template = Template(template_content)
            
            # Prepare template variables
            template_vars = config.to_template_vars()
            if extra_vars:
                template_vars.update(extra_vars)
            
            return template.render(template_vars)
            
        except Exception as e:
            console.print(f"❌ Error processing template {template_path}: {e}", style="red")
            raise
    
    def validate_template(self, template_path: Path) -> bool:
        """Validate that a template file has valid Jinja2 syntax"""
        try:
            with open(template_path, 'r') as f:
                template_content = f.read()
            
            # Try to parse the template
            Template(template_content)
            return True
            
        except Exception as e:
            console.print(f"❌ Invalid template syntax in {template_path}: {e}", style="red")
            return False
    
    def list_templates(self) -> Dict[str, list]:
        """List all available templates"""
        templates = {
            'cluster': [],
            'services': {}
        }
        
        # Check for cluster templates
        cluster_template = self.template_dir / "cluster.json.j2"
        if cluster_template.exists():
            templates['cluster'].append('cluster.json.j2')
        
        # Check for service templates
        services_dir = self.template_dir / "services"
        if services_dir.exists():
            for service_dir in services_dir.iterdir():
                if service_dir.is_dir():
                    service_templates = []
                    for template_file in service_dir.glob("*.j2"):
                        service_templates.append(template_file.name)
                    
                    if service_templates:
                        templates['services'][service_dir.name] = service_templates
        
        return templates


class ServiceTemplateProcessor:
    """Specialized processor for service templates"""
    
    def __init__(self, services_dir: Path):
        self.services_dir = services_dir
    
    def process_service_files(self, service_name: str, config: Config) -> Dict[str, Any]:
        """Process all template files for a service"""
        service_dir = self.services_dir / service_name
        
        if not service_dir.exists():
            raise FileNotFoundError(f"Service directory not found: {service_dir}")
        
        processor = TemplateProcessor(service_dir.parent.parent)
        
        # Process each template file
        processed_files = {}
        
        # Container configuration
        container_template = service_dir / "container.json.j2"
        if container_template.exists():
            rendered = processor.process_service_template(service_name, "container.json.j2", config)
            processed_files['container'] = json.loads(rendered)
        elif (service_dir / "container.json").exists():
            # Fall back to static file
            with open(service_dir / "container.json", 'r') as f:
                processed_files['container'] = json.load(f)
        
        # Docker Compose configuration
        compose_template = service_dir / "docker-compose.yml.j2"
        if compose_template.exists():
            processed_files['compose'] = processor.process_service_template(service_name, "docker-compose.yml.j2", config)
        elif (service_dir / "docker-compose.yml").exists():
            # Fall back to static file
            with open(service_dir / "docker-compose.yml", 'r') as f:
                processed_files['compose'] = f.read()
        
        # Service configuration
        service_template = service_dir / "service.json.j2"
        if service_template.exists():
            rendered = processor.process_service_template(service_name, "service.json.j2", config)
            processed_files['service'] = json.loads(rendered)
        elif (service_dir / "service.json").exists():
            # Fall back to static file
            with open(service_dir / "service.json", 'r') as f:
                processed_files['service'] = json.load(f)
        
        return processed_files