# Guía de Configuración de Flowise

Flowise proporciona una interfaz visual para crear y gestionar flujos de trabajo de IA. Esta guía te ayudará a configurar y usar Flowise con integración de vLLM.

## Acceso a Flowise

- **URL**: http://localhost:3000
- **Credenciales Predeterminadas**:
  - Usuario: `user`
  - Contraseña: `password`

## Conceptos de Flowise

- **Chatflows**: Representaciones visuales de flujos de trabajo de conversación
- **Nodos**: Componentes que realizan funciones específicas (prompts, modelos, memoria, etc.)
- **Aristas**: Conexiones entre nodos que definen cómo fluyen los datos
- **API**: Endpoints RESTful para interactuar con tus chatflows mediante programación

## Crear un Chatflow con vLLM

### 1. Acceder a la Interfaz de Flowise

1. Abre tu navegador y navega a: http://localhost:3000
2. Inicia sesión con el usuario `user` y la contraseña `password`

### 2. Crear un Nuevo Chatflow

1. Haz clic en "Chatflows" en la barra lateral
2. Haz clic en el botón "+" para crear un nuevo Chatflow
3. Nombra tu Chatflow (por ejemplo, "Chatflow vLLM Gemma3")

### 3. Agregar y Configurar Nodos

#### Nodo de Prompt del Sistema

1. Desde el panel de nodos, arrastra y suelta un nodo "System Prompt" en el lienzo
2. Configura el nodo con:
   - Prompt: "Eres un asistente útil impulsado por Gemma3. Proporciona respuestas concisas y precisas."

#### Nodo vLLM

1. Desde el panel de nodos, arrastra y suelta un nodo "vLLM" o "OpenAI Compatible" en el lienzo
2. Configura el nodo con:
   - URL Base: `http://vllm:8000/v1` (usa el nombre del contenedor docker, no localhost)
   - Modelo: `gemma-3-4b`
   - Temperatura: `0.7`
   - Tokens Máximos: `1000`
   - Deja los demás ajustes en sus valores predeterminados

#### Nodo de Memoria Buffer

1. Desde el panel de nodos, arrastra y suelta un nodo "Buffer Memory" en el lienzo
2. Configura el nodo con:
   - Clave de Memoria: `chat_history`
   - Devolver Mensajes: `true` (marcado)
   - Límite Máximo de Tokens: `2000`

#### Nodo de Cadena de Conversación

1. Desde el panel de nodos, arrastra y suelta un nodo "Conversation Chain" en el lienzo
2. No se necesita configuración adicional

#### Nodo de Disparador de Chat

1. Desde el panel de nodos, arrastra y suelta un nodo "Chat Trigger" en el lienzo
2. No se necesita configuración adicional

### 4. Conectar los Nodos

Conecta los nodos con las siguientes conexiones:

1. System Prompt → Conversation Chain (de "prompt" a "systemPrompt")
2. vLLM → Conversation Chain (de "model" a "llm")
3. Buffer Memory → Conversation Chain (de "memory" a "memory")
4. Conversation Chain → Chat Trigger (de "output" a "input")

### 5. Guardar y Probar

1. Haz clic en el botón "Save" en la esquina superior derecha
2. Haz clic en el botón "Chat" para probar tu chatflow

## Usar la API de Flowise

Puedes interactuar con tu Chatflow a través de la API de Flowise.

### Autenticación

Agrega el siguiente encabezado a tus solicitudes de API:
```
  "Authorization: Bearer YOUR_DEFAULT_TOKEN_HERE"
```