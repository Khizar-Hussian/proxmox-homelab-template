"""
Deployment implementation for Proxmox homelab services
"""
import json
import time
import subprocess
from typing import Dict, List, Optional
from pathlib import Path

from proxmoxer import ProxmoxAPI
from rich.console import Console
import requests

from .models import Config
from .service_discovery import ServiceDiscovery, ServiceInfo
from .template_processor import TemplateProcessor

console = Console()


class ProxmoxDeploymentError(Exception):
    """Custom exception for deployment errors"""
    pass


class ProxmoxDeployer:
    """Handles deployment to Proxmox infrastructure"""
    
    def __init__(self, config: Config):
        self.config = config
        self.service_discovery = ServiceDiscovery()
        self.template_processor = TemplateProcessor(config)
        self.proxmox = self._connect_proxmox()
    
    def _connect_proxmox(self) -> ProxmoxAPI:
        """Connect to Proxmox API"""
        try:
            # Parse token format: root@pam!token-id=token-secret
            token_full = self.config.secrets.proxmox_token
            
            if '=' not in token_full:
                raise ValueError("Invalid token format - missing '='")
            
            # Split into user!token-id and token-secret
            user_token_part, token_secret = token_full.split('=', 1)
            
            if '!' not in user_token_part:
                raise ValueError("Invalid token format - missing '!'")
            
            # Split user and token name
            user, token_name = user_token_part.split('!', 1)
            
            console.print(f"🔐 Connecting to Proxmox with user: {user}, token: {token_name}")
            console.print(f"📦 Using template: {self.config.proxmox.template}")
            
            proxmox = ProxmoxAPI(
                self.config.proxmox.host,
                user=user,
                token_name=token_name,
                token_value=token_secret,
                verify_ssl=False,
                port=self.config.proxmox.api_port
            )
            
            # Test connection
            version = proxmox.version.get()
            console.print(f"✅ Connected to Proxmox VE {version['version']}", style="green")
            
            return proxmox
            
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to connect to Proxmox: {e}")
    
    def setup_networking(self, verbose: bool = False):
        """Set up container networking"""
        if verbose:
            console.print(f"📡 Setting up container bridge: {self.config.network.container_bridge}")
        
        try:
            # Check if container bridge already exists
            node_name = self._get_node_name()
            network_config = self.proxmox.nodes(node_name).network.get()
            
            bridge_exists = any(
                net.get('iface') == self.config.network.container_bridge 
                for net in network_config
            )
            
            if not bridge_exists:
                # Create container bridge
                console.print(f"🔧 Creating container bridge {self.config.network.container_bridge}")
                
                bridge_config = {
                    'iface': self.config.network.container_bridge,
                    'type': 'bridge',
                    'address': self.config.network.container_gateway,
                    'netmask': '255.255.255.0',
                    'bridge_ports': 'none',
                    'bridge_stp': 'off',
                    'bridge_fd': '0',
                    'comments': 'Container network bridge (auto-created by homelab)'
                }
                
                self.proxmox.nodes(node_name).network.post(**bridge_config)
                console.print(f"✅ Created bridge {self.config.network.container_bridge}")
                
                # Note: Network changes require a reboot to take effect
                console.print("⚠️  Network changes require Proxmox reboot to take effect", style="yellow")
            else:
                console.print(f"✅ Container bridge {self.config.network.container_bridge} already exists")
                
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to set up networking: {e}")
    
    def setup_storage(self, verbose: bool = False):
        """Set up storage infrastructure"""
        if verbose:
            console.print(f"💾 Setting up NFS mounts from {self.config.storage.nfs_server}")
        
        try:
            # Test NFS connectivity
            result = subprocess.run(
                ['showmount', '-e', self.config.storage.nfs_server],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                console.print(f"✅ NFS server {self.config.storage.nfs_server} is accessible")
            else:
                console.print(f"⚠️  NFS server may not be accessible: {result.stderr}", style="yellow")
                
        except Exception as e:
            console.print(f"⚠️  Could not verify NFS connectivity: {e}", style="yellow")
    
    def deploy_single_service(self, service_name: str, verbose: bool = False):
        """Deploy a single service"""
        console.print(f"📦 Deploying service: {service_name}")
        
        try:
            # Get service info
            service_info = self.service_discovery.get_service_info(service_name)
            if not service_info:
                raise ProxmoxDeploymentError(f"Service {service_name} not found")
            
            # Load service configuration
            service_files = self.service_discovery.get_service_files(service_name)
            
            # Load container configuration
            with open(service_files['container'], 'r') as f:
                container_config_raw = json.load(f)
            
            # Handle nested container structure
            if 'container' in container_config_raw:
                container_config = container_config_raw['container']
                # Map nested structure to flat structure expected by deployment code
                flat_config = {
                    'container_id': container_config['id'],
                    'hostname': container_config['hostname'],
                    'ip_address': container_config['ip'],
                    'cpu_cores': container_config['resources']['cpu'],
                    'memory_mb': container_config['resources']['memory'],
                    'disk_gb': container_config['resources']['disk'],
                    'features': container_config.get('features', [])
                }
                
                # Add mounts if present
                if 'nfs_mounts' in container_config and container_config['nfs_mounts']:
                    flat_config['mounts'] = container_config['nfs_mounts']
                    
            else:
                # Assume flat structure
                flat_config = container_config_raw
            
            # Create LXC container
            container_id = self._create_container(service_info, flat_config, verbose)
            
            # Wait for container to be ready
            self._wait_for_container_ready(container_id)
            
            # Deploy service inside container
            self._deploy_service_in_container(container_id, service_info, service_files, verbose)
            
            console.print(f"✅ Successfully deployed {service_name}")
            
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to deploy {service_name}: {e}")
    
    def _create_container(self, service_info: ServiceInfo, container_config: Dict, verbose: bool = False) -> int:
        """Create LXC container"""
        container_id = container_config['container_id']
        hostname = container_config['hostname']
        ip_address = container_config['ip_address']
        
        if verbose:
            console.print(f"🏗️  Creating container {container_id} ({hostname})")
        
        try:
            node_name = self._get_node_name()
            
            # Check if container already exists
            try:
                existing = self.proxmox.nodes(node_name).lxc(container_id).config.get()
                console.print(f"⚠️  Container {container_id} already exists, skipping creation", style="yellow")
                return container_id
            except:
                pass  # Container doesn't exist, proceed with creation
            
            # Container creation parameters
            create_params = {
                'vmid': container_id,
                'hostname': hostname,
                'ostemplate': self.config.proxmox.template,
                'cores': container_config.get('cpu_cores', 1),
                'memory': container_config.get('memory_mb', 512),
                'rootfs': f"local-lvm:{container_config.get('disk_gb', 8)}",
                'net0': f"name=eth0,bridge=vmbr0,ip={ip_address}/24,gw={self.config.network.management_gateway}",
                'nameserver': "8.8.8.8,8.8.4.4",
                'searchdomain': self.config.cluster.domain,
                'features': self._get_safe_features(container_config),
                'unprivileged': 1,
                'onboot': 1,
                'startup': 'order=1',
                'description': f"Homelab service: {service_info.name}"
            }
            
            # Add NFS mounts if specified
            if 'mounts' in container_config and container_config['mounts']:
                for i, mount in enumerate(container_config['mounts']):
                    mount_point = f"mp{i}"
                    mount_config = f"{mount['source']},{mount['target']}"
                    if mount.get('readonly', False):
                        mount_config += ",ro=1"
                    create_params[mount_point] = mount_config
            
            # Create container
            task_id = self.proxmox.nodes(node_name).lxc.post(**create_params)
            
            # Wait for creation to complete
            self._wait_for_task(task_id)
            
            console.print(f"✅ Created container {container_id} ({hostname})")
            
            # Start container
            self.proxmox.nodes(node_name).lxc(container_id).status.start.post()
            console.print(f"🚀 Started container {container_id}")
            
            return container_id
            
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to create container {container_id}: {e}")
    
    def _deploy_service_in_container(self, container_id: int, service_info: ServiceInfo, service_files: Dict, verbose: bool = False):
        """Deploy service inside the container"""
        if verbose:
            console.print(f"📋 Deploying service configuration in container {container_id}")
        
        try:
            node_name = self._get_node_name()
            
            # Install Docker and Docker Compose
            self._install_docker_in_container(container_id)
            
            # Process docker-compose template
            compose_content = self.template_processor.process_template(service_files['compose'])
            
            # Upload docker-compose.yml to container
            compose_path = f"/opt/{service_info.name}/docker-compose.yml"
            self._upload_file_to_container(container_id, compose_content, compose_path)
            
            # Start the service
            self._execute_in_container(container_id, f"cd /opt/{service_info.name} && docker-compose up -d")
            
            console.print(f"✅ Service {service_info.name} is running in container {container_id}")
            
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to deploy service in container {container_id}: {e}")
    
    def _install_docker_in_container(self, container_id: int):
        """Install Docker and Docker Compose in container"""
        console.print(f"🐳 Installing Docker in container {container_id}")
        
        # First, kill any hanging apt processes
        try:
            console.print("🔧 Cleaning up any hanging processes...")
            self._execute_in_container(container_id, "pkill -f apt-get || true")
            self._execute_in_container(container_id, "rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*")
        except:
            pass  # Continue even if cleanup fails
        
        # Check network connectivity first
        try:
            console.print("🌐 Testing network connectivity...")
            result = self._execute_in_container(container_id, "ping -c 1 8.8.8.8")
            console.print("✅ Network connectivity OK")
        except:
            console.print("❌ Network connectivity failed")
            # Debug network configuration
            console.print("🔍 Checking network configuration...")
            try:
                ip_result = self._execute_in_container(container_id, "ip addr show")
                console.print(f"IP configuration: {ip_result}")
                route_result = self._execute_in_container(container_id, "ip route show")
                console.print(f"Route table: {route_result}")
                dns_result = self._execute_in_container(container_id, "cat /etc/resolv.conf")
                console.print(f"DNS config: {dns_result}")
            except Exception as e:
                console.print(f"Debug failed: {e}")
            
            # Try to fix DNS and network
            console.print("🔧 Fixing DNS configuration...")
            self._execute_in_container(container_id, "echo 'nameserver 8.8.8.8' > /etc/resolv.conf")
            self._execute_in_container(container_id, "echo 'nameserver 8.8.4.4' >> /etc/resolv.conf")
            
            # Test again
            try:
                self._execute_in_container(container_id, "ping -c 1 8.8.8.8")
                console.print("✅ Network connectivity restored")
            except:
                console.print("❌ Network still not working - using local sources")
                # Try using local Ubuntu repositories
                self._execute_in_container(container_id, "sed -i 's/archive.ubuntu.com/mirror.enzu.com/g' /etc/apt/sources.list")
                self._execute_in_container(container_id, "sed -i 's/security.ubuntu.com/mirror.enzu.com/g' /etc/apt/sources.list")
        
        commands = [
            ("locale-gen en_US.UTF-8", "Generating locales"),
            ("update-locale LANG=en_US.UTF-8", "Setting system locale"),
            ("apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=30", "Updating package lists"),
            ("apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl gnupg lsb-release", "Installing prerequisites"),
            ("curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg", "Adding Docker GPG key"),
            ("echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null", "Adding Docker repository"),
            ("apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=30", "Updating package lists with Docker repo"),
            ("apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-compose-plugin", "Installing Docker"),
            ("systemctl enable docker", "Enabling Docker service"),
            ("systemctl start docker", "Starting Docker service"),
            ("docker --version", "Verifying Docker installation")
        ]
        
        for cmd, description in commands:
            console.print(f"⚙️  {description}...")
            result = self._execute_in_container(container_id, cmd)
            if "docker --version" in cmd:
                console.print(f"✅ {result.strip()}")
        
        console.print(f"✅ Docker installed in container {container_id}")
    
    def _execute_in_container(self, container_id: int, command: str):
        """Execute command in container using subprocess"""
        try:
            # Set environment variables for locale
            env_setup = "export DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8"
            full_command = f"{env_setup} && {command}"
            
            # Use pct exec directly since the API exec method is not implemented in proxmoxer
            result = subprocess.run(
                ['pct', 'exec', str(container_id), '--', 'bash', '-c', full_command],
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            
            if result.returncode != 0:
                raise ProxmoxDeploymentError(f"Command failed with exit code {result.returncode}: {result.stderr}")
            
            return result.stdout
            
        except subprocess.TimeoutExpired:
            raise ProxmoxDeploymentError(f"Command timed out in container {container_id}")
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to execute command in container {container_id}: {e}")
    
    def _upload_file_to_container(self, container_id: int, content: str, path: str):
        """Upload file content to container"""
        try:
            # Create directory if it doesn't exist
            dir_path = str(Path(path).parent)
            self._execute_in_container(container_id, f"mkdir -p {dir_path}")
            
            # Write file content using a here document to avoid escaping issues
            heredoc_delimiter = "EOF_HOMELAB_DEPLOY"
            command = f"""cat > {path} << '{heredoc_delimiter}'
{content}
{heredoc_delimiter}"""
            
            self._execute_in_container(container_id, command)
            
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to upload file to container {container_id}: {e}")
    
    def _wait_for_container_ready(self, container_id: int, timeout: int = 180):
        """Wait for container to be ready"""
        console.print(f"⏳ Waiting for container {container_id} to be ready...")
        
        node_name = self._get_node_name()
        
        for i in range(timeout):
            try:
                status = self.proxmox.nodes(node_name).lxc(container_id).status.current.get()
                current_status = status['status']
                
                # Print status updates every 10 seconds
                if i % 10 == 0:
                    console.print(f"🔄 Container {container_id} status: {current_status} (waiting {i}s)")
                
                if current_status == 'running':
                    # Additional check - try to execute a simple command
                    try:
                        console.print(f"🧪 Testing container {container_id} responsiveness...")
                        self._execute_in_container(container_id, "echo 'ready'")
                        console.print(f"✅ Container {container_id} is ready and responsive")
                        return
                    except Exception as e:
                        if i % 10 == 0:
                            console.print(f"⚠️  Container {container_id} running but not yet responsive: {e}")
                        pass
                
                time.sleep(1)
                
            except Exception as e:
                if i % 10 == 0:
                    console.print(f"⚠️  Error checking container {container_id}: {e}")
                time.sleep(1)
        
        raise ProxmoxDeploymentError(f"Container {container_id} not ready after {timeout} seconds")
    
    def _wait_for_task(self, task_id: str, timeout: int = 300):
        """Wait for Proxmox task to complete"""
        node_name = self._get_node_name()
        
        for i in range(timeout):
            try:
                task = self.proxmox.nodes(node_name).tasks(task_id).status.get()
                if task['status'] == 'stopped':
                    if task.get('exitstatus') == 'OK':
                        return
                    else:
                        raise ProxmoxDeploymentError(f"Task {task_id} failed: {task.get('exitstatus')}")
                
                time.sleep(1)
                
            except Exception as e:
                time.sleep(1)
        
        raise ProxmoxDeploymentError(f"Task {task_id} timeout after {timeout} seconds")
    
    def _get_safe_features(self, container_config: Dict) -> str:
        """Get safe feature flags that don't require root privileges"""
        safe_features = []
        
        # Always enable nesting for Docker
        safe_features.append('nesting=1')
        
        # Only add other features if they're safe
        if 'features' in container_config:
            for feature in container_config['features']:
                if feature == 'nesting=1':
                    continue  # Already added
                # Add other safe features here in the future
                # For now, skip keyctl and other root-only features
                
        return ','.join(safe_features)
    
    def _get_node_name(self) -> str:
        """Get the Proxmox node name"""
        try:
            nodes = self.proxmox.nodes.get()
            if not nodes:
                raise ProxmoxDeploymentError("No Proxmox nodes found")
            
            # Use the first node (in single-node setups)
            return nodes[0]['node']
            
        except Exception as e:
            raise ProxmoxDeploymentError(f"Failed to get node name: {e}")