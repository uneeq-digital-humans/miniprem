"""Render HTML to PDF using WeasyPrint.

This module handles the final conversion from HTML to PDF,
including font configuration and PDF metadata embedding.
"""

import logging
import warnings
from pathlib import Path
from typing import Optional

from weasyprint import HTML, CSS
from weasyprint.text.fonts import FontConfiguration

from .models import PDFGenerationContext

logger = logging.getLogger(__name__)

# Suppress WeasyPrint's "undefined anchor" warnings for base_url resolution
# These occur when links resolve to directory paths, which is benign
logging.getLogger('weasyprint').setLevel(logging.CRITICAL)


class PDFRenderer:
    """Render HTML to PDF with professional styling.

    Uses WeasyPrint to convert assembled HTML documents to PDF,
    handling fonts, styling, and metadata.
    """

    def __init__(self) -> None:
        """Initialize the PDF renderer with font configuration."""
        self.font_config = FontConfiguration()

    def render(
        self,
        html_content: str,
        output_path: Path,
        context: PDFGenerationContext,
        additional_css: Optional[str] = None
    ) -> bool:
        """Render HTML content to PDF file.

        Args:
            html_content: Complete HTML document string
            output_path: Path for output PDF file
            context: PDF generation context (for metadata)
            additional_css: Optional additional CSS to apply

        Returns:
            True if successful, False otherwise

        Raises:
            Exception: If PDF generation fails
        """
        try:
            # Use docs directory as base URL for resolving relative paths
            # This ensures all image paths are resolved correctly
            base_url = str(context.docs_dir) if context.docs_dir else None

            # Create HTML document
            html = HTML(string=html_content, base_url=base_url)

            # Build list of stylesheets
            stylesheets = []
            if additional_css:
                stylesheets.append(CSS(string=additional_css))

            # Ensure output directory exists
            output_path.parent.mkdir(parents=True, exist_ok=True)

            # Render PDF with metadata
            logger.info(f"Rendering PDF to: {output_path}")
            html.write_pdf(
                target=str(output_path),
                stylesheets=stylesheets if stylesheets else None,
                font_config=self.font_config,
            )

            # Verify output file was created
            if output_path.exists():
                file_size = output_path.stat().st_size
                logger.info(
                    f"PDF generated successfully: {output_path} "
                    f"({file_size / 1024:.1f} KB)"
                )
                return True
            else:
                logger.error("PDF file was not created")
                return False

        except Exception as e:
            logger.error(f"PDF generation failed: {e}")
            raise
