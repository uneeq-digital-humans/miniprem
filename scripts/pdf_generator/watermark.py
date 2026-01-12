"""Cover page and watermark generation.

This module handles generation of the PDF cover page with UneeQ branding
and the watermark CSS for page backgrounds.
"""

import base64
import logging
from datetime import datetime
from pathlib import Path

from .config import BRANDING
from .models import PDFGenerationContext

logger = logging.getLogger(__name__)


class CoverPageGenerator:
    """Generate PDF cover page with UneeQ branding.

    Creates a professional cover page including:
    - Company logo (embedded as base64)
    - Document title
    - Generation date
    - Company information and copyright
    """

    def generate(self, context: PDFGenerationContext) -> str:
        """Generate cover page HTML.

        Args:
            context: PDF generation context with logo path and title

        Returns:
            Cover page HTML string
        """
        # Read and encode logo as base64 for embedding
        logo_base64 = ""
        logo_mime = "image/png"

        if context.logo_path and context.logo_path.exists():
            try:
                with open(context.logo_path, "rb") as f:
                    logo_data = f.read()
                    logo_base64 = base64.b64encode(logo_data).decode('utf-8')

                # Determine MIME type from extension
                suffix = context.logo_path.suffix.lower()
                if suffix == '.svg':
                    logo_mime = 'image/svg+xml'
                elif suffix in ('.jpg', '.jpeg'):
                    logo_mime = 'image/jpeg'
                else:
                    logo_mime = 'image/png'

                logger.debug(f"Encoded logo: {context.logo_path}")
            except Exception as e:
                logger.warning(f"Failed to read logo: {e}")
        else:
            logger.warning(f"Logo not found: {context.logo_path}")

        # Format dates
        generation_date = context.generation_date
        current_year = context.current_year

        # Build logo HTML
        logo_html = ""
        if logo_base64:
            logo_html = f'''<img src="data:{logo_mime};base64,{logo_base64}"
                                alt="{BRANDING['company_name']} Logo"
                                class="cover-logo-img" />'''

        # Generate cover page HTML
        cover_html = f'''<div class="cover-page">
    <div class="cover-logo">
        {logo_html}
    </div>

    <div class="cover-title">
        <h1>{context.title}</h1>
        <p class="cover-subtitle">{BRANDING['tagline']}</p>
    </div>

    <div class="cover-metadata">
        <p class="cover-date">Generated: {generation_date}</p>
        <p class="cover-version">Documentation Version 1.0</p>
    </div>

    <div class="cover-footer">
        <p class="cover-copyright">&copy; {current_year} {BRANDING['company_name']}. All rights reserved.</p>
        <p class="cover-website"><a href="https://{BRANDING['website']}">{BRANDING['website']}</a></p>
    </div>
</div>
'''

        logger.info("Generated cover page")
        return cover_html


class WatermarkGenerator:
    """Generate watermark CSS for PDF pages.

    Creates CSS that applies a semi-transparent logo watermark
    to the center of each content page.
    """

    def generate(
        self,
        watermark_logo_path: Path,
        opacity: float = 0.20
    ) -> str:
        """Generate CSS for watermark background.

        Args:
            watermark_logo_path: Path to watermark logo (SVG or PNG)
            opacity: Watermark opacity (0.0-1.0), default 0.20 (20%)

        Returns:
            CSS string for watermark styling
        """
        if not watermark_logo_path or not watermark_logo_path.exists():
            logger.warning(f"Watermark logo not found: {watermark_logo_path}")
            return ""

        try:
            # Read and encode watermark as base64
            with open(watermark_logo_path, "rb") as f:
                watermark_data = f.read()

            watermark_base64 = base64.b64encode(watermark_data).decode('utf-8')

            # Determine MIME type
            suffix = watermark_logo_path.suffix.lower()
            if suffix == '.svg':
                mime = 'image/svg+xml'
            elif suffix in ('.jpg', '.jpeg'):
                mime = 'image/jpeg'
            else:
                mime = 'image/png'

            logger.debug(f"Encoded watermark: {watermark_logo_path}")

        except Exception as e:
            logger.warning(f"Failed to read watermark logo: {e}")
            return ""

        # Generate watermark CSS
        # Uses a pseudo-element for better opacity control
        watermark_css = f'''
/* Watermark Background for Content Pages */
.document-content {{
    position: relative;
}}

.document-content::before {{
    content: "";
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 250px;
    height: 250px;
    background-image: url("data:{mime};base64,{watermark_base64}");
    background-repeat: no-repeat;
    background-position: center;
    background-size: contain;
    opacity: {opacity};
    z-index: -1;
    pointer-events: none;
}}

/* Ensure watermark appears on each page when printed */
@media print {{
    .document-content::before {{
        position: fixed;
    }}
}}
'''

        logger.info(f"Generated watermark CSS with {opacity*100:.0f}% opacity")
        return watermark_css
