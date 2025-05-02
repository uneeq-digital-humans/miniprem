#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Set up environment variables
export PYTHONPATH=/app
export CUDA_VISIBLE_DEVICES=all

echo "Installing Python dependencies..."
pip3 install -r requirements.txt

echo "Checking for model..."
# Download the model if it doesn't exist
if [ ! -d "/app/models/${MODEL_SIZE}" ]; then
    echo "Downloading model ${MODEL_SIZE}..."
    # First download with CPU to avoid CUDA initialization errors
    python3 -c "from faster_whisper import WhisperModel; model = WhisperModel('${MODEL_SIZE}', device='cpu', compute_type='int8')"
fi

echo "Starting FastAPI server..."
# Start the FastAPI server
cd /app
python3 -m uvicorn app.main:app --host 0.0.0.0 --port 9000