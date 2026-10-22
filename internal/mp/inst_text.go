package mp

// Text blocks copied byte-for-byte from docker/scripts/install_miniprem.sh (generated; do not hand-edit).

type instEcho struct {
	e bool // echo -e
	s string
}

// bash: install_miniprem.sh:135-156 (heredoc)
const instUsageText = `@BASENAME@ [OPTIONS]
Install and configure Renny digital human with internal speech processing on a laptop/kiosk

Options:
    --platform-address <addr>    UneeQ platform address
    --platform-key <key>         UneeQ platform API key
    --tenant-id <id>             Tenant ID
    --azure-region <region>      Azure region for speech services
    --azure-speech-key <key>     Azure speech subscription key
    --renny-image <image>        Docker image name for Renny
    --region <us|eu>             UneeQ region (us or eu, default: us)
    --deployment-target <type>   Deployment target (hardware or cloud)
    --seed <file>                Load values from a seed file (implies --non-interactive).
                                 See seed.example.env for the full key reference.
    --non-interactive            Disable all interactive prompts; missing required values
                                 abort the install with the full list of what's missing.
    --interactive                Force interactive mode even when --seed is given.
    --force                      Auto-confirm "continue?" gates (port conflicts, duplicate
                                 installs, etc.). Equivalent to MINIPREM_SEED_FORCE=yes.
    --help                       Show this help message
`

// bash: install_miniprem.sh:10-21
var instCwdGuardTop = []instEcho{
	{false, ""},
	{false, "╔═══════════════════════════════════════════════════════════╗"},
	{false, "║  ERROR: Installation script must be run from MiniPrem     ║"},
	{false, "║         root directory                                    ║"},
	{false, "╚═══════════════════════════════════════════════════════════╝"},
	{false, ""},
	{false, "Please change to the MiniPrem directory first:"},
	{false, "  cd /path/to/miniprem"},
	{false, "  sudo ./docker/scripts/install_miniprem.sh"},
	{false, ""},
}

var instCwdGuardBottom = []instEcho{
	{false, ""},
}

// bash: install_miniprem.sh:1783-1793
var instLogoLines = []instEcho{
	{true, "\\e[38;5;208m  #     #  #    #  #######  #######  #######        "},
	{true, "\\e[38;5;209m  #     #  ##   #  #        #        #     #        "},
	{true, "\\e[38;5;210m  #     #  # #  #  #######  #######  #     #        "},
	{true, "\\e[38;5;211m  #     #  #  # #  #        #        #     #        "},
	{true, "\\e[38;5;212m  #     #  #   ##  #        #        #   # #        "},
	{true, "\\e[38;5;213m   #####   #    #  #######  #######  #######        "},
	{false, ""},
	{true, "\\e[38;5;208m  ################################################  "},
	{true, "\\e[38;5;255m               DIGITALHUMANS.COM                    "},
	{true, "\\e[0m"},
	{false, ""},
}

