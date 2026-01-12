#!/bin/bash
# =============================================================================
# MiniPrem Documentation PDF Generator
# =============================================================================
# Generates professional PDF documentation from MiniPrem markdown files
# with UneeQ branding, category filtering, and enterprise-quality formatting.
#
# Usage:
#   ./scripts/generate-docs-pdf.sh [OPTIONS]
#
# Options:
#   -c, --category    Filter by category: docker|kubernetes|services|api|advanced|all
#   -o, --output      Output PDF file path
#   -t, --title       Custom document title
#   --no-toc          Skip table of contents generation
#   --no-cover        Skip cover page generation
#   --no-watermark    Skip watermark on pages
#   -v, --verbose     Enable verbose output
#   -h, --help        Show help message
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Script Configuration
# =============================================================================

# Resolve script and project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source logging utilities
if [[ -f "$PROJECT_ROOT/scripts/logging.sh" ]]; then
    source "$PROJECT_ROOT/scripts/logging.sh"
else
    # Fallback logging functions if logging.sh not available
    info() { echo "[INFO] $*"; }
    success() { echo "[SUCCESS] $*"; }
    warning() { echo "[WARNING] $*"; }
    error() { echo "[ERROR] $*"; }
    fatal() { echo "[FATAL] $*"; exit 1; }
    log_section() { echo -e "\n=== $1 ===\n"; }
    CHECKMARK="[OK]"
fi

# =============================================================================
# Default Configuration
# =============================================================================

CATEGORY="all"
OUTPUT_PATH="${PROJECT_ROOT}/docs/MiniPrem-Documentation.pdf"
TITLE="MiniPrem Documentation"
INCLUDE_TOC=true
INCLUDE_COVER=true
INCLUDE_WATERMARK=true
VERBOSE=false

# Asset paths
DOCS_DIR="${PROJECT_ROOT}/docs"
LOGO_PATH="${PROJECT_ROOT}/docs/images/logos/logo-horizontal-color.png"
WATERMARK_LOGO="${PROJECT_ROOT}/miniprem-monitor/frontend/public/assets/logos/uneeq-logo.svg"
VENV_PATH="${PROJECT_ROOT}/scripts/pdf_generator/.venv"
REQUIREMENTS_FILE="${PROJECT_ROOT}/scripts/pdf_generator/requirements.txt"

# =============================================================================
# Help Function
# =============================================================================

show_help() {
    cat << 'EOF'
MiniPrem Documentation PDF Generator
=====================================

Generate professional PDF documentation from MiniPrem markdown files.

USAGE:
    ./scripts/generate-docs-pdf.sh [OPTIONS]

OPTIONS:
    -c, --category CATEGORY    Filter by category (default: all)
                               Values: docker|kubernetes|services|api|advanced|all
                               Comma-separated for multiple: docker,kubernetes

    -o, --output PATH          Output PDF file path
                               (default: docs/MiniPrem-Documentation.pdf)

    -t, --title TITLE          Custom document title
                               (default: "MiniPrem Documentation")

    --no-toc                   Skip table of contents generation
    --no-cover                 Skip cover page generation
    --no-watermark             Skip watermark on pages

    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

CATEGORIES:
    docker       Docker deployment guides and local setup
    kubernetes   Kubernetes/EKS/AKS production deployment
    services     Service configuration (Flowise, vLLM, Renny, etc.)
    api          API reference documentation
    advanced     Advanced topics (telemetry, troubleshooting)
    all          All documentation in sidebar order (default)

EXAMPLES:
    # Generate complete documentation
    ./scripts/generate-docs-pdf.sh

    # Generate only Kubernetes documentation
    ./scripts/generate-docs-pdf.sh --category kubernetes

    # Generate Docker and Kubernetes docs
    ./scripts/generate-docs-pdf.sh -c docker,kubernetes

    # Custom output path with verbose logging
    ./scripts/generate-docs-pdf.sh -o ~/Desktop/miniprem-docs.pdf -v

    # Generate without cover page or watermark
    ./scripts/generate-docs-pdf.sh --no-cover --no-watermark

REQUIREMENTS:
    - Python 3.8 or higher
    - System libraries for WeasyPrint:
      macOS:  brew install pango cairo libffi gdk-pixbuf
      Ubuntu: apt-get install libcairo2 libpango-1.0-0 libgdk-pixbuf2.0-0

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--category)
            CATEGORY="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -t|--title)
            TITLE="$2"
            shift 2
            ;;
        --no-toc)
            INCLUDE_TOC=false
            shift
            ;;
        --no-cover)
            INCLUDE_COVER=false
            shift
            ;;
        --no-watermark)
            INCLUDE_WATERMARK=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "" "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Execution
