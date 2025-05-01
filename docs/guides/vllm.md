# vLLM LLM Integration

This guide covers the vLLM large language model (LLM) integration in the MiniPrem platform, which provides the natural language understanding capabilities.

## Overview

[vLLM](https://vllm.ai/) is a high-performance, open-source inference engine for large language models. In the MiniPrem platform, vLLM powers conversational intelligence using Mistral-7B-Instruct-v0.3, a state-of-the-art open-source language model optimized for instruction following and chat.

## Prerequisites

- HuggingFace account
- Accepted terms for Mistral model use
- HuggingFace API token with read permissions

## Initial Setup

During installation, the system will:
1. Guide you through creating/logging into a HuggingFace account
2. Help you accept the Mistral model terms
3. Assist in creating and configuring a HuggingFace API token
4. Download and configure the Mistral model

## Accessing vLLM

- **API Endpoint**: http://localhost:8000/v1
- **Container Name**: `vllm`
- **Model Path**: `mistralai/Mistral-7B-Instruct-v0.3`

## Default Model

MiniPrem comes pre-configured with:
- **Model**: `Mistral-7B-Instruct-v0.3`
- **Context Length**: 8,192 tokens
- **Parameters**: 7 billion
- **Optimizations**: Pre-configured for efficient GPU inference

## Direct Interaction with vLLM

### Using the OpenAI-Compatible API

You can interact with vLLM directly via its OpenAI-compatible API:

```bash
# Chat completion
curl -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mistralai/Mistral-7B-Instruct-v0.3",
  "messages": [
      {"role": "system", "content": "You are a helpful AI assistant."},
      {"role": "user", "content": "What is artificial intelligence?"}
  ]
}'
```

## Further Reading

- [vLLM Official Documentation](https://vllm.readthedocs.io/en/latest/)
- [vLLM GitHub Repository](https://github.com/vllm-project/vllm) 