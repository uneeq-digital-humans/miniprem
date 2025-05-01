# Build stage
FROM nvidia/cuda:12.2.2-devel-ubuntu22.04 as builder

# Install wget first
RUN apt-get update && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

# Add NVIDIA repository for cuDNN
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && rm cuda-keyring_1.1-1_all.deb

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg \
    python3-pip \
    python3-dev \
    portaudio19-dev \
    python3-pyaudio \
    x11-apps \
    xclip \
    libcudnn9-cuda-12 \
    libcudnn9-dev-cuda-12 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Runtime stage
FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04

# Install wget first
RUN apt-get update && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

# Add NVIDIA repository for cuDNN
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && rm cuda-keyring_1.1-1_all.deb

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    portaudio19-dev \
    python3-pyaudio \
    x11-apps \
    xclip \
    libcudnn9-cuda-12 \
    && rm -rf /var/lib/apt/lists/*

# Copy Python packages from builder
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
ENV MODEL_SIZE=large-v3
ENV NUM_WORKERS=1
ENV CPU_THREADS=4

EXPOSE 9000
CMD ["/app/start.sh"]