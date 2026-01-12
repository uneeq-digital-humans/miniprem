# PDF Documentation Generator

Generate professional PDF documentation from your MiniPrem installation with UneeQ branding, table of contents, and category filtering.

## Overview

The PDF generator script converts your MiniPrem markdown documentation into a professionally formatted PDF document. Features include:

- **Cover page** with UneeQ logo and document title
- **Table of contents** with clickable page references
- **Category filtering** to generate docs for specific topics
- **Syntax highlighting** for code blocks
- **Professional styling** optimized for printing and sharing

## Quick Start

From the project root directory, run:

```bash
./scripts/generate-docs-pdf.sh
```

This generates the complete documentation PDF at:

```
docs/MiniPrem-Documentation.pdf
```

## Usage

```bash
./scripts/generate-docs-pdf.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `-c, --category` | Filter by category (default: all) |
| `-o, --output` | Output PDF file path |
| `-t, --title` | Custom document title |
| `--no-toc` | Skip table of contents |
| `--no-cover` | Skip cover page |
| `--no-watermark` | Skip watermark on pages |
| `-v, --verbose` | Enable verbose output |
| `-h, --help` | Show help message |

### Categories

Generate documentation for specific topics:

| Category | Content |
|----------|---------|
| `docker` | Docker deployment guides and local setup |
| `kubernetes` | Kubernetes/EKS/AKS production deployment |
| `services` | Service configuration (Flowise, vLLM, Renny, etc.) |
| `api` | API reference documentation |
| `advanced` | Advanced topics (telemetry, troubleshooting) |
| `all` | All documentation in sidebar order (default) |

## Examples

### Generate complete documentation

```bash
./scripts/generate-docs-pdf.sh
```

### Generate only Kubernetes documentation

```bash
./scripts/generate-docs-pdf.sh --category kubernetes
```

### Generate Docker and Kubernetes docs together

```bash
./scripts/generate-docs-pdf.sh -c docker,kubernetes
```

### Custom output path with verbose logging

```bash
./scripts/generate-docs-pdf.sh -o ~/Desktop/miniprem-docs.pdf -v
```

### Generate without cover page or watermark

```bash
./scripts/generate-docs-pdf.sh --no-cover --no-watermark
```

## Output

The generated PDF includes:

1. **Cover page** - UneeQ logo, document title, generation date
2. **Table of contents** - Clickable navigation with page numbers
3. **Document content** - All selected documentation with syntax highlighting
4. **Page footer** - Copyright notice and page numbers

### Default output location

```
docs/MiniPrem-Documentation.pdf
```

## Requirements

### Python

Python 3.8 or higher is required. The script automatically creates a virtual environment and installs dependencies on first run.

### System Libraries

WeasyPrint requires system libraries for PDF rendering:

**macOS:**
```bash
brew install pango cairo libffi gdk-pixbuf
```

**Ubuntu/Debian:**
```bash
apt-get install libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libffi-dev
```

## Troubleshooting

### WeasyPrint installation fails

If you see errors about missing libraries, install the system dependencies listed above for your operating system.

### PDF not generating

1. Check that Python 3.8+ is installed: `python3 --version`
2. Run with verbose flag for details: `./scripts/generate-docs-pdf.sh -v`
3. Verify the docs directory exists: `ls docs/`

### Missing fonts

The PDF uses system fonts. If text appears incorrectly, ensure you have standard system fonts installed.