# =============================================================================

log_section "MiniPrem PDF Documentation Generator"

# Verify documentation directory exists
if [[ ! -d "$DOCS_DIR" ]]; then
    fatal "" "Documentation directory not found: $DOCS_DIR"
fi

# Verify Python is available
info "" "Checking Python environment..."
if ! command -v python3 &> /dev/null; then
    fatal "" "Python 3 is required but not installed."
fi

PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
info "" "Found Python $PYTHON_VERSION"

# Create virtual environment if it doesn't exist
if [[ ! -d "$VENV_PATH" ]]; then
    info "" "Creating Python virtual environment..."
    python3 -m venv "$VENV_PATH"

    # Activate and install dependencies
    source "$VENV_PATH/bin/activate"

    info "" "Installing dependencies..."
    pip install --quiet --upgrade pip
    pip install --quiet -r "$REQUIREMENTS_FILE"

    success "$CHECKMARK" "Virtual environment created and dependencies installed"
else
    source "$VENV_PATH/bin/activate"
fi

# Verify WeasyPrint is available
if ! python3 -c "import weasyprint" &> /dev/null; then
    warning "" "WeasyPrint not found. Installing dependencies..."
    pip install --quiet -r "$REQUIREMENTS_FILE"
fi

# Build Python command arguments
PYTHON_ARGS=(
    "-m" "pdf_generator"
    "--docs-dir" "$DOCS_DIR"
    "--output" "$OUTPUT_PATH"
    "--title" "$TITLE"
    "--category" "$CATEGORY"
)

# Add optional logo paths if files exist
if [[ -f "$LOGO_PATH" ]]; then
    PYTHON_ARGS+=("--logo-path" "$LOGO_PATH")
fi

if [[ -f "$WATERMARK_LOGO" ]]; then
    PYTHON_ARGS+=("--watermark-logo" "$WATERMARK_LOGO")
fi

# Add feature flags
[[ "$INCLUDE_TOC" == "false" ]] && PYTHON_ARGS+=("--no-toc")
[[ "$INCLUDE_COVER" == "false" ]] && PYTHON_ARGS+=("--no-cover")
[[ "$INCLUDE_WATERMARK" == "false" ]] && PYTHON_ARGS+=("--no-watermark")
[[ "$VERBOSE" == "true" ]] && PYTHON_ARGS+=("--verbose")

# Display configuration
info "" "Configuration:"
info "" "  Category:   $CATEGORY"
info "" "  Output:     $OUTPUT_PATH"
info "" "  Title:      $TITLE"
info "" "  Cover:      $INCLUDE_COVER"
info "" "  TOC:        $INCLUDE_TOC"
info "" "  Watermark:  $INCLUDE_WATERMARK"

# Run the PDF generator
info "" "Generating PDF documentation..."
cd "$PROJECT_ROOT/scripts"

if python3 "${PYTHON_ARGS[@]}"; then
    # Verify output file was created
    if [[ -f "$OUTPUT_PATH" ]]; then
        FILE_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)

        echo ""
        success "$CHECKMARK" "PDF generated successfully!"
        info "" "  Output:     $OUTPUT_PATH"
        info "" "  Size:       $FILE_SIZE"
        echo ""
    else
        fatal "" "PDF generation completed but output file not found: $OUTPUT_PATH"
    fi
else
    fatal "" "PDF generation failed. Check the error messages above."
fi

# Deactivate virtual environment
deactivate 2>/dev/null || true

exit 0
