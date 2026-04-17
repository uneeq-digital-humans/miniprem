# Custom Speech-to-Text (STT) Integration Guide

This guide explains how to integrate your own Speech-to-Text service (such as Azure Speech Services, AWS Transcribe, or any custom STT) with UneeQ digital humans.

## Overview: Understanding STT Options

There are **three ways** to handle speech-to-text with UneeQ:

| Option | Description | Who handles audio? | Who handles transcription? |
|--------|-------------|-------------------|---------------------------|
| **1. UneeQ Built-in STT** | Enable microphone in UneeQ config | UneeQ SDK | UneeQ (Google/Deepgram) |
| **2. MiniPrem Whisper** | Use MiniPrem's Whisper service | Your frontend | MiniPrem Whisper container |
| **3. Custom STT (BYOSTT)** | Bring your own STT provider | Your frontend | Your STT service (Azure, AWS, etc.) |

**This guide focuses on Option 3: Custom STT (Bring Your Own STT)**

## Architecture: How Custom STT Works

When using custom STT, you bypass UneeQ's built-in speech recognition entirely. The flow is:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           YOUR FRONTEND                                      │
│  ┌─────────────┐    ┌─────────────────┐    ┌─────────────────────────────┐  │
│  │  Microphone │───▶│  Audio Capture  │───▶│  Your STT Service           │  │
│  │   (Browser) │    │  (Web Audio API)│    │  (Azure/AWS/Custom)         │  │
│  └─────────────┘    └─────────────────┘    └──────────────┬──────────────┘  │
│                                                           │                  │
│                                                           ▼                  │
│                                            ┌──────────────────────────────┐  │
│                                            │  Transcribed Text            │  │
│                                            │  "Hello, how are you?"       │  │
│                                            └──────────────┬───────────────┘  │
│                                                           │                  │
│                                                           ▼                  │
│                                            ┌──────────────────────────────┐  │
│                                            │  uneeq.chatPrompt(text,true) │  │
│                                            │  Send text to Digital Human  │  │
│                                            └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
                              ┌─────────────────────────────┐
                              │     UneeQ Digital Human     │
                              │   Processes text, responds  │
                              └─────────────────────────────┘
```

## Key Concept: The `chatPrompt()` Method

The `chatPrompt()` method is how you send user text to the UneeQ digital human when using custom STT:

```javascript
// Send transcribed text to the digital human
uneeqInstance.chatPrompt(transcribedText, addClosedCaption);
```

**Parameters:**
- `transcribedText` (string): The text you received from your STT service
- `addClosedCaption` (boolean): Set to `true` to display the text as a caption

**Example:**
```javascript
// User said "What's the weather today?"
// Your Azure STT transcribed it
// Now send it to UneeQ:
uneeqInstance.chatPrompt("What's the weather today?", true);
```

## Step-by-Step Implementation Guide

### Step 1: Configure UneeQ WITHOUT Built-in Microphone

When initializing UneeQ, **do NOT enable the built-in microphone**. The key options are:

```javascript
const uneeqInstance = new Uneeq({
    // Required: Your persona configuration
    connectionUrl: 'https://api.us.uneeq.io',  // Or your region's API endpoint
    personaId: 'your-persona-id',

    // IMPORTANT FOR CUSTOM STT: Keep these disabled
    enableMicrophone: false,  // Default is false - DO NOT set to true
    enableVad: false,         // Disable voice activity detection

    // Optional: Other common settings
    showUserInputInterface: false,  // Hide UneeQ's built-in input UI if using your own
    showClosedCaptions: true,       // Show captions for DH responses
    layoutMode: 'fullScreen',       // or 'overlay', 'contained'
    autoStart: false,               // Control when session starts
});
```

**Key Configuration Options for Custom STT:**

| Option | Value | Why |
|--------|-------|-----|
| `enableMicrophone` | `false` | Prevents UneeQ from capturing audio |
| `enableVad` | `false` | Disables UneeQ's voice activity detection |
| `showUserInputInterface` | `false` | Optional: Hide UneeQ's input UI if you have your own |

**What NOT to do:**
```javascript
// DON'T do this if using custom STT
uneeqInstance.enableMicrophone();  // This enables UneeQ's built-in STT

