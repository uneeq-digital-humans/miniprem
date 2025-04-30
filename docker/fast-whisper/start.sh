#!/bin/bash

# Set up environment variables
export PYTHONPATH=/app
export CUDA_VISIBLE_DEVICES=all

# Install Python dependencies
pip install -r requirements.txt

# Download the model if it doesn't exist
if [ ! -d "/app/models/large-v3" ]; then
    python -c "from faster_whisper import WhisperModel; model = WhisperModel('large-v3', device='cuda', compute_type='float16')"
fi

# Start the FastAPI server
uvicorn app.main:app --host 0.0.0.0 --port 9000 --reload 