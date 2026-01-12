"""Table of Contents generation.

This module generates a professional Table of Contents for the PDF
with category groupings and CSS-based page numbers.
"""

import logging
from typing import List

from .config import CATEGORY_DISPLAY_NAMES
from .models import Document, DocumentCategory, TableOfContentsEntry

logger = logging.getLogger(__name__)


class TOCGenerator:
    """Generate Table of Contents for PDF.

    Creates a structured TOC with category headers and document entries,
    using CSS target-counter() for accurate page numbers in the rendered PDF.
    """

    def generate(self, documents: List[Document]) -> str:
        """Generate TOC HTML from documents.

        Creates a structured table of contents with:
        - Category headers for document groupings
        - Document entries with links to anchors
        - CSS-based page number references

        Args:
            documents: List of documents in display order

        Returns:
            TOC HTML string
        """
        if not documents:
            logger.warning("No documents provided for TOC generation")
            return ""

        # Build TOC entries with category groupings
        entries: List[TableOfContentsEntry] = []
        current_category: DocumentCategory = None

        for doc in documents:
            # Add category header if category changed
            if doc.category != current_category and doc.category != DocumentCategory.ALL:
                current_category = doc.category
                category_name = CATEGORY_DISPLAY_NAMES.get(
                    doc.category.value,
                    doc.category.value.title()
                )
                entries.append(TableOfContentsEntry(
                    title=category_name,
                    level=0,
                    anchor="",
                    is_category=True
                ))

            # Add document entry
            entries.append(TableOfContentsEntry(
                title=doc.title,
                level=doc.level,
                anchor=doc.anchor,
                is_category=False
            ))

        # Generate HTML
        toc_items = []
        for entry in entries:
            if entry.is_category:
                toc_items.append(
                    f'        <li class="toc-category">{entry.title}</li>'
                )
            else:
                toc_items.append(f'''        <li class="toc-entry toc-level-{entry.level}">
            <a href="#{entry.anchor}">
                <span class="toc-text">{entry.title}</span>
                <span class="toc-dots"></span>
                <span class="toc-page"></span>
            </a>
        </li>''')

        toc_html = f'''<nav class="table-of-contents">
    <h1 class="toc-title">Table of Contents</h1>
    <ol class="toc-list">
{chr(10).join(toc_items)}
    </ol>
</nav>
'''

        logger.info(f"Generated TOC with {len(entries)} entries")
        return toc_html