// DON'T set these in config
{
    enableMicrophone: true,           // This uses UneeQ's Google/Deepgram STT
    enableVad: true,                  // This enables UneeQ's voice detection
    speechRecognitionProvider: 'deepgram',  // Not needed for custom STT
}
```

**Note:** The `speechRecognitionProvider` option (google/deepgram) only applies when using UneeQ's built-in microphone. For custom STT, you handle transcription yourself, so this option is irrelevant.

### Step 2: Capture Audio from the User's Microphone

Use the Web Audio API or MediaRecorder to capture audio:

```javascript
class AudioCaptureService {
    private mediaRecorder: MediaRecorder | null = null;
    private audioChunks: Blob[] = [];

    async startCapture(): Promise<void> {
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: {
                echoCancellation: true,
                noiseSuppression: true,
                sampleRate: 16000,  // Azure STT typically expects 16kHz
            }
        });

        this.mediaRecorder = new MediaRecorder(stream, {
            mimeType: 'audio/webm;codecs=opus'
        });

        this.mediaRecorder.ondataavailable = (event) => {
            if (event.data.size > 0) {
                this.audioChunks.push(event.data);
            }
        };

        this.mediaRecorder.start(100); // Capture in 100ms chunks
    }

    stopCapture(): Blob {
        this.mediaRecorder?.stop();
        const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
        this.audioChunks = [];
        return audioBlob;
    }
}
```

### Step 3: Send Audio to Your STT Service (Azure Example)

#### Option A: Azure Speech SDK (Recommended)

```javascript
import * as SpeechSDK from 'microsoft-cognitiveservices-speech-sdk';

class AzureSTTService {
    private speechConfig: SpeechSDK.SpeechConfig;
    private recognizer: SpeechSDK.SpeechRecognizer | null = null;

    constructor(subscriptionKey: string, region: string) {
        this.speechConfig = SpeechSDK.SpeechConfig.fromSubscription(
            subscriptionKey,
            region
        );
        this.speechConfig.speechRecognitionLanguage = 'en-US';
    }

    async transcribeFromMicrophone(
        onResult: (text: string) => void,
        onError: (error: Error) => void
    ): Promise<void> {
        const audioConfig = SpeechSDK.AudioConfig.fromDefaultMicrophoneInput();
        this.recognizer = new SpeechSDK.SpeechRecognizer(
            this.speechConfig,
            audioConfig
        );

        // Handle interim results (partial transcriptions)
        this.recognizer.recognizing = (_, event) => {
            console.log('Recognizing:', event.result.text);
        };

        // Handle final results
        this.recognizer.recognized = (_, event) => {
            if (event.result.reason === SpeechSDK.ResultReason.RecognizedSpeech) {
                onResult(event.result.text);
            }
        };

        // Handle errors
        this.recognizer.canceled = (_, event) => {
            onError(new Error(`Recognition canceled: ${event.errorDetails}`));
        };

        // Start continuous recognition
        await this.recognizer.startContinuousRecognitionAsync();
    }

    async stop(): Promise<void> {
        await this.recognizer?.stopContinuousRecognitionAsync();
    }
}
```

#### Option B: Azure REST API

If you prefer to handle audio yourself and call Azure's REST API:

```javascript
async function transcribeWithAzureREST(
    audioBlob: Blob,
    subscriptionKey: string,
    region: string
): Promise<string> {
    const response = await fetch(
        `https://${region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US`,
        {
            method: 'POST',
            headers: {
                'Ocp-Apim-Subscription-Key': subscriptionKey,
                'Content-Type': 'audio/wav; codecs=audio/pcm; samplerate=16000',
            },
            body: audioBlob,
        }
    );

    const result = await response.json();
    return result.DisplayText;
}
```

### Step 4: Send Transcribed Text to UneeQ

When you receive transcribed text from your STT service, send it to UneeQ:

```javascript
// Complete integration example
class CustomSTTIntegration {
    private uneeqInstance: any;
    private azureSTT: AzureSTTService;

    constructor(uneeqInstance: any, azureConfig: { key: string; region: string }) {
        this.uneeqInstance = uneeqInstance;
        this.azureSTT = new AzureSTTService(azureConfig.key, azureConfig.region);
    }

    async startListening(): Promise<void> {
        await this.azureSTT.transcribeFromMicrophone(
            // On successful transcription
            (transcribedText: string) => {
                console.log('User said:', transcribedText);

                // Send to UneeQ digital human
                this.uneeqInstance.chatPrompt(transcribedText, true);
            },
            // On error
            (error: Error) => {
                console.error('STT Error:', error);
            }
        );
    }

