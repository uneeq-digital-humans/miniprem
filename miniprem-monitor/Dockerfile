# Multi-stage build for MiniPrem Monitor
# Stage 1: Build Next.js frontend
# Stage 2: Python runtime with FastAPI backend + built frontend

# ============================================================================
# Stage 1: Frontend Builder
# ============================================================================
FROM node:18-alpine AS frontend-builder

WORKDIR /app/frontend

# Copy package files and install dependencies
COPY frontend/package*.json ./
RUN npm install --legacy-peer-deps

# Copy frontend source and build
COPY frontend/ ./
RUN npm run build

# ============================================================================
# Stage 2: Python Runtime with Both Services
# ============================================================================
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies and CLI tools
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    ca-certificates \
    apt-transport-https \
    supervisor \
    nodejs \
    npm \
    sudo \
    unzip \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (static binary for cross-platform compatibility)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ARCH="x86_64"; elif [ "$ARCH" = "aarch64" ]; then ARCH="aarch64"; fi && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH}/docker-27.5.1.tgz" -o docker.tgz && \
    tar xzf docker.tgz && \
    mv docker/docker /usr/local/bin/ && \
    rm -rf docker docker.tgz && \
    chmod +x /usr/local/bin/docker

# Install kubectl (static binary)
RUN ARCH=$(dpkg --print-architecture) && \
    curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/${ARCH}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install AWS CLI v2 (required for EKS authentication)
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then ARCH="x86_64"; elif [ "$ARCH" = "arm64" ]; then ARCH="aarch64"; fi && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Copy and install Python dependencies
COPY backend/requirements.txt ./backend/
RUN pip install --no-cache-dir -r backend/requirements.txt

# Copy backend application
COPY backend/ ./backend/

# Copy built frontend from builder stage
COPY --from=frontend-builder /app/frontend/.next ./frontend/.next
COPY --from=frontend-builder /app/frontend/package.json ./frontend/
COPY --from=frontend-builder /app/frontend/next.config.js ./frontend/
COPY --from=frontend-builder /app/frontend/node_modules ./frontend/node_modules

# Copy public directory from frontend builder (contains logos and static assets)
COPY --from=frontend-builder /app/frontend/public ./frontend/public

# Copy startup script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Create supervisord configuration
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose port for the application
EXPOSE 3001

# Health check endpoint (FastAPI backend)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Use entrypoint script to start both services
ENTRYPOINT ["/docker-entrypoint.sh"]
