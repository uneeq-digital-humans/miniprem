"""Convert markdown to HTML with syntax highlighting.

This module handles the conversion of preprocessed markdown documents
to HTML, including syntax highlighting for code blocks and proper
structuring for PDF generation.
"""

import logging
import re
from pathlib import Path
from typing import List

import markdown
from markdown.extensions.codehilite import CodeHiliteExtension
from markdown.extensions.fenced_code import FencedCodeExtension
from markdown.extensions.tables import TableExtension
from markdown.extensions.toc import TocExtension
from pygments.formatters import HtmlFormatter

from .models import Document, PDFGenerationContext

logger = logging.getLogger(__name__)


class MarkdownConverter:
    """Convert markdown documents to HTML with syntax highlighting.

    Uses python-markdown with extensions for tables, code blocks,
    and syntax highlighting via Pygments.
    """

    def __init__(self) -> None:
        """Initialize the markdown converter with required extensions."""
        self.md = markdown.Markdown(
            extensions=[
                'tables',
                'fenced_code',
                'codehilite',
                'toc',
                'nl2br',
                'sane_lists',
            ],
            extension_configs={
                'codehilite': {
                    'css_class': 'highlight',
                    'guess_lang': True,
                    'linenums': False,
                    'use_pygments': True,
                },
                'toc': {
                    'permalink': False,
                    'toc_depth': '2-4',
                },
            }
        )

    def convert(self, document: Document) -> str:
        """Convert a document's markdown content to HTML.

        Args:
            document: Document object with markdown content

        Returns:
            HTML string wrapped in a section element
        """
        # Reset the markdown instance for each document
        self.md.reset()

        # Convert markdown to HTML
        html = self.md.convert(document.content)

        # Add document-specific prefix to all heading IDs to avoid duplicates
        # This prevents "Anchor defined twice" warnings when multiple docs
        # have the same heading names like "Overview", "Troubleshooting", etc.
        doc_prefix = document.anchor.replace("doc-", "")

        def prefix_id(match: re.Match) -> str:
            tag = match.group(1)
            old_id = match.group(2)
            rest = match.group(3)
            new_id = f"{doc_prefix}-{old_id}"
            return f'<{tag} id="{new_id}"{rest}'

        # Match heading tags with id attributes
        html = re.sub(
            r'<(h[1-6])\s+id="([^"]+)"([^>]*)>',
            prefix_id,
            html,
            flags=re.IGNORECASE
        )

        # Also update any internal links that reference these anchors
        def prefix_href(match: re.Match) -> str:
            old_anchor = match.group(1)
            return f'href="#{doc_prefix}-{old_anchor}"'

        html = re.sub(
            r'href="#([^"]+)"',
            prefix_href,
            html
        )

        # Wrap in section with unique ID for TOC linking
        wrapped_html = f'''
<section id="{document.anchor}" class="document-section">
    <h1 class="document-title">{document.title}</h1>
    {html}
</section>
'''
        return wrapped_html

    def get_pygments_css(self, style: str = "dracula") -> str:
        """Get Pygments CSS for syntax highlighting.

        Args:
            style: Pygments style name (default: dracula for dark code blocks)

        Returns:
            CSS string for syntax highlighting
        """
        try:
            formatter = HtmlFormatter(style=style)
            return formatter.get_style_defs('.highlight')
        except Exception as e:
            logger.warning(f"Failed to get Pygments style '{style}': {e}")
            # Fall back to monokai
            formatter = HtmlFormatter(style="monokai")
            return formatter.get_style_defs('.highlight')


class HTMLAssembler:
    """Assemble final HTML document from converted parts.

    Combines cover page, TOC, document sections, and styling into
    a complete HTML document ready for PDF rendering.
    """

    def __init__(self, styles_dir: Path) -> None:
        """Initialize the HTML assembler.

        Args:
            styles_dir: Path to directory containing pdf.css
        """
        self.styles_dir = styles_dir

    def assemble(
        self,
        context: PDFGenerationContext,
        document_htmls: List[str],
        toc_html: str,
        cover_html: str,
        pygments_css: str,
        watermark_css: str = ""
    ) -> str:
        """Assemble complete HTML document from all components.

        Args:
            context: PDF generation context
            document_htmls: List of converted document HTML strings
            toc_html: Table of contents HTML
            cover_html: Cover page HTML
            pygments_css: Pygments syntax highlighting CSS
            watermark_css: Watermark styling CSS

        Returns:
            Complete HTML document string
        """
        # Load main CSS
        css_path = self.styles_dir / "pdf.css"
        if css_path.exists():
            main_css = css_path.read_text(encoding="utf-8")
        else:
            logger.warning(f"CSS file not found: {css_path}")
            main_css = ""

        # Combine all document sections
        content_html = "\n".join(document_htmls)

        # Build cover page section
        cover_section = ""
        if context.include_cover and cover_html:
            cover_section = cover_html

        # Build TOC section
        toc_section = ""
        if context.include_toc and toc_html:
            toc_section = toc_html

        # Inject dynamic values into CSS
        main_css = main_css.replace("{{CURRENT_YEAR}}", str(context.current_year))

        # Build complete HTML document
        html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{context.title}</title>
    <style>
{main_css}

/* Pygments Syntax Highlighting */
{pygments_css}

/* Watermark Styling */
{watermark_css}
    </style>
</head>
<body>
    {cover_section}
    {toc_section}
    <main class="document-content">
        {content_html}
    </main>
</body>
</html>
'''
        return html
