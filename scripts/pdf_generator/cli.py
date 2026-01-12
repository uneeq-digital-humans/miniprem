"""CLI argument parsing and orchestration.

This module provides the command-line interface for the PDF generator,
handling argument parsing and orchestrating the conversion pipeline.
"""

import argparse
import logging
import sys
from pathlib import Path
from typing import List, Optional

from .config import CATEGORY_DISPLAY_NAMES
from .converter import HTMLAssembler, MarkdownConverter
from .models import Document, DocumentCategory, PDFGenerationContext
from .parser import MarkdownParser, SidebarParser
from .renderer import PDFRenderer
from .toc import TOCGenerator
from .watermark import CoverPageGenerator, WatermarkGenerator

logger = logging.getLogger(__name__)


def parse_args(args: Optional[List[str]] = None) -> argparse.Namespace:
    """Parse command line arguments.

    Args:
        args: Command line arguments (defaults to sys.argv)

    Returns:
        Parsed argument namespace
    """
    parser = argparse.ArgumentParser(
        prog="pdf_generator",
        description="Generate professional PDF from MiniPrem documentation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python -m pdf_generator --docs-dir ./docs --output ./MiniPrem-Docs.pdf
  python -m pdf_generator --docs-dir ./docs --category kubernetes -v
  python -m pdf_generator --docs-dir ./docs -c docker,kubernetes

Categories:
  docker      - Docker deployment and setup guides
  kubernetes  - Kubernetes/EKS/AKS deployment guides
  services    - Service configuration (Flowise, vLLM, etc.)
  api         - API reference documentation
  advanced    - Advanced topics (telemetry, troubleshooting)
  all         - All documentation (default)
"""
    )

    parser.add_argument(
        "--docs-dir",
        type=Path,
        required=True,
        help="Path to docs directory containing markdown files"
    )

    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("MiniPrem-Documentation.pdf"),
        help="Output PDF file path (default: MiniPrem-Documentation.pdf)"
    )

    parser.add_argument(
        "-t", "--title",
        default="MiniPrem Documentation",
        help="Document title for cover page (default: MiniPrem Documentation)"
    )

    parser.add_argument(
        "-c", "--category",
        default="all",
        help="Category filter: docker|kubernetes|services|api|advanced|all "
             "(comma-separated for multiple, default: all)"
    )

    parser.add_argument(
        "--logo-path",
        type=Path,
        help="Path to cover page logo image"
    )

    parser.add_argument(
        "--watermark-logo",
        type=Path,
        help="Path to watermark logo image (SVG or PNG)"
    )

    parser.add_argument(
        "--no-toc",
        action="store_true",
        help="Skip table of contents generation"
    )

    parser.add_argument(
        "--no-cover",
        action="store_true",
        help="Skip cover page generation"
    )

    parser.add_argument(
        "--no-watermark",
        action="store_true",
        help="Skip watermark on pages"
    )

    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Enable verbose output"
    )

    return parser.parse_args(args)


def filter_by_category(
    documents: List[Document],
    category_filter: str
) -> List[Document]:
    """Filter documents by category.

    Args:
        documents: List of all documents
        category_filter: Comma-separated category names or 'all'

    Returns:
        Filtered list of documents
    """
    if category_filter.lower() == "all":
        return documents

    # Parse comma-separated categories
    categories = [c.strip().lower() for c in category_filter.split(",")]

    # Filter documents
    filtered = [
        doc for doc in documents
        if doc.category.value in categories
    ]

    logger.info(
        f"Filtered {len(documents)} documents to {len(filtered)} "
        f"for categories: {', '.join(categories)}"
    )

    return filtered


def main(args: Optional[List[str]] = None) -> int:
    """Main entry point for PDF generator.

    Args:
        args: Command line arguments (defaults to sys.argv)

    Returns:
        Exit code (0 for success, non-zero for failure)
    """
    parsed_args = parse_args(args)

    # Configure logging
    log_level = logging.DEBUG if parsed_args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    logger.info(f"MiniPrem PDF Generator starting...")
    logger.info(f"Documentation directory: {parsed_args.docs_dir}")

    # Validate docs directory
    if not parsed_args.docs_dir.exists():
        logger.error(f"Documentation directory not found: {parsed_args.docs_dir}")
        return 1

    # Initialize components
    sidebar_parser = SidebarParser(parsed_args.docs_dir)
    markdown_parser = MarkdownParser(parsed_args.docs_dir)
    markdown_converter = MarkdownConverter()
    toc_generator = TOCGenerator()
    cover_generator = CoverPageGenerator()
    watermark_generator = WatermarkGenerator()
    renderer = PDFRenderer()

    # Get styles directory
    styles_dir = Path(__file__).parent / "styles"
    assembler = HTMLAssembler(styles_dir)

    try:
        # Step 1: Parse sidebar to get document order
        logger.info("Parsing sidebar navigation...")
        sidebar_entries = sidebar_parser.parse()

        if not sidebar_entries:
            logger.error("No documents found in sidebar")
            return 1

        # Step 2: Parse all markdown documents
        logger.info("Parsing markdown documents...")
        documents: List[Document] = []

        for order, (title, rel_path, level) in enumerate(sidebar_entries):
            category = sidebar_parser.get_category_for_path(rel_path)
            doc = markdown_parser.parse_document(
                rel_path, title, category, order, level
            )
            if doc:
                documents.append(doc)

        logger.info(f"Parsed {len(documents)} documents")

        # Step 3: Filter by category
        documents = filter_by_category(documents, parsed_args.category)

        if not documents:
            logger.error(
                f"No documents found for category: {parsed_args.category}"
            )
            return 1

        # Step 4: Create generation context
        context = PDFGenerationContext(
            documents=documents,
            title=parsed_args.title,
            output_path=parsed_args.output,
            docs_dir=parsed_args.docs_dir,
            logo_path=parsed_args.logo_path or Path(),
            watermark_logo_path=parsed_args.watermark_logo or Path(),
            include_toc=not parsed_args.no_toc,
            include_cover=not parsed_args.no_cover,
            include_watermark=not parsed_args.no_watermark,
        )

        # Step 5: Convert documents to HTML
        logger.info("Converting markdown to HTML...")
        document_htmls = []
        for doc in documents:
            html = markdown_converter.convert(doc)
            doc.html_content = html
            document_htmls.append(html)

        # Step 6: Generate TOC
        toc_html = ""
        if context.include_toc:
            logger.info("Generating table of contents...")
            toc_html = toc_generator.generate(documents)

        # Step 7: Generate cover page
        cover_html = ""
        if context.include_cover:
            logger.info("Generating cover page...")
            cover_html = cover_generator.generate(context)

        # Step 8: Generate watermark CSS
        watermark_css = ""
        if context.include_watermark and context.watermark_logo_path.exists():
            logger.info("Generating watermark...")
            watermark_css = watermark_generator.generate(
                context.watermark_logo_path,
                opacity=0.20
            )

        # Step 9: Assemble final HTML
        logger.info("Assembling final HTML document...")
        pygments_css = markdown_converter.get_pygments_css()
        final_html = assembler.assemble(
            context,
            document_htmls,
            toc_html,
            cover_html,
            pygments_css,
            watermark_css
        )

        # Step 10: Render PDF
        logger.info("Rendering PDF...")
        success = renderer.render(
            final_html,
            parsed_args.output,
            context,
            additional_css=watermark_css
        )

        if success:
            logger.info(f"PDF generated successfully: {parsed_args.output}")
            return 0
        else:
            logger.error("PDF generation failed")
            return 1

    except FileNotFoundError as e:
        logger.error(f"File not found: {e}")
        return 1
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
