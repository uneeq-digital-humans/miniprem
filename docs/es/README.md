# Plataforma MiniPrem

> Una plataforma integral de humano digital con integración LLM, animación facial en tiempo real y capacidades de monitoreo.

## Descripción General

MiniPrem es una plataforma integrada que combina una interfaz de humano digital (Renny) con capacidades LLM (vLLM), automatización de flujos de trabajo (Flowise) y herramientas completas de monitoreo (Prometheus + Grafana). Esta configuración permite implementar y gestionar interacciones avanzadas de IA a través de una interfaz humana virtual.

## Características

- **Interfaz de Humano Digital**: Impulsada por Renny, con animación facial en tiempo real
- **Integración LLM**: vLLM ejecutando Gemma3 para comprensión del lenguaje natural
- **Automatización de Flujos de Trabajo**: Flowise para construir y gestionar flujos de trabajo de IA
- **Métricas y Monitoreo**: Prometheus y Grafana para seguimiento del rendimiento en tiempo real
- **Gestión de Colas**: Redis para procesamiento confiable de mensajes
- **RIME AI**: Texto a voz de alta calidad a través de una API simple

## Inicio Rápido

### Requisitos Previos

- Docker y Docker Compose
- GPU NVIDIA con controladores apropiados
- Ubuntu Linux (recomendado)
- Credenciales requeridas de UneeQ (dirección de plataforma, clave API, ID de inquilino)
- Credenciales del servicio Azure Speech (región y clave API)

### Instalación

Para instrucciones completas de instalación, consulte nuestra [Guía de Primeros Pasos](guides/getting-started.md).

## Componentes de la Plataforma

MiniPrem incluye los siguientes componentes:

- **Renny**: Interfaz de humano digital con animación facial en tiempo real
- **vLLM**: Servicio de Modelo de Lenguaje Grande con Gemma3
- **Flowise**: Constructor visual de flujos de trabajo para aplicaciones de IA
- **Prometheus y Grafana**: Monitoreo y paneles en tiempo real
- **Redis**: Cola de mensajes para procesamiento confiable
- **RIME**: Motor de texto a voz de alta calidad

## Siguientes Pasos

- [Primeros Pasos](guides/getting-started.md): Instalación y configuración básica
- [Descripción de Servicios](guides/services.md): Detalles de cada componente
- [Solución de Problemas](troubleshooting.md): Soluciones a problemas comunes