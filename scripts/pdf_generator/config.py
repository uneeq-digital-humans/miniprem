"""Configuration constants for PDF generation.

This module defines category mappings, PDF styling constants, and branding
information used throughout the PDF generation pipeline.
"""

from dataclasses import dataclass, field
from typing import Dict, List


@dataclass
class CategoryMapping:
    """Maps CLI categories to markdown file patterns.

    Categories are determined by analyzing the docs/_sidebar.md structure
    and grouping related documentation files together.
    """

    DOCKER: List[str] = field(default_factory=list)
    KUBERNETES: List[str] = field(default_factory=list)
    SERVICES: List[str] = field(default_factory=list)
    API: List[str] = field(default_factory=list)
    ADVANCED: List[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        """Initialize category file mappings."""
        self.DOCKER = [
            "guides/getting-started.md",
            "guides/first-steps.md",
            "guides/docker-deployment.md",
            "guides/README_SETUP_MULTIPLE.md",
            "guides/harbor-registry.md",
        ]
        self.KUBERNETES = [
            "guides/kubernetes-overview.md",
            "guides/kubernetes-eks.md",
            "guides/kubernetes-aks.md",
            "guides/kubernetes-multi-cloud.md",
        ]
        self.SERVICES = [
            "guides/services.md",
            "guides/miniprem-monitor.md",
            "guides/flowise.md",
            "guides/vllm.md",
            "guides/monitoring.md",
            "guides/renny.md",
            "guides/rime.md",
            "guides/whisper.md",
        ]
        self.API = [
            "api/README.md",
            "api/health.md",
            "api/container-logs.md",
        ]
        self.ADVANCED = [
            "fastwhisper_gpu_setup.md",
            "TELEMETRY.md",
            "DESIGN_SYSTEM.md",
            "METRICS_DASHBOARD_SETUP.md",
            "IDENTIFIERS_CHEATSHEET.md",
            "troubleshooting.md",
        ]

    def get_all_files(self) -> List[str]:
        """Get all files across all categories."""
        return (
            self.DOCKER +
            self.KUBERNETES +
            self.SERVICES +
            self.API +
            self.ADVANCED
        )


# PDF page and styling configuration
PDF_CONFIG: Dict[str, str] = {
    "page_size": "A4",
    "margin_top": "25mm",
    "margin_bottom": "25mm",
    "margin_left": "20mm",
    "margin_right": "20mm",
    "watermark_opacity": "0.20",
    "code_font_family": "'JetBrains Mono', 'Fira Code', Consolas, Monaco, monospace",
    "body_font_family": "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
}


# UneeQ company branding
BRANDING: Dict[str, str] = {
    "company_name": "UneeQ",
    "product_name": "MiniPrem",
    "tagline": "Digital Humans. Unlimited Possibilities.",
    "website": "www.digitalhumans.com",
    "support_email": "support@digitalhumans.com",
}


# Category display names for TOC
CATEGORY_DISPLAY_NAMES: Dict[str, str] = {
    "docker": "Docker Deployment",
    "kubernetes": "Kubernetes Production",
    "services": "Service Configuration",
    "api": "API Reference",
    "advanced": "Advanced Topics",
}
