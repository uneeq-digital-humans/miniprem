# Integración de vLLM LLM

Esta guía cubre la integración del modelo de lenguaje grande (LLM) vLLM en la plataforma MiniPrem, que proporciona las capacidades de comprensión del lenguaje natural.

## Descripción General

[vLLM](https://vllm.ai/) es un motor de inferencia de alto rendimiento y código abierto para modelos de lenguaje grandes. En la plataforma MiniPrem, vLLM impulsa la inteligencia conversacional usando Gemma3:4b, un modelo de lenguaje de código abierto de última generación.

## Acceso a vLLM

- **Endpoint de API**: http://localhost:8000/v1
- **Nombre del Contenedor**: `vllm`

## Modelo Predeterminado

MiniPrem viene preconfigurado con:
- **Modelo**: `gemma-3-4b` (o tu modelo compatible con HuggingFace elegido)
- **Longitud de Contexto**: 8,192 tokens (dependiente del modelo)
- **Parámetros**: 4 mil millones (dependiente del modelo)

## Interacción Directa con vLLM

### Usando la API Compatible con OpenAI

Puedes interactuar con vLLM directamente a través de su API compatible con OpenAI:

```bash
# Completado de chat
curl -X POST http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "gemma-3-4b",
  "messages": [
    { "role": "user", "content": "What is artificial intelligence?" }
  ]
}'
```

## Lectura Adicional

- [Documentación Oficial de vLLM](https://vllm.readthedocs.io/en/latest/)
- [Repositorio GitHub de vLLM](https://github.com/vllm-project/vllm) 