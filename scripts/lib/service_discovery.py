"""
Service discovery system for automatically detecting and managing services
"""
from pathlib import Path
from typing import List, Dict, Optional, Set
import json
from dataclasses import dataclass
from rich.console import Console
from rich.table import Table

console = Console()


@dataclass
class ServiceInfo:
    """Information about a discovered service"""
    name: str
    directory: Path
    config: Dict
    auto_deploy: bool = False
    category: str = "unknown"
    dependencies: List[str] = None
    
    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []


class ServiceDiscovery:
    """Service discovery and management system"""
    
    def __init__(self, services_dir: Optional[Path] = None):
        self.services_dir = services_dir or Path("config/services")
        self.required_files = ["container.json", "service.json"]
        self.compose_files = ["docker-compose.yml", "docker-compose.yaml"]
    
    def discover_all_services(self) -> List[str]:
        """Discover all valid services by scanning subdirectories"""
        if not self.services_dir.exists():
            console.print(f"⚠️  Services directory not found: {self.services_dir}", style="yellow")
            return []
        
        services = []
        
        for service_dir in self.services_dir.iterdir():
            if service_dir.is_dir() and not service_dir.name.startswith('.'):
                if self.is_valid_service(service_dir):
                    services.append(service_dir.name)
                else:
                    missing_files = self.get_missing_files(service_dir)
                    console.print(
                        f"⚠️  Skipping {service_dir.name}: missing {', '.join(missing_files)}", 
                        style="yellow"
                    )
        
        return sorted(services)
    
    def is_valid_service(self, service_dir: Path) -> bool:
        """Check if service directory has all required files"""
        # Check required files
        has_required = all((service_dir / file).exists() for file in self.required_files)
        
        # Check if at least one compose file exists
        has_compose = any((service_dir / file).exists() for file in self.compose_files)
        
        return has_required and has_compose
    
    def get_missing_files(self, service_dir: Path) -> List[str]:
        """Get list of missing required files for a service"""
        missing = [file for file in self.required_files if not (service_dir / file).exists()]
        
        # Check compose files
        if not any((service_dir / file).exists() for file in self.compose_files):
            missing.append("docker-compose.yml")
        
        return missing
    
    def get_service_info(self, service_name: str) -> Optional[ServiceInfo]:
        """Get detailed information about a service"""
        service_dir = self.services_dir / service_name
        
        if not service_dir.exists():
            return None
        
        if not self.is_valid_service(service_dir):
            return None
        
        # Load service configuration
        try:
            with open(service_dir / "service.json") as f:
                service_config = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            console.print(f"❌ Error loading service.json for {service_name}: {e}", style="red")
            return None
        
        # Extract service info from nested structure
        service_info = service_config.get("service", {})
        dependencies_info = service_config.get("dependencies", {})
        
        return ServiceInfo(
            name=service_name,
            directory=service_dir,
            config=service_config,
            auto_deploy=service_config.get("auto_deploy", False),
            category=service_info.get("category", "unknown"),
            dependencies=dependencies_info.get("required", [])
        )
    
    def get_all_service_info(self) -> List[ServiceInfo]:
        """Get information for all discovered services"""
        service_infos = []
        
        for service_name in self.discover_all_services():
            service_info = self.get_service_info(service_name)
            if service_info:
                service_infos.append(service_info)
        
        return service_infos
    
    def get_auto_deploy_services(self) -> List[str]:
        """Get list of services marked for auto-deployment"""
        auto_deploy = []
        
        for service_info in self.get_all_service_info():
            if service_info.auto_deploy:
                auto_deploy.append(service_info.name)
        
        return auto_deploy
    
    def get_services_by_category(self, category: str) -> List[str]:
        """Get services filtered by category"""
        services = []
        
        for service_info in self.get_all_service_info():
            if service_info.category == category:
                services.append(service_info.name)
        
        return services
    
    def validate_service_dependencies(self, service_name: str) -> bool:
        """Validate that all dependencies for a service exist"""
        service_info = self.get_service_info(service_name)
        if not service_info:
            return False
        
        available_services = set(self.discover_all_services())
        missing_deps = []
        
        for dep in service_info.dependencies:
            if dep not in available_services:
                missing_deps.append(dep)
        
        if missing_deps:
            console.print(
                f"❌ Service {service_name} has missing dependencies: {', '.join(missing_deps)}", 
                style="red"
            )
            return False
        
        return True
    
    def get_deployment_order(self, services: List[str]) -> List[str]:
        """Get services in deployment order based on dependencies"""
        # Create dependency graph
        service_deps = {}
        for service_name in services:
            service_info = self.get_service_info(service_name)
            if service_info:
                # Filter dependencies to only include services in the deployment list
                filtered_deps = [dep for dep in service_info.dependencies if dep in services]
                service_deps[service_name] = filtered_deps
        
        # Topological sort to resolve dependencies
        ordered = []
        visited = set()
        visiting = set()
        
        def visit(service):
            if service in visiting:
                console.print(f"⚠️  Circular dependency detected involving {service}", style="yellow")
                return
            
            if service in visited:
                return
            
            visiting.add(service)
            
            # Visit dependencies first
            for dep in service_deps.get(service, []):
                if dep in services:  # Only visit if dependency is in deployment list
                    visit(dep)
            
            visiting.remove(service)
            visited.add(service)
            ordered.append(service)
        
        # Visit all services
        for service in services:
            visit(service)
        
        return ordered
    
    def list_services(self, show_details: bool = False) -> None:
        """Display a table of all available services"""
        service_infos = self.get_all_service_info()
        
        if not service_infos:
            console.print("No services found in the services directory.", style="yellow")
            return
        
        table = Table(title="📦 Available Services")
        table.add_column("Service", style="cyan")
        table.add_column("Category", style="yellow")
        table.add_column("Auto Deploy", style="green")
        
        if show_details:
            table.add_column("Dependencies", style="blue")
            table.add_column("Description", style="dim")
        
        for service_info in service_infos:
            auto_deploy = "✅" if service_info.auto_deploy else "❌"
            
            row = [
                service_info.name,
                service_info.category,
                auto_deploy
            ]
            
            if show_details:
                deps = ", ".join(service_info.dependencies) if service_info.dependencies else "None"
                service_details = service_info.config.get("service", {})
                description = service_details.get("description", "No description")
                row.extend([deps, description])
            
            table.add_row(*row)
        
        console.print(table)
    
    def validate_services(self, services: List[str]) -> bool:
        """Validate that all specified services exist and have valid dependencies"""
        available_services = set(self.discover_all_services())
        
        # Check if all services exist
        missing_services = [s for s in services if s not in available_services]
        if missing_services:
            console.print(f"❌ Unknown services: {', '.join(missing_services)}", style="red")
            console.print(f"Available services: {', '.join(sorted(available_services))}", style="yellow")
            return False
        
        # Check dependencies
        for service in services:
            if not self.validate_service_dependencies(service):
                return False
        
        return True
    
    def get_service_files(self, service_name: str) -> Dict[str, Path]:
        """Get paths to all service files"""
        service_dir = self.services_dir / service_name
        
        # Find the correct compose file
        compose_file = None
        for file in self.compose_files:
            if (service_dir / file).exists():
                compose_file = service_dir / file
                break
        
        files = {
            "container": service_dir / "container.json",
            "service": service_dir / "service.json"
        }
        
        if compose_file:
            files["compose"] = compose_file
            
        return files
    
    def create_service_directory(self, service_name: str) -> Path:
        """Create a new service directory"""
        service_dir = self.services_dir / service_name
        service_dir.mkdir(parents=True, exist_ok=True)
        return service_dir