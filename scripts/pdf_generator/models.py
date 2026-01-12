"""Data models for PDF generation.

This module defines the core data structures used throughout the PDF
generation pipeline, including documents, categories, and generation context.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import List, Optional


class DocumentCategory(Enum):
    """Document category enumeration.

    Categories correspond to the main sections in the documentation sidebar
    and can be used to filter which documents are included in the PDF.
    """

    DOCKER = "docker"
    KUBERNETES = "kubernetes"
    SERVICES = "services"
    API = "api"
    ADVANCED = "advanced"
    ALL = "all"

    @classmethod
    def from_string(cls, value: str) -> "DocumentCategory":
        """Create category from string value.

        Args:
            value: Category string (case-insensitive)

        Returns:
            Matching DocumentCategory enum value

        Raises:
            ValueError: If value doesn't match any category
        """
        value_lower = value.lower().strip()
        for category in cls:
            if category.value == value_lower:
                return category
        raise ValueError(f"Unknown category: {value}")


@dataclass
class Document:
    """Represents a markdown document for PDF generation.

    Attributes:
        title: Document title (from sidebar or first heading)
        path: Absolute path to the markdown file
        content: Preprocessed markdown content
        category: Document category for filtering
        order: Order in the final PDF (based on sidebar position)
        level: Heading level in TOC (1-3, determines indentation)
        html_content: Converted HTML content (populated during conversion)
    """

    title: str
    path: Path
    content: str
    category: DocumentCategory
    order: int
    level: int = 1
    html_content: Optional[str] = None

    @property
    def anchor(self) -> str:
        """Generate URL-safe anchor ID from title."""
        import re
        slug = re.sub(r'[^\w\s-]', '', self.title.lower())
        slug = re.sub(r'[-\s]+', '-', slug).strip('-')
        return f"doc-{slug}"


@dataclass
class TableOfContentsEntry:
    """Represents a single entry in the Table of Contents.

    Attributes:
        title: Display title for the entry
        level: Nesting level (1 = top level, higher = more nested)
        anchor: HTML anchor ID for linking
        is_category: True if this is a category header, not a document
    """

    title: str
    level: int
    anchor: str
    is_category: bool = False


@dataclass
class PDFGenerationContext:
    """Context object containing all data needed for PDF generation.

    This object is passed through the generation pipeline and accumulates
    processed data at each stage.

    Attributes:
        documents: List of Document objects to include in PDF
        title: PDF document title
        output_path: Path where PDF will be written
        docs_dir: Path to the documentation root directory (for resolving paths)
        logo_path: Path to cover page logo image
        watermark_logo_path: Path to watermark logo image
        include_toc: Whether to generate table of contents
        include_cover: Whether to generate cover page
        include_watermark: Whether to add watermark to pages
        generation_date: Formatted date string for cover page
        toc_entries: Generated TOC entries (populated during processing)
        final_html: Assembled HTML content (populated during processing)
    """

    documents: List[Document]
    title: str
    output_path: Path
    docs_dir: Path
    logo_path: Path
    watermark_logo_path: Path
    include_toc: bool = True
    include_cover: bool = True
    include_watermark: bool = True
    generation_date: str = field(
        default_factory=lambda: datetime.now().strftime("%B %d, %Y")
    )
    current_year: int = field(
        default_factory=lambda: datetime.now().year
    )
    toc_entries: List[TableOfContentsEntry] = field(default_factory=list)
    final_html: Optional[str] = None