// bash: install_miniprem.sh:2281-2285
var instCustomBanner = []instEcho{
	{false, ""},
	{false, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"},
	{false, "  🔧 Custom Docker Services Setup"},
	{false, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"},
	{false, ""},
}

// bash: install_miniprem.sh:2882-2908
var instFinalBanner = []instEcho{
	{false, ""},
	{false, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"},
	{false, "  ⚙️  Renny Quality Configuration"},
	{false, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"},
	{false, ""},
	{false, "Your Renny quality level is currently set based on your deployment target."},
	{false, ""},
	{false, "To change quality settings:"},
	{false, "  • Edit: @ROOT@/docker/docker-compose.env"},
	{false, "  • Set RENNY_QUALITY_LEVEL to one of:"},
	{false, "    - 'web' (optimized for cloud/web deployment, lower resource usage)"},
	{false, "    - 'miniprem' (optimized for dedicated hardware, higher quality)"},
	{false, "  • Restart: @ROOT@/miniprem.sh restart"},
	{false, ""},
	{false, "For detailed information, see: docs/RENNY_QUALITY_CONFIGURATION.md"},
	{false, ""},
	{false, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"},
	{false, "  📦 Want to run multiple Renny instances for increased capacity?"},
	{false, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"},
	{false, ""},
	{false, "To configure multiple Renny containers:"},
	{false, "  cd @ROOT@/docker/scripts"},
	{false, "  ./setup_multiple_rennys.sh"},
	{false, ""},
	{false, "Recommended: 2-4 instances per GPU (varies by GPU model)"},
	{false, "See docs/MULTIPLE_RENNY_SETUP.md for detailed guidance"},
	{false, ""},
}

// bash: install_miniprem.sh:2013-2021
const instFwRequirements = `faster-whisper==0.10.0
fastapi==0.103.1
uvicorn==0.23.2
python-multipart==0.0.6
pydantic==2.4.2
pyaudio==0.2.13
pyclip==0.7.0
python-dotenv==1.0.0
torch>=2.0.0
`
const instFwStart = `#!/bin/bash
cd /app/app
python3 -m uvicorn main:app --host 0.0.0.0 --port 9000
`
const instFwMain = `from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import os
import time
from faster_whisper import WhisperModel
import tempfile

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Specify path to model files
models_path = '/app/models'

# Initialize model (will be loaded when needed)
model = None

def get_model():
    global model
    if model is None:
        # Check if models directory exists
        if not os.path.exists(models_path):
            os.makedirs(models_path, exist_ok=True)
        
        # Initialize the model
        model = WhisperModel("large-v2", device="cuda", compute_type="float16", download_root=models_path)
    return model

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...), model: str = Form("large-v2")):
    try:
        start_time = time.time()
        
        # Save uploaded file to a temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            temp_file_path = temp_file.name
            content = await file.read()
            temp_file.write(content)
        
        # Get the model
        whisper_model = get_model()
        
        # Transcribe the audio
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5)
        
        # Collect all segments of transcription
        full_text = ""
        for segment in segments:
            full_text += segment.text + " "
        
        # Clean up temporary file
        os.unlink(temp_file_path)
        
        process_time = time.time() - start_time
        
        return {
            "text": full_text.strip(),
            "processing_time": process_time,
            "language": info.language,
            "language_probability": info.language_probability
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9000)
`

// bash: install_miniprem.sh:1214-1232 (heredoc; @DATE@/@HEX32@/@PW@ expanded by the caller in order)
const instFlowiseEnv = `# Generated by install_miniprem.sh on @DATE@
# See flowise.env.example for documentation. Do not commit this file.

# Encryption key for credentials stored in Flowise (changing it makes stored
# credentials undecryptable — wipe the flowise_data volume if you do)
FLOWISE_SECRETKEY_OVERWRITE=@HEX32@

# Auth/session secrets — must stay stable across container restarts
JWT_AUTH_TOKEN_SECRET=@HEX32@
JWT_REFRESH_TOKEN_SECRET=@HEX32@
EXPRESS_SESSION_SECRET=@HEX32@
TOKEN_HASH_SECRET=@HEX32@

# Initial Flowise admin account (created automatically during chatflow setup).
# Use these to log in at http://localhost:3000
FLOWISE_ADMIN_EMAIL=admin@miniprem.local
FLOWISE_ADMIN_PASSWORD=@PW@
`

// bash: install_miniprem.sh:2163-2181
const instSystemdUnit = `[Unit]
Description=MiniPrem (UneeQ Renny + monitor)
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=@ROOT@
ExecStart=@ROOT@/miniprem.sh start
ExecStop=@ROOT@/miniprem.sh stop
TimeoutStartSec=600
TimeoutStopSec=180

[Install]
WantedBy=multi-user.target
`

// bash: install_miniprem.sh:2244-2257
const instDesktopEntry = `[Desktop Entry]
Version=1.0
Type=Application
Name=Start MiniPrem
Comment=Start UneeQ MiniPrem Server
Exec=bash -c 'cd @ROOT@ && ./miniprem.sh start; read -p "Press Enter to close..."'
Icon=utilities-terminal
Terminal=true
Categories=Development;Utility;
Keywords=miniprem;renny;digital-human;
Path=@ROOT@
StartupNotify=false
`

// bash: install_miniprem.sh:1666-1675 (curl -d argument)
const instChatPayload = `{
            "model": "HuggingFaceH4/zephyr-7b-beta",
            "messages": [
                {"role": "system", "content": "You are a helpful AI assistant."},
                {"role": "user", "content": "Hello! Are you working?"}
            ],
            "max_tokens": 50,
            "temperature": 0.7
        }`
