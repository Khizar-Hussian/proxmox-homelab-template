#!/usr/bin/env python3
"""
🏠 Proxmox Homelab Deployment Tool

A modern Python-based deployment system for Proxmox homelab infrastructure.
Automatically discovers services and handles deployment with proper validation.
"""

import sys
import os
from pathlib import Path
from typing import List, Optional

import typer
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn
from rich.panel import Panel
from rich.text import Text

# Add the scripts directory to the path so we can import our modules
sys.path.insert(0, str(Path(__file__).parent))

from lib.models import Config
from lib.validation import ComprehensiveValidator
from lib.service_discovery import ServiceDiscovery

# Initialize Typer app and Rich console
app = typer.Typer(
    name="deploy",
    help="🏠 Proxmox Homelab Deployment Tool",
    no_args_is_help=True,
    rich_markup_mode="rich"
)
console = Console()

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent


def load_config(env_file: Optional[Path] = None) -> Config:
    """Load and validate configuration"""
    if env_file is None:
        env_file = PROJECT_ROOT / ".env"
    
    if not env_file.exists():
        console.print(f"❌ Environment file not found: {env_file}", style="red")
        console.print("💡 Copy .env.example to .env and fill in your values", style="yellow")
        raise typer.Exit(1)
    
    try:
        return Config.from_env(env_file)
    except Exception as e:
        console.print(f"❌ Configuration error: {e}", style="red")
        raise typer.Exit(1)


def print_banner():
    """Print application banner"""
    banner_text = Text("🏠 PROXMOX HOMELAB DEPLOYMENT", style="bold blue")
    console.print(Panel(banner_text, expand=False, border_style="blue"))


@app.command()
def validate_only(
    env_file: Optional[Path] = typer.Option(None, "--env-file", help="Path to environment file"),
    verbose: bool = typer.Option(False, "--verbose", help="Verbose output")
):
    """Validate configuration without deploying"""
    print_banner()
    
    try:
        config = load_config(env_file)
        validator = ComprehensiveValidator(config)
        
        if validator.validate_all():
            console.print("\n📋 Configuration Summary:", style="bold")
            config.print_summary()
            console.print("\n✅ Configuration is valid - ready for deployment!", style="bold green")
        else:
            console.print("\n❌ Configuration validation failed", style="bold red")
            raise typer.Exit(1)
            
    except Exception as e:
        console.print(f"❌ Validation error: {e}", style="red")
        raise typer.Exit(1)


@app.command()
def list_services(
    details: bool = typer.Option(False, "--details", help="Show detailed service information")
):
    """List all available services"""
    print_banner()
    
    service_discovery = ServiceDiscovery(PROJECT_ROOT / "config" / "services")
    service_discovery.list_services(show_details=details)


@app.command()
def deploy(
    services: Optional[str] = typer.Option(None, "--services", help="Comma-separated list of services to deploy"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Show what would be done without making changes"),
    verbose: bool = typer.Option(False, "--verbose", help="Verbose output"),
    env_file: Optional[Path] = typer.Option(None, "--env-file", help="Path to environment file")
):
    """Deploy homelab infrastructure"""
    print_banner()
    
    try:
        # Load configuration
        config = load_config(env_file)
        
        # Validate configuration
        validator = ComprehensiveValidator(config)
        if not validator.validate_all():
            console.print("\n❌ Configuration validation failed", style="bold red")
            raise typer.Exit(1)
        
        # Service discovery
        service_discovery = ServiceDiscovery(PROJECT_ROOT / "config" / "services")
        
        # Determine which services to deploy
        if services:
            # Deploy specific services
            service_list = [s.strip() for s in services.split(",")]
            
            # Validate services exist
            if not service_discovery.validate_services(service_list):
                raise typer.Exit(1)
            
            # Get deployment order based on dependencies
            deploy_services = service_discovery.get_deployment_order(service_list)
            
            console.print(f"\n🎯 Deploying specific services: {', '.join(service_list)}", style="green")
            if deploy_services != service_list:
                console.print(f"📋 Deployment order (with dependencies): {', '.join(deploy_services)}", style="blue")
        else:
            # Deploy all auto-deploy services
            auto_deploy_services = service_discovery.get_auto_deploy_services()
            
            if not auto_deploy_services:
                console.print("\n⚠️  No services marked for auto-deployment", style="yellow")
                console.print("💡 Use --services to specify services or mark services with 'auto_deploy: true'", style="dim")
                raise typer.Exit(0)
            
            deploy_services = service_discovery.get_deployment_order(auto_deploy_services)
            console.print(f"\n🚀 Deploying auto-deploy services: {', '.join(deploy_services)}", style="green")
        
        # Show what we're about to do
        console.print(f"\n📋 Configuration Summary:", style="bold")
        config.print_summary()
        
        if dry_run:
            console.print(f"\n🔍 DRY RUN - Would deploy the following services:", style="yellow")
            for service in deploy_services:
                console.print(f"  • {service}", style="dim")
            console.print("\n💡 Remove --dry-run to perform actual deployment", style="blue")
            return
        
        # Confirm deployment
        if not typer.confirm(f"\n🚀 Deploy {len(deploy_services)} services?"):
            console.print("❌ Deployment cancelled", style="yellow")
            raise typer.Exit(0)
        
        # Deploy services
        deploy_services_impl(deploy_services, config, verbose)
        
    except Exception as e:
        console.print(f"❌ Deployment error: {e}", style="red")
        raise typer.Exit(1)


def deploy_services_impl(services: List[str], config: Config, verbose: bool = False):
    """Implementation of service deployment"""
    console.print(f"\n🚀 Starting deployment of {len(services)} services...", style="bold green")
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        console=console,
    ) as progress:
        
        # Phase 1: Infrastructure Setup
        infra_task = progress.add_task("Setting up infrastructure...", total=2)
        
        # Network setup
        progress.update(infra_task, description="Setting up networking...")
        setup_networking(config, verbose)
        progress.update(infra_task, advance=1)
        
        # Storage setup
        progress.update(infra_task, description="Setting up storage...")
        setup_storage(config, verbose)
        progress.update(infra_task, advance=1)
        
        # Phase 2: Service Deployment
        service_task = progress.add_task("Deploying services...", total=len(services))
        
        for service_name in services:
            progress.update(service_task, description=f"Deploying {service_name}...")
            deploy_single_service(service_name, config, verbose)
            progress.update(service_task, advance=1)
    
    # Deployment complete
    console.print("\n🎉 Deployment completed successfully!", style="bold green")
    print_deployment_summary(config)


