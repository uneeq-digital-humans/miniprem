# Ollama LLM Integration

This guide covers the Ollama large language model (LLM) integration in the MiniPrem platform, which provides the natural language understanding capabilities.

## Overview

[Ollama](https://ollama.ai/) is an open-source framework for running large language models locally. In the MiniPrem platform, Ollama powers the conversational intelligence using Gemma3:4b, a state-of-the-art open-source language model.

## Accessing Ollama

- **API Endpoint**: http://localhost:11434
- **Container Name**: `ollama`

## Default Model

MiniPrem comes pre-configured with:
- **Model**: `Gemma3:4b`
- **Approx. Size**: 8GB (compressed to ~4GB)
- **Context Length**: 8,192 tokens
- **Parameters**: 8 billion

## Direct Interaction with Ollama

### Using the API

You can interact with Ollama directly via its API:

```bash
# Generate a completion
curl -X POST http://localhost:11434/api/generate -d '{
  "model": "gemma3:4b",
  "prompt": "What is artificial intelligence?",
  "stream": false
}'

# Chat completion
curl -X POST http://localhost:11434/api/chat -d '{
  "model": "gemma3:4b",
  "messages": [
    { "role": "user", "content": "What is artificial intelligence?" }
  ]
}'
```