    async stopListening(): Promise<void> {
        await this.azureSTT.stop();
    }
}
```

### Step 5: Handle Digital Human Speaking States

Mute/unmute your microphone when the digital human is speaking to avoid feedback:

```javascript
// Listen for UneeQ events
window.addEventListener('UneeqMessage', (event) => {
    const msg = event.detail;

    switch (msg.uneeqMessageType) {
        case 'AvatarStartedSpeaking':
            // Mute microphone to avoid picking up DH audio
            customSTT.stopListening();
            break;

        case 'AvatarStoppedSpeaking':
            // Resume listening when DH stops talking
            customSTT.startListening();
            break;
    }
});
```

## Complete Working Example

Here's a complete React component implementing custom STT with Azure:

```typescript
import React, { useEffect, useRef, useState } from 'react';
import * as SpeechSDK from 'microsoft-cognitiveservices-speech-sdk';

interface CustomSTTProps {
    uneeqInstance: any;
    azureKey: string;
    azureRegion: string;
}

export function CustomSTTMicrophone({ uneeqInstance, azureKey, azureRegion }: CustomSTTProps) {
    const [isListening, setIsListening] = useState(false);
    const [transcript, setTranscript] = useState('');
    const recognizerRef = useRef<SpeechSDK.SpeechRecognizer | null>(null);

    const startListening = async () => {
        const speechConfig = SpeechSDK.SpeechConfig.fromSubscription(azureKey, azureRegion);
        speechConfig.speechRecognitionLanguage = 'en-US';

        const audioConfig = SpeechSDK.AudioConfig.fromDefaultMicrophoneInput();
        const recognizer = new SpeechSDK.SpeechRecognizer(speechConfig, audioConfig);
        recognizerRef.current = recognizer;

        // Interim results (for UI feedback)
        recognizer.recognizing = (_, event) => {
            setTranscript(event.result.text);
        };

        // Final results - send to UneeQ
        recognizer.recognized = (_, event) => {
            if (event.result.reason === SpeechSDK.ResultReason.RecognizedSpeech) {
                const text = event.result.text;
                setTranscript(text);

                // Send to UneeQ digital human
                uneeqInstance.chatPrompt(text, true);

                // Clear transcript after sending
                setTimeout(() => setTranscript(''), 500);
            }
        };

        recognizer.canceled = (_, event) => {
            console.error('Recognition canceled:', event.errorDetails);
            setIsListening(false);
        };

        await recognizer.startContinuousRecognitionAsync();
        setIsListening(true);
    };

    const stopListening = async () => {
        await recognizerRef.current?.stopContinuousRecognitionAsync();
        recognizerRef.current = null;
        setIsListening(false);
    };

    // Auto-mute when DH is speaking
    useEffect(() => {
        const handleUneeqMessage = (event: CustomEvent) => {
            const msg = event.detail;
            if (msg.uneeqMessageType === 'AvatarStartedSpeaking') {
                stopListening();
            } else if (msg.uneeqMessageType === 'AvatarStoppedSpeaking') {
                startListening();
            }
        };

        window.addEventListener('UneeqMessage', handleUneeqMessage as EventListener);
        return () => {
            window.removeEventListener('UneeqMessage', handleUneeqMessage as EventListener);
        };
    }, []);

    return (
        <div className="custom-stt-controls">
            <button
                onClick={isListening ? stopListening : startListening}
                className={isListening ? 'listening' : 'muted'}
            >
                {isListening ? 'Stop Listening' : 'Start Listening'}
            </button>
            {transcript && (
                <div className="transcript">
                    {transcript}
                </div>
            )}
        </div>
    );
}
```

## Azure Speech Services Setup

### Prerequisites

1. **Azure Account** with Speech Services resource
2. **Subscription Key** and **Region** from Azure Portal

### Getting Your Credentials

1. Go to [Azure Portal](https://portal.azure.com)
2. Create a new "Speech Services" resource
3. After creation, go to "Keys and Endpoint"
4. Copy:
   - **KEY 1** or **KEY 2** (subscription key)
   - **Location/Region** (e.g., `eastus`, `westus2`)

### Supported Audio Formats

Azure Speech Services accepts:
- **PCM WAV**: 16-bit, mono, 16kHz (recommended)
- **Opus/WebM**: Supported for streaming
- **MP3**: Supported but less efficient

### Language Support

Set the language in your config:
```javascript
speechConfig.speechRecognitionLanguage = 'en-US';  // English (US)
speechConfig.speechRecognitionLanguage = 'es-ES';  // Spanish (Spain)
speechConfig.speechRecognitionLanguage = 'fr-FR';  // French (France)
speechConfig.speechRecognitionLanguage = 'de-DE';  // German
speechConfig.speechRecognitionLanguage = 'ja-JP';  // Japanese
speechConfig.speechRecognitionLanguage = 'zh-CN';  // Chinese (Simplified)
```

See [Azure Language Support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support) for full list.

## Troubleshooting

### Common Issues

**1. "Connection to UneeQ failed"**
- Ensure UneeQ session is initialized before calling `chatPrompt()`
- Check that WebSocket connection is established

**2. "Azure STT not transcribing"**
- Verify subscription key and region are correct
- Check browser microphone permissions
- Ensure audio format matches Azure requirements (16kHz recommended)

**3. "Digital human doesn't respond"**
- Confirm `chatPrompt()` is being called (add console.log)
- Check if text is empty or just whitespace
- Verify UneeQ conversation/session is active

**4. "Echo/feedback loop"**
- Implement auto-mute when DH is speaking (see Step 5)
- Use echo cancellation in audio capture config
- Add physical distance between speaker and microphone

**5. "Transcription is slow"**
- Use streaming/continuous recognition instead of batch
- Choose Azure region closest to your users
- Consider using Azure's Neural models for better accuracy

### Debug Logging

Add logging to track the flow:

```javascript
// In your STT handler
recognizer.recognized = (_, event) => {
    console.log('[CustomSTT] Recognition result:', {
        reason: event.result.reason,
        text: event.result.text,
        duration: event.result.duration
    });

    if (event.result.text) {
        console.log('[CustomSTT] Sending to UneeQ:', event.result.text);
        uneeqInstance.chatPrompt(event.result.text, true);
    }
};

