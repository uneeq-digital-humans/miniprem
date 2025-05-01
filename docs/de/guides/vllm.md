# vLLM LLM Integration

Dieser Leitfaden behandelt die Integration von vLLM Large Language Model (LLM) in die MiniPrem-Plattform, die die Funktionen zum Verstehen natürlicher Sprache bereitstellt.

## Überblick

[vLLM](https://vllm.ai/) ist eine leistungsstarke Open-Source-Inferenzmaschine für große Sprachmodelle. In der MiniPrem-Plattform unterstützt vLLM die Konversationsintelligenz mit Gemma3:4b, einem hochmodernen Open-Source-Sprachmodell.

## Zugriff auf vLLM

- **API-Endpunkt**: http://localhost:8000/v1
- **Container-Name**: `vllm`

## Standardmodell

MiniPrem wird vorkonfiguriert mit:
- **Modell**: `gemma-3-4b` (oder ein HuggingFace-kompatibles Modell Ihrer Wahl)
- **Kontextlänge**: 8.192 Token (modellabhängig)
- **Parameter**: 4 Milliarden (modellabhängig)

## Direkte Interaktion mit vLLM

### Verwendung der OpenAI-kompatiblen API

Sie können mit vLLM direkt über seine OpenAI-kompatible API interagieren:

```bash
# Chat completion
curl -X POST http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-3-4b",
  "messages": [
    { "role": "user", "content": "What is artificial intelligence?" }
  ]
}'
```

## Weitere Lektüre

- [vLLM Offizielle Dokumentation](https://vllm.readthedocs.io/en/latest/)
- [vLLM GitHub Repository](https://github.com/vllm-project/vllm)