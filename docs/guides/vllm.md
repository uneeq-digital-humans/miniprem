# vLLM LLM Integration

This guide covers the vLLM large language model (LLM) integration in the MiniPrem platform, which provides the natural language understanding capabilities.

## Overview

[vLLM](https://vllm.ai/) is a high-performance, open-source inference engine for large language models. In the MiniPrem platform, vLLM powers the conversational intelligence using Gemma3:4b, a state-of-the-art open-source language model.

## Accessing vLLM

- **API Endpoint**: http://localhost:8000/v1
- **Container Name**: `vllm`

## Default Model

MiniPrem comes pre-configured with:
- **Model**: `gemma-3-4b` (or your chosen HuggingFace-compatible model)
- **Context Length**: 8,192 tokens (model-dependent)
- **Parameters**: 4 billion (model-dependent)

## Direct Interaction with vLLM

### Using the OpenAI-Compatible API

You can interact with vLLM directly via its OpenAI-compatible API:

```bash
# Chat completion
curl -X POST http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-3-4b",
  "messages": [
    { "role": "user", "content": "What is artificial intelligence?" }
  ]
}'
```

## Further Reading

- [vLLM Official Documentation](https://vllm.readthedocs.io/en/latest/)
- [vLLM GitHub Repository](https://github.com/vllm-project/vllm) 