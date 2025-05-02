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
import struct
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("fast-whisper")

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
    logger.info(f"Initializing Whisper model: {MODEL_SIZE} with CUDA and compute type {COMPUTE_TYPE}")
    model = WhisperModel(
        MODEL_SIZE,
        device="cuda", 
        compute_type=COMPUTE_TYPE,
        cpu_threads=CPU_THREADS,
        num_workers=NUM_WORKERS,
        download_root="/app/models"
    )
    logger.info("Successfully loaded model with CUDA")
except Exception as e:
    logger.error(f"Failed to initialize with CUDA: {str(e)}")
    logger.info("Falling back to CPU model")
    model = WhisperModel(
        MODEL_SIZE,
        device="cpu",
        compute_type="int8",
        cpu_threads=CPU_THREADS,
        num_workers=NUM_WORKERS,
        download_root="/app/models"
    )
    logger.info("Successfully loaded model with CPU")

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
        self.silence_frames = 0  # Count silent frames
        self.silence_frames_threshold = 10  # Number of silent frames to trigger transcription
        self.sample_rate = 16000       # Standard sample rate for Whisper

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.add(websocket)
        self.audio_buffer[websocket] = bytearray()
        self.silence_frames = 0
        logger.info(f"New WebSocket connection established. Total connections: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)
        if websocket in self.audio_buffer:
            del self.audio_buffer[websocket]
        logger.info(f"WebSocket connection closed. Remaining connections: {len(self.active_connections)}")

    async def process_audio(self, websocket: WebSocket, audio_data: str):
        try:
            # Decode base64 audio data to bytes
            audio_bytes = base64.b64decode(audio_data)
            
            # Append to buffer as raw bytes
            if websocket not in self.audio_buffer:
                self.audio_buffer[websocket] = bytearray()
            
            self.audio_buffer[websocket].extend(audio_bytes)
            
            # Convert to numpy array for silence detection
            audio_array = np.frombuffer(audio_bytes, dtype=np.float32)
            
            # Check for silence to trigger transcription
            if len(audio_array) > 0:
                max_amplitude = np.max(np.abs(audio_array))
                logger.debug(f"Max amplitude: {max_amplitude}")
                
                if max_amplitude < self.silence_threshold:
                    self.silence_frames += 1
                    logger.debug(f"Silence frame detected ({self.silence_frames}/{self.silence_frames_threshold})")
                else:
                    self.silence_frames = 0
                
                # If we detect enough silence frames or have a large buffer, transcribe
                buffer_duration = len(self.audio_buffer[websocket]) / (4 * self.sample_rate)  # 4 bytes per float32
                should_transcribe = (self.silence_frames >= self.silence_frames_threshold and buffer_duration >= 0.5) or buffer_duration >= 5.0
                
                if should_transcribe:
                    logger.info(f"Transcribing: Buffer size: {len(self.audio_buffer[websocket])} bytes, duration: {buffer_duration:.2f} seconds")
                    
                    # Create a WAV file from our buffer
                    with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
                        try:
                            # Convert the buffer to int16 samples
                            float_data = np.frombuffer(self.audio_buffer[websocket], dtype=np.float32)
                            int16_data = (float_data * 32767).astype(np.int16)
                            
                            with wave.open(temp_file.name, 'wb') as wf:
                                wf.setnchannels(1)
                                wf.setsampwidth(2)  # 2 bytes for int16
                                wf.setframerate(self.sample_rate)
                                wf.writeframes(int16_data.tobytes())
                            
                            logger.info(f"Created temporary WAV file: {temp_file.name}")
                            
                            # Transcribe the audio
                            segments, info = model.transcribe(
                                temp_file.name,
                                language=None,  # Auto-detect language
                                initial_prompt=None
                            )

                            # Convert segments to text
                            text = " ".join([segment.text for segment in segments])
                            logger.info(f"Transcription result: '{text}'")

                            # Send transcription back to client
                            if text.strip():  # Only send non-empty transcriptions
                                await websocket.send_json({
                                    "type": "transcription",
                                    "text": text,
                                    "language": info.language if hasattr(info, 'language') else "unknown"
                                })
                                logger.info(f"Sent transcription to client: '{text}'")
                            else:
                                logger.info("Transcription was empty, not sending to client")

                        except Exception as e:
                            logger.error(f"Error during transcription: {str(e)}")
                        finally:
                            # Clean up
                            try:
                                os.unlink(temp_file.name)
                            except:
                                pass
                            
                            # Reset buffer and silence counter
                            self.audio_buffer[websocket] = bytearray()
                            self.silence_frames = 0
                    
        except Exception as e:
            logger.error(f"Error processing audio: {str(e)}")
            # Don't reset the buffer on error, but if it's too large, clear it to prevent memory issues
            if websocket in self.audio_buffer and len(self.audio_buffer[websocket]) > 1000000:  # 1MB limit
                logger.warning("Buffer too large, clearing to prevent memory issues")
                self.audio_buffer[websocket] = bytearray()
                self.silence_frames = 0

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
                elif message["type"] == "ping":
                    # Respond to ping message
                    await websocket.send_json({"type": "pong"})
            except json.JSONDecodeError:
                logger.error("Failed to decode JSON from websocket")
                continue
            except Exception as e:
                logger.error(f"Error in websocket processing: {str(e)}")
    except Exception as e:
        logger.error(f"WebSocket error: {str(e)}")
    finally:
        manager.disconnect(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=9000) 