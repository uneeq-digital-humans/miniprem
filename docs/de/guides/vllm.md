# vLLM LLM Integration

Dieser Leitfaden behandelt die Integration des vLLM Large Language Model (LLM) in die MiniPrem-Plattform, die die Funktionen zum Verstehen natürlicher Sprache bereitstellt.

## Überblick

[vLLM](https://vllm.ai/) ist eine leistungsstarke Open-Source-Inferenzmaschine für große Sprachmodelle. In der MiniPrem-Plattform nutzt vLLM Mistral-7B-Instruct-v0.3, ein hochmodernes Open-Source-Sprachmodell, das für Anweisungsbefolgung und Chat optimiert ist.

## Voraussetzungen

- HuggingFace Konto
- Akzeptierte Nutzungsbedingungen für das Mistral-Modell
- HuggingFace API-Token mit Leserechten

## Ersteinrichtung

Während der Installation wird das System:
1. Sie durch die Erstellung/Anmeldung eines HuggingFace-Kontos führen
2. Ihnen bei der Akzeptanz der Mistral-Modell-Bedingungen helfen
3. Sie bei der Erstellung und Konfiguration eines HuggingFace API-Tokens unterstützen
4. Das Mistral-Modell herunterladen und konfigurieren

## Zugriff auf vLLM

- **API-Endpunkt**: http://localhost:8000/v1
- **Container-Name**: `vllm`
- **Modell-Pfad**: `mistralai/Mistral-7B-Instruct-v0.3`

## Standardmodell

MiniPrem ist vorkonfiguriert mit:
- **Modell**: `Mistral-7B-Instruct-v0.3`
- **Kontextlänge**: 8.192 Token
- **Parameter**: 7 Milliarden
- **Optimierungen**: Vorkonfiguriert für effiziente GPU-Inferenz
## Direkte Interaktion mit vLLM

### Verwendung der OpenAI-kompatiblen API

Sie können direkt über die OpenAI-kompatible API mit vLLM interagieren:

```bash
# Chat-Vervollständigung
curl -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "mistralai/Mistral-7B-Instruct-v0.3",
    "messages": [
        {"role": "system", "content": "Sie sind ein hilfreicher KI-Assistent."},
        {"role": "user", "content": "Was ist künstliche Intelligenz?"}
    ]
}'
```

## Weitere Lektüre

- [vLLM Offizielle Dokumentation](https://vllm.readthedocs.io/en/latest/)
- [vLLM GitHub Repository](https://github.com/vllm-project/vllm)
