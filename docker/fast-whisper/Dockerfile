# Build stage - Updated to CUDA 12.8 + Ubuntu 22.04 for driver 580+ support
FROM nvidia/cuda:12.8.0-devel-ubuntu22.04 AS builder

# Install build dependencies (removed unused audio/video libraries)
# Note: CUDA keyring already included in base image
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    python3-pip \
    python3-dev \
    libcudnn9-cuda-12 \
    libcudnn9-dev-cuda-12 \
    libsndfile1 \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install Python dependencies (all packages use pre-built wheels)
RUN pip3 install --no-cache-dir -r requirements.txt

# Runtime stage - Updated to CUDA 12.8 + Ubuntu 22.04 for driver 580+ support
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04

# Install runtime dependencies (removed unused portaudio, pyaudio, x11-apps, xclip)
# Note: CUDA keyring already included in base image
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    libcudnn9-cuda-12 \
    libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

# Create symlink from python3 to python if it doesn't exist
RUN if [ ! -e /usr/bin/python ]; then ln -s /usr/bin/python3 /usr/bin/python; fi
# Copy Python packages from builder (Ubuntu 22.04 uses Python 3.10)
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
WORKDIR /app
COPY app/ /app/app/
COPY start.sh /app/
COPY requirements.txt .

# Create necessary directories
RUN mkdir -p /app/static /app/models
RUN chmod +x /app/start.sh

# Set LD_LIBRARY_PATH
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH

# Add core memory optimization environment variables
ENV PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb=256
ENV CUDA_LAUNCH_BLOCKING=1

# These are defaults that can be overridden by docker-compose
ENV COMPUTE_TYPE=float16
ENV MODEL_SIZE=tiny.en
ENV NUM_WORKERS=1
ENV CPU_THREADS=4

EXPOSE 9000
CMD ["/app/start.sh"]