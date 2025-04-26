# Flowise Chatflow Setup Instructions

After starting the Docker containers with `docker compose -f docker-compose.updated.yml up -d`, follow these steps to set up the Chatflow in Flowise:

## Access Flowise UI

1. Open your browser and navigate to: http://localhost:3000

## Create a New Chatflow

1. Click on "Chatflows" in the sidebar
2. Click the "+" button to create a new Chatflow
3. Name your Chatflow (e.g., "Ollama Gemma3 Chatflow")

## Add and Configure Nodes

### 1. Add System Prompt Node

1. From the nodes panel, drag and drop a "System Prompt" node onto the canvas
2. Configure the node with:
   - Prompt: "You are a helpful assistant powered by Gemma3. Provide concise and accurate responses."

### 2. Add Ollama Node

1. From the nodes panel, drag and drop an "Ollama" node onto the canvas
2. Configure the node with:
   - Base URL: `http://ollama:11434` (use the docker container name, not localhost)
   - Model: `Gemma3:4b`
   - Temperature: `0.7`
   - Max Tokens: `1000`
   - Leave other settings at default values

### 3. Add Buffer Memory Node

1. From the nodes panel, drag and drop a "Buffer Memory" node onto the canvas
2. Configure the node with:
   - Memory Key: `chat_history`
   - Return Messages: `true` (checked)
   - Max Token Limit: `2000`

### 4. Add Conversation Chain Node

1. From the nodes panel, drag and drop a "Conversation Chain" node onto the canvas
2. No additional configuration needed

### 5. Add Chat Trigger Node

1. From the nodes panel, drag and drop a "Chat Trigger" node onto the canvas
2. No additional configuration needed

## Connect the Nodes

Connect the nodes with the following connections:

1. System Prompt → Conversation Chain (from "prompt" to "systemPrompt")
2. Ollama → Conversation Chain (from "model" to "llm")
3. Buffer Memory → Conversation Chain (from "memory" to "memory")
4. Conversation Chain → Chat Trigger (from "output" to "input")

## Save and Test

1. Click the "Save" button at the top right
2. Click the "Chat" button to test your chatflow

## Using the API

You can interact with your Chatflow through the Flowise API. The endpoint will be:

```
POST http://localhost:3000/api/v1/prediction/{CHATFLOW_ID}
```

With the following JSON body:
```json
{
  "question": "Your question here",
  "history": []
}
```

For subsequent requests, include the history from previous responses.