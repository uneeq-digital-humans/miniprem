"""Parse sidebar navigation and markdown documents.

This module handles parsing of the Docsify _sidebar.md file to extract
document ordering, as well as preprocessing markdown content for PDF
generation.
"""

import logging
import re
from pathlib import Path
from typing import List, Optional, Tuple

from .config import CategoryMapping
from .models import Document, DocumentCategory

logger = logging.getLogger(__name__)


class SidebarParser:
    """Parse Docsify _sidebar.md to extract document order and hierarchy.

    The sidebar defines the navigation structure of the documentation.
    This parser extracts document titles, paths, and nesting levels to
    determine the order and hierarchy for the PDF.
    """

    def __init__(self, docs_dir: Path) -> None:
        """Initialize the sidebar parser.

        Args:
            docs_dir: Path to the docs directory containing _sidebar.md
        """
        self.docs_dir = docs_dir
        self.sidebar_path = docs_dir / "_sidebar.md"
        self.category_mapping = CategoryMapping()

    def parse(self) -> List[Tuple[str, str, int]]:
        """Parse sidebar and return list of document entries.

        Returns:
            List of tuples: (document_title, relative_path, indent_level)
            where indent_level indicates nesting (1 = top level)

        Raises:
            FileNotFoundError: If _sidebar.md doesn't exist
        """
        if not self.sidebar_path.exists():
            raise FileNotFoundError(f"Sidebar not found: {self.sidebar_path}")

        content = self.sidebar_path.read_text(encoding="utf-8")
        entries: List[Tuple[str, str, int]] = []

        # Pattern: * [Title](path.md) with optional indentation
        # Captures: (indentation, title, path)
        link_pattern = re.compile(
            r'^(\s*)\*\s*\[([^\]]+)\]\(([^)]+)\)',
            re.MULTILINE
        )

        for match in link_pattern.finditer(content):
            indent = len(match.group(1))
            title = match.group(2).strip()
            path = match.group(3).strip()

            # Calculate level from indentation (2 spaces per level)
            level = (indent // 2) + 1

            # Skip anchor-only links (like # or #section)
            if path == "#" or path.startswith("#"):
                continue

            # Normalize path (remove leading /)
            if path.startswith("/"):
                path = path[1:]

            # Skip if it's just an anchor within a file
            if "#" in path and not path.endswith(".md"):
                # Extract the file path before the anchor
                file_path = path.split("#")[0]
                if file_path and file_path.endswith(".md"):
                    path = file_path
                else:
                    continue

            # Skip non-markdown files
            if not path.endswith(".md"):
                continue

            # Skip duplicate entries (same path already added)
            if any(p == path for _, p, _ in entries):
                continue

            entries.append((title, path, level))
            logger.debug(f"Found document: {title} -> {path} (level {level})")

        logger.info(f"Parsed {len(entries)} documents from sidebar")
        return entries

    def get_category_for_path(self, relative_path: str) -> DocumentCategory:
        """Determine the category for a document based on its path.

        Args:
            relative_path: Path relative to docs directory

        Returns:
            DocumentCategory enum value
        """
        mapping = self.category_mapping

        # Check explicit mappings first
        if relative_path in mapping.DOCKER:
            return DocumentCategory.DOCKER
        elif relative_path in mapping.KUBERNETES:
            return DocumentCategory.KUBERNETES
        elif relative_path in mapping.SERVICES:
            return DocumentCategory.SERVICES
        elif relative_path in mapping.API:
            return DocumentCategory.API
        elif relative_path in mapping.ADVANCED:
            return DocumentCategory.ADVANCED

        # Fall back to path-based detection
        path_lower = relative_path.lower()
        if "kubernetes" in path_lower or "eks" in path_lower or "aks" in path_lower:
            return DocumentCategory.KUBERNETES
        elif "docker" in path_lower:
            return DocumentCategory.DOCKER
        elif relative_path.startswith("api/"):
            return DocumentCategory.API
        elif relative_path.startswith("guides/"):
            return DocumentCategory.SERVICES

        # Default to advanced for anything else
        return DocumentCategory.ADVANCED


class MarkdownParser:
    """Parse and preprocess markdown documents for PDF generation.

    This parser reads markdown files and preprocesses them by:
    - Resolving relative image paths to absolute paths
    - Removing Docsify-specific HTML elements
    - Cleaning up formatting for PDF rendering
    """

    def __init__(self, docs_dir: Path) -> None:
        """Initialize the markdown parser.

        Args:
            docs_dir: Path to the docs directory
        """
        self.docs_dir = docs_dir

    def parse_document(
        self,
        relative_path: str,
        title: str,
        category: DocumentCategory,
        order: int,
        level: int
    ) -> Optional[Document]:
        """Parse a markdown document and create a Document object.

        Args:
            relative_path: Path relative to docs directory
            title: Document title from sidebar
            category: Document category
            order: Order in final PDF
            level: TOC nesting level

        Returns:
            Document object or None if file not found
        """
        file_path = self.docs_dir / relative_path

        if not file_path.exists():
            logger.warning(f"Document not found: {file_path}")
            return None

        try:
            content = file_path.read_text(encoding="utf-8")
        except Exception as e:
            logger.error(f"Failed to read {file_path}: {e}")
            return None

        # Preprocess content for PDF rendering
        # Pass both the file's directory and the docs root for proper path resolution
        content = self._preprocess_markdown(content, file_path.parent, self.docs_dir)

        return Document(
            title=title,
            path=file_path,
            content=content,
            category=category,
            order=order,
            level=level
        )

    def _preprocess_markdown(
        self,
        content: str,
        base_dir: Path,
        docs_dir: Path
    ) -> str:
        """Preprocess markdown content for PDF generation.

        Performs the following transformations:
        - Removes Docsify-specific HTML elements (dark mode images, etc.)
        - Converts relative image paths to absolute paths
        - Cleans up info/warning/tip boxes

        Args:
            content: Raw markdown content
            base_dir: Directory containing the markdown file (for path resolution)
            docs_dir: Root docs directory (for resolving paths from root)

        Returns:
            Preprocessed markdown content
        """
        # Remove ALL HTML img tags with logo-dark-mode class (entire tag)
        content = re.sub(
            r'<img[^>]*class=["\'][^"\']*logo-dark-mode[^"\']*["\'][^>]*/?>',
            '',
            content,
            flags=re.IGNORECASE | re.DOTALL
        )

        # Remove ALL div tags (they break markdown parsing)
        # This includes: div align="center", div class="cloud-grid", info-box, etc.
        content = re.sub(
            r'<div[^>]*>\s*\n?',
            '',
            content,
            flags=re.IGNORECASE
        )
        content = re.sub(r'</div>\s*', '', content, flags=re.IGNORECASE)

        # Convert HTML img tags with logo-light-mode to markdown (keep these)
        def html_img_to_markdown(match: re.Match) -> str:
            full_tag = match.group(0)

            # Skip/remove dark mode images entirely
            if 'logo-dark-mode' in full_tag.lower():
                return ''

            # Extract src attribute
            src_match = re.search(r'src=["\']([^"\']+)["\']', full_tag)
            if not src_match:
                return ''
            src = src_match.group(1)

            # Extract alt attribute (optional)
            alt_match = re.search(r'alt=["\']([^"\']*)["\']', full_tag)
            alt = alt_match.group(1) if alt_match else "Image"

            # Resolve relative paths
            if not src.startswith(('http://', 'https://')):
                # Try relative to file's directory first
                abs_path = (base_dir / src).resolve()
                if not abs_path.exists():
                    # Try relative to docs root
                    abs_path = (docs_dir / src).resolve()
                if abs_path.exists():
                    return f'![{alt}]({abs_path})'
                else:
                    logger.debug(f"Image not found, skipping: {src}")
                    return ''

            return f'![{alt}]({src})'

        # Match any img tag
        content = re.sub(
            r'<img\s+[^>]+/?>',
            html_img_to_markdown,
            content,
            flags=re.IGNORECASE | re.DOTALL
        )

        # Convert relative markdown image paths to absolute
        def absolutize_image(match: re.Match) -> str:
            alt_text = match.group(1)
            img_path = match.group(2)

            # Skip already absolute paths and URLs
            if img_path.startswith(('http://', 'https://', '/')):
                return match.group(0)

            # Skip if path is already absolute (contains the docs_dir)
            if str(docs_dir) in img_path:
                return match.group(0)

            # Try relative to file's directory first
            abs_path = (base_dir / img_path).resolve()
            if not abs_path.exists():
                # Try relative to docs root
                abs_path = (docs_dir / img_path).resolve()

            if abs_path.exists():
                return f'![{alt_text}]({abs_path})'
            else:
                # Remove non-existent images entirely to avoid broken links
                logger.debug(f"Image not found, removing: {img_path}")
                return ''

        content = re.sub(
            r'!\[([^\]]*)\]\(([^)]+)\)',
            absolutize_image,
            content
        )

        # Convert info-box divs to blockquotes
        content = re.sub(
            r'<div\s+class=["\'](?:info|tip|warning|error)-box["\']\s*>\s*(.+?)\s*</div>',
            r'> \1',
            content,
            flags=re.DOTALL | re.IGNORECASE
        )

        # Remove any remaining HTML comments
        content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)

        # Convert cross-document markdown links to plain text
        # These links like [text](file.md) or [text](../path/file.md) won't work in PDF
        def remove_md_link(match: re.Match) -> str:
            text = match.group(1)
            path = match.group(2)
            # Keep external links (http/https)
            if path.startswith(('http://', 'https://', 'mailto:')):
                return match.group(0)
            # Keep anchor-only links (they're internal to this document)
            if path.startswith('#'):
                return match.group(0)
            # Keep absolute paths to image files (these are valid)
            if path.startswith('/') and any(path.lower().endswith(ext) for ext in ('.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp')):
                return match.group(0)
            # Remove directory-only links (like "../" or "./")
            if path in ('../', './', '/') or path.rstrip('/') in ('..', '.', ''):
                logger.debug(f"Removing directory link: {path}")
                return text
            # Remove relative file links (markdown documents)
            if path.endswith('.md') or '/' in path:
                logger.debug(f"Removing cross-document link: {path}")
                return text
            # Keep everything else
            return match.group(0)

        content = re.sub(
            r'\[([^\]]+)\]\(([^)]+)\)',
            remove_md_link,
            content
        )

        # Also handle HTML anchor tags with relative hrefs
        def remove_html_link(match: re.Match) -> str:
            href = match.group(1)
            text = match.group(2)
            # Keep external links (http/https) and mailto
            if href.startswith(('http://', 'https://', 'mailto:')):
                return match.group(0)
            # Keep anchor-only links (they're internal to this document)
            if href.startswith('#'):
                return match.group(0)
            # Remove relative file links - just return the text
            logger.debug(f"Removing HTML cross-document link: {href}")
            return text

        content = re.sub(
            r'<a\s+href="([^"]+)"[^>]*>([^<]+)</a>',
            remove_html_link,
            content,
            flags=re.IGNORECASE
        )

        # Remove empty lines that might be left from removed elements
        content = re.sub(r'\n{3,}', '\n\n', content)

        return content
