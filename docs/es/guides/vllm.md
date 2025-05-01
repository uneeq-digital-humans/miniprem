# Integración de vLLM LLM

Esta guía cubre la integración del modelo de lenguaje grande (LLM) vLLM en la plataforma MiniPrem, que proporciona las capacidades de comprensión del lenguaje natural.

## Descripción General

[vLLM](https://vllm.ai/) es un motor de inferencia de código abierto de alto rendimiento para modelos de lenguaje grandes. En la plataforma MiniPrem, vLLM impulsa la inteligencia conversacional utilizando Mistral-7B-Instruct-v0.3, un modelo de lenguaje de código abierto de última generación optimizado para seguir instrucciones y chatear.
## Requisitos Previos

- Cuenta de HuggingFace
- Términos aceptados para el uso del modelo Mistral
- Token de API de HuggingFace con permisos de lectura

## Configuración Inicial

Durante la instalación, el sistema:
1. Te guiará a través de la creación/inicio de sesión de una cuenta HuggingFace
2. Te ayudará a aceptar los términos del modelo Mistral
3. Te asistirá en la creación y configuración de un token de API de HuggingFace
4. Descargará y configurará el modelo Mistral

## Acceso a vLLM

- **Punto Final de API**: http://localhost:8000/v1
- **Nombre del Contenedor**: `vllm`
- **Ruta del Modelo**: `facebook/opt-125m`

## Modelo Predeterminado

MiniPrem viene preconfigurado con:
- **Modelo**: `Mistral-7B-Instruct-v0.3`
- **Longitud de Contexto**: 8,192 tokens
- **Parámetros**: 7 mil millones
- **Optimizaciones**: Preconfigurado para inferencia eficiente en GPU

## Interacción Directa con vLLM

### Uso de la API Compatible con OpenAI

Puedes interactuar con vLLM directamente a través de su API compatible con OpenAI:

```bash
# Completado de chat
curl -X POST http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "facebook/opt-125m",
  "messages": [
        {"role": "system", "content": "Eres un asistente de IA servicial."},
      {"role": "user", "content": "¿Qué es la inteligencia artificial?"}
  ]
}'
```

## Lectura Adicional

- [Documentación Oficial de vLLM](https://vllm.readthedocs.io/en/latest/)
- [Repositorio GitHub de vLLM](https://github.com/vllm-project/vllm) 