def setup_networking(config: Config, verbose: bool = False):
    """Set up networking infrastructure"""
    if verbose:
        console.print(f"📡 Setting up container bridge: {config.network.container_bridge}")
    
    # TODO: Implement actual networking setup
    # This would create the container bridge, set up iptables rules, etc.
    pass


def setup_storage(config: Config, verbose: bool = False):
    """Set up storage infrastructure"""
    if verbose:
        console.print(f"💾 Setting up NFS mounts from {config.storage.nfs_server}")
    
    # TODO: Implement actual storage setup
    # This would set up NFS mounts, create directories, etc.
    pass


def deploy_single_service(service_name: str, config: Config, verbose: bool = False):
    """Deploy a single service"""
    if verbose:
        console.print(f"📦 Deploying service: {service_name}")
    
    # TODO: Implement actual service deployment
    # This would:
    # 1. Process service templates with Jinja2
    # 2. Create LXC container via Proxmox API
    # 3. Deploy Docker Compose configuration
    # 4. Start the service
    pass


def print_deployment_summary(config: Config):
    """Print deployment summary with service URLs"""
    console.print("\n📋 Deployment Summary:", style="bold")
    console.print("=" * 60, style="dim")
    
    console.print(f"\n🌐 Core Services:")
    console.print(f"  • Pi-hole DNS:        https://pihole.{config.cluster.domain}/admin")
    console.print(f"  • Nginx Proxy:        https://proxy.{config.cluster.domain}:81")
    console.print(f"  • Grafana:            https://grafana.{config.cluster.domain}")
    console.print(f"  • Authentik SSO:      https://auth.{config.cluster.domain}")
    
    console.print(f"\n🔐 Default Credentials:")
    console.print(f"  • Nginx Proxy:        admin@example.com / changeme")
    console.print(f"  • Pi-hole:            admin / [generated]")
    console.print(f"  • Grafana:            admin / admin")
    console.print(f"  • Authentik:          admin@{config.cluster.domain} / [from config]")
    
    console.print(f"\n📊 Container Network:")
    console.print(f"  • Management:         {config.network.management_subnet}")
    console.print(f"  • Containers:         {config.network.container_subnet}")
    console.print(f"  • Core Services:      10.0.0.40-10.0.0.49")
    
    console.print(f"\n📝 Next Steps:")
    console.print(f"  1. Change default passwords for all services")
    console.print(f"  2. Configure SSL certificates in Nginx Proxy Manager")
    console.print(f"  3. Set up authentication providers in Authentik")
    console.print(f"  4. Review monitoring dashboards in Grafana")
    console.print(f"  5. Add your services in config/services/ directory")
    
    console.print("\n=" * 60, style="dim")
    console.print("✅ Your homelab is ready to use!", style="bold green")


@app.command()
def status():
    """Show status of deployed services"""
    print_banner()
    
    # TODO: Implement service status checking
    console.print("🔍 Service status checking coming soon...", style="yellow")


@app.command()
def logs(
    service: str = typer.Argument(..., help="Service name to show logs for"),
    follow: bool = typer.Option(False, "--follow", "-f", help="Follow log output"),
    lines: int = typer.Option(50, "--lines", "-n", help="Number of lines to show")
):
    """Show logs for a specific service"""
    print_banner()
    
    # TODO: Implement log viewing
    console.print(f"📝 Showing logs for {service} (coming soon)...", style="yellow")


@app.command()
def remove(
    service: str = typer.Argument(..., help="Service name to remove"),
    force: bool = typer.Option(False, "--force", help="Force removal without confirmation")
):
    """Remove a service from the homelab"""
    print_banner()
    
    if not force:
        if not typer.confirm(f"Are you sure you want to remove {service}?"):
            console.print("❌ Removal cancelled", style="yellow")
            return
    
    # TODO: Implement service removal
    console.print(f"🗑️  Removing {service} (coming soon)...", style="yellow")


if __name__ == "__main__":
    app()