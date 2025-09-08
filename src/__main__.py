#!/usr/bin/env python3
"""
NFS vs Direct Storage Database Benchmark
Main entry point for the benchmark suite.
"""

import click
import sys
import os
import yaml
from pathlib import Path
from rich.console import Console

from benchmark.runner import BenchmarkRunner
from benchmark.config import BenchmarkConfig
from benchmark.logger import setup_logging

console = Console()


@click.group()
@click.version_option(version="1.0.0", prog_name="NFS vs Direct Benchmark")
def cli():
    """NFS vs Direct Storage Database Benchmark Suite"""
    pass


@cli.command()
@click.option(
    "--config",
    "-c",
    type=click.Path(exists=True, path_type=Path),
    default="config/default.yaml",
    help="Configuration file path"
)
@click.option(
    "--output",
    "-o",
    type=click.Path(path_type=Path),
    help="Output directory for results"
)
@click.option(
    "--databases",
    "-d",
    multiple=True,
    type=click.Choice(["postgresql", "mysql", "sqlite"]),
    help="Specific databases to benchmark (default: all enabled)"
)
@click.option(
    "--scenarios",
    "-s",
    multiple=True,
    help="Specific scenarios to run (default: all enabled)"
)
@click.option(
    "--storage-types",
    multiple=True,
    type=click.Choice(["direct", "nfs"]),
    default=["direct", "nfs"],
    help="Storage types to benchmark"
)
@click.option(
    "--nfs-versions",
    multiple=True,
    type=click.Choice(["v3", "v4"]),
    help="NFS versions to test (default: from config)"
)
@click.option(
    "--verbose",
    "-v",
    is_flag=True,
    help="Enable verbose output"
)
@click.option(
    "--dry-run",
    is_flag=True,
    help="Show what would be run without executing"
)
def run(config, output, databases, scenarios, storage_types, nfs_versions, verbose, dry_run):
    """Run the complete benchmark suite"""
    
    # Setup logging
    log_level = "DEBUG" if verbose else "INFO"
    setup_logging(level=log_level)
    
    try:
        # Load configuration
        console.print(f"[blue]Loading configuration from {config}[/blue]")
        with open(config, 'r') as f:
            config_data = yaml.safe_load(f)
        
        benchmark_config = BenchmarkConfig(config_data)
        
        # Override config with CLI options
        if output:
            benchmark_config.global_config['output_dir'] = str(output)
        if databases:
            # Disable all databases, then enable specified ones
            for db in benchmark_config.databases:
                benchmark_config.databases[db]['enabled'] = db in databases
        if scenarios:
            # Filter scenarios
            benchmark_config.scenarios = [
                s for s in benchmark_config.scenarios 
                if s['name'] in scenarios
            ]
        if nfs_versions:
            benchmark_config.nfs_config['versions'] = list(nfs_versions)
        
        # Initialize benchmark runner
        runner = BenchmarkRunner(benchmark_config)
        
        if dry_run:
            console.print("[yellow]DRY RUN - Showing execution plan:[/yellow]")
            runner.show_execution_plan()
        else:
            console.print("[green]Starting benchmark execution[/green]")
            results = runner.run_all()
            
            if results:
                console.print("[green]✓ Benchmark completed successfully[/green]")
                console.print(f"Results saved to: {results.output_dir}")
            else:
                console.print("[red]✗ Benchmark failed[/red]")
                sys.exit(1)
                
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if verbose:
            console.print_exception()
        sys.exit(1)


@cli.command()
@click.argument("results_dir", type=click.Path(exists=True, path_type=Path))
@click.option(
    "--format",
    "-f",
    multiple=True,
    type=click.Choice(["html", "markdown", "csv", "json"]),
    default=["html", "markdown"],
    help="Report formats to generate"
)
@click.option(
    "--output",
    "-o",
    type=click.Path(path_type=Path),
    help="Output directory for reports"
)
def report(results_dir, format, output):
    """Generate reports from existing benchmark results"""
    
    from reports.generator import ReportGenerator
    
    try:
        generator = ReportGenerator(results_dir)
        
        output_dir = output or results_dir / "reports"
        output_dir.mkdir(exist_ok=True)
        
        for fmt in format:
            console.print(f"[blue]Generating {fmt.upper()} report...[/blue]")
            report_path = generator.generate_report(fmt, output_dir)
            console.print(f"[green]✓ {fmt.upper()} report: {report_path}[/green]")
            
    except Exception as e:
        console.print(f"[red]Error generating reports: {e}[/red]")
        sys.exit(1)


@cli.command()
@click.option(
    "--services",
    "-s",
    multiple=True,
    type=click.Choice(["all", "databases", "nfs-server", "benchmark-runner"]),
    default=["all"],
    help="Services to start"
)
def start(services):
    """Start benchmark infrastructure services"""
    
    from benchmark.infrastructure import InfrastructureManager
    
    try:
        manager = InfrastructureManager()
        
        if "all" in services:
            manager.start_all()
        else:
            for service in services:
                manager.start_service(service)
                
        console.print("[green]✓ Services started successfully[/green]")
        
    except Exception as e:
        console.print(f"[red]Error starting services: {e}[/red]")
        sys.exit(1)


@cli.command()
@click.option(
    "--force",
    "-f",
    is_flag=True,
    help="Force stop and cleanup without confirmation"
)
def stop(force):
    """Stop benchmark infrastructure services"""
    
    from benchmark.infrastructure import InfrastructureManager
    
    try:
        if not force:
            if not click.confirm("Stop all benchmark services?"):
                return
        
        manager = InfrastructureManager()
        manager.stop_all()
        
        console.print("[green]✓ Services stopped successfully[/green]")
        
    except Exception as e:
        console.print(f"[red]Error stopping services: {e}[/red]")
        sys.exit(1)


@cli.command()
def status():
    """Show status of benchmark infrastructure"""
    
    from benchmark.infrastructure import InfrastructureManager
    
    try:
        manager = InfrastructureManager()
        status_info = manager.get_status()
        
        console.print("[blue]Benchmark Infrastructure Status:[/blue]")
        for service, info in status_info.items():
            status_color = "green" if info['running'] else "red"
            console.print(f"  {service}: [{status_color}]{info['status']}[/{status_color}]")
            if info.get('health'):
                console.print(f"    Health: {info['health']}")
        
    except Exception as e:
        console.print(f"[red]Error checking status: {e}[/red]")
        sys.exit(1)


@cli.command()
@click.argument("output_file", type=click.Path(path_type=Path))
def config_template(output_file):
    """Generate a configuration template file"""
    
    template_path = Path(__file__).parent.parent / "config" / "default.yaml"
    
    try:
        with open(template_path, 'r') as src:
            with open(output_file, 'w') as dst:
                dst.write(src.read())
        
        console.print(f"[green]✓ Configuration template saved to {output_file}[/green]")
        console.print("[blue]Edit the file to customize your benchmark settings[/blue]")
        
    except Exception as e:
        console.print(f"[red]Error creating config template: {e}[/red]")
        sys.exit(1)


if __name__ == "__main__":
    cli()