// After chatPrompt
console.log('[CustomSTT] chatPrompt called successfully');
```

## Security Considerations

### Never Expose API Keys in Frontend

Use a backend proxy to handle Azure authentication:

```javascript
// BAD - Don't do this
const azureKey = 'your-key-exposed-in-frontend';

// GOOD - Use a backend token service
async function getAzureToken(): Promise<string> {
    const response = await fetch('/api/azure-stt-token');
    const { token } = await response.json();
    return token;
}

// Then use token-based authentication
const speechConfig = SpeechSDK.SpeechConfig.fromAuthorizationToken(
    token,
    region
);
```

### Backend Token Service Example (Node.js)

```javascript
// /api/azure-stt-token
import fetch from 'node-fetch';

export async function getAzureToken(req, res) {
    const response = await fetch(
        `https://${process.env.AZURE_REGION}.api.cognitive.microsoft.com/sts/v1.0/issueToken`,
        {
            method: 'POST',
            headers: {
                'Ocp-Apim-Subscription-Key': process.env.AZURE_SPEECH_KEY,
                'Content-Length': '0',
            },
        }
    );

    const token = await response.text();
    res.json({ token });
}
```

## Other STT Providers

### AWS Transcribe

```javascript
import { TranscribeStreamingClient, StartStreamTranscriptionCommand } from '@aws-sdk/client-transcribe-streaming';

const client = new TranscribeStreamingClient({ region: 'us-east-1' });

// Stream audio to AWS Transcribe
const command = new StartStreamTranscriptionCommand({
    LanguageCode: 'en-US',
    MediaEncoding: 'pcm',
    MediaSampleRateHertz: 16000,
    AudioStream: audioStream,
});

const response = await client.send(command);
for await (const event of response.TranscriptResultStream) {
    const transcript = event.TranscriptEvent?.Transcript?.Results?.[0]?.Alternatives?.[0]?.Transcript;
    if (transcript) {
        uneeqInstance.chatPrompt(transcript, true);
    }
}
```

### Google Cloud Speech-to-Text

```javascript
import speech from '@google-cloud/speech';

const client = new speech.SpeechClient();

const request = {
    config: {
        encoding: 'LINEAR16',
        sampleRateHertz: 16000,
        languageCode: 'en-US',
    },
    audio: { content: audioBase64 },
};

const [response] = await client.recognize(request);
const transcript = response.results
    .map(result => result.alternatives[0].transcript)
    .join(' ');

uneeqInstance.chatPrompt(transcript, true);
```

## Summary

To use custom STT with UneeQ:

1. **Don't enable** UneeQ's built-in microphone (`enableMicrophone: false`)
2. **Capture audio** yourself using Web Audio API or MediaRecorder
3. **Send audio** to your STT service (Azure, AWS, Google, etc.)
4. **Send transcribed text** to UneeQ using `chatPrompt(text, true)`
5. **Handle DH speaking states** to mute/unmute your microphone

The key method is:
```javascript
uneeqInstance.chatPrompt(transcribedText, true);
```

This sends your custom-transcribed text to the UneeQ digital human for processing.
