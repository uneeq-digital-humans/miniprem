#!/bin/bash

# Set up environment variables
export PYTHONPATH=/app
export CUDA_VISIBLE_DEVICES=all

# Install Python dependencies
pip3 install -r requirements.txt

# Download the model if it doesn't exist
if [ ! -d "/app/models/small-v3" ]; then
    python3 -c "from faster_whisper import WhisperModel; model = WhisperModel('small-v3', device='cuda', compute_type='float16')"
fi

# Start the FastAPI server
cd /app
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 9000