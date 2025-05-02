from fastapi import FastAPI, UploadFile, File, HTTPException, WebSocket
from fastapi.staticfiles import StaticFiles
from faster_whisper import WhisperModel
import os
import tempfile
import soundfile as sf
import numpy as np
from typing import Optional
import asyncio
import wave
import json
import base64
import io

app = FastAPI()

# Mount static files with absolute path
app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")

# Get model configuration from environment variables
MODEL_SIZE = os.environ.get("MODEL_SIZE", "tiny.en")
COMPUTE_TYPE = os.environ.get("COMPUTE_TYPE", "float16")
CPU_THREADS = int(os.environ.get("CPU_THREADS", "4"))
NUM_WORKERS = int(os.environ.get("NUM_WORKERS", "1"))

# Try to initialize the model with CUDA, fall back to CPU if it fails
try:
    print(f"Initializing Whisper model: {MODEL_SIZE} with CUDA and compute type {COMPUTE_TYPE}")
    model = WhisperModel(
        MODEL_SIZE,
        device="cuda", 
        compute_type=COMPUTE_TYPE,
        cpu_threads=CPU_THREADS,
        num_workers=NUM_WORKERS,
        download_root="/app/models"
    )
    print("Successfully loaded model with CUDA")
except Exception as e:
    print(f"Failed to initialize with CUDA: {str(e)}")
    print("Falling back to CPU model")
    model = WhisperModel(
        MODEL_SIZE,
        device="cpu",
        compute_type="int8",
        cpu_threads=CPU_THREADS,
        num_workers=NUM_WORKERS,
        download_root="/app/models"
    )
    print("Successfully loaded model with CPU")

@app.get("/")
async def read_root():
    return {"message": "Fast Whisper API is running. Visit /static/index.html for the test page."}

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/transcribe")
async def transcribe_audio(
    file: UploadFile = File(...),
    language: Optional[str] = None,
    initial_prompt: Optional[str] = None
):
    try:
        # Create a temporary file to store the uploaded audio
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_file_path = temp_file.name

        # Transcribe the audio
        segments, info = model.transcribe(
            temp_file_path,
            language=language,
            initial_prompt=initial_prompt
        )

        # Convert segments to text
        text = " ".join([segment.text for segment in segments])

        # Clean up the temporary file
        os.unlink(temp_file_path)

        return {
            "text": text,
            "language": info.language,
            "language_probability": info.language_probability
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# WebSocket connection manager
class ConnectionManager:
    def __init__(self):
        self.active_connections = set()
        self.audio_buffer = {}
        self.silence_threshold = 0.01  # Adjust based on your needs
        self.silence_duration = 1.0    # Seconds of silence to trigger transcription
        self.sample_rate = 16000       # Standard sample rate for Whisper

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        self.audio_buffer[websocket] = []

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        if websocket in self.audio_buffer:
            del self.audio_buffer[websocket]

    async def process_audio(self, websocket: WebSocket, audio_data: bytes):
        # Convert base64 audio data to numpy array
        audio_bytes = base64.b64decode(audio_data)
        audio_array = np.frombuffer(audio_bytes, dtype=np.float32)
        
        # Add to buffer
        if websocket not in self.audio_buffer:
            self.audio_buffer[websocket] = []
        self.audio_buffer[websocket].extend(audio_array)

        # Check for silence
        if len(audio_array) > 0 and np.max(np.abs(audio_array)) < self.silence_threshold:
            # If we have enough audio data, transcribe it
            if len(self.audio_buffer[websocket]) > self.sample_rate * 2:  # At least 2 seconds of audio
                # Save buffer to temporary WAV file
                with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
                    with wave.open(temp_file.name, 'wb') as wf:
                        wf.setnchannels(1)
                        wf.setsampwidth(2)
                        wf.setframerate(self.sample_rate)
                        wf.writeframes(np.array(self.audio_buffer[websocket], dtype=np.float32).tobytes())

                    # Transcribe the audio
                    segments, info = model.transcribe(
                        temp_file.name,
                        language=None,  # Auto-detect language
                        initial_prompt=None
                    )

                    # Convert segments to text
                    text = " ".join([segment.text for segment in segments])

                    # Send transcription back to client
                    await websocket.send_json({
                        "type": "transcription",
                        "text": text,
                        "language": info.language
                    })

                    # Clean up
                    os.unlink(temp_file.name)
                    self.audio_buffer[websocket] = []

manager = ConnectionManager()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                message = json.loads(data)
                if message["type"] == "audio":
                    await manager.process_audio(websocket, message["data"])
            except json.JSONDecodeError:
                continue
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        manager.disconnect(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000) 