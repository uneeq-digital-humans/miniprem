# Flowise Configuration Guide

Flowise provides a visual interface for creating and managing AI workflows. This guide will help you set up and use Flowise with vLLM integration.

## Accessing Flowise

- **URL**: http://localhost:3000
- **Default Credentials**:
  - Username: `user`
  - Password: `password`

## Flowise Concepts

- **Chatflows**: Visual representations of conversation workflows
- **Nodes**: Components that perform specific functions (prompts, models, memory, etc.)
- **Edges**: Connections between nodes that define how data flows
- **API**: RESTful endpoints to interact with your chatflows programmatically

## Creating a Chatflow with vLLM

### 1. Access Flowise UI

1. Open your browser and navigate to: http://localhost:3000
2. Log in with username `user` and password `password`

### 2. Create a New Chatflow

1. Click on "Chatflows" in the sidebar
2. Click the "+" button to create a new Chatflow
3. Name your Chatflow (e.g., "vLLM Gemma3 Chatflow")

### 3. Add and Configure Nodes

#### System Prompt Node

1. From the nodes panel, drag and drop a "System Prompt" node onto the canvas
2. Configure the node with:
   - Prompt: "You are a helpful assistant powered by Gemma3. Provide concise and accurate responses."

#### vLLM Node

1. From the nodes panel, drag and drop a "vLLM" or "OpenAI Compatible" node onto the canvas
2. Configure the node with:
   - Base URL: `http://vllm:8000/v1` (use the docker container name, not localhost)
   - Model: `gemma-3-4b`
   - Temperature: `0.7`
   - Max Tokens: `1000`
   - Leave other settings at default values

#### Buffer Memory Node

1. From the nodes panel, drag and drop a "Buffer Memory" node onto the canvas
2. Configure the node with:
   - Memory Key: `chat_history`
   - Return Messages: `true` (checked)
   - Max Token Limit: `2000`

#### Conversation Chain Node

1. From the nodes panel, drag and drop a "Conversation Chain" node onto the canvas
2. No additional configuration needed

#### Chat Trigger Node

1. From the nodes panel, drag and drop a "Chat Trigger" node onto the canvas
2. No additional configuration needed

### 4. Connect the Nodes

Connect the nodes with the following connections:

1. System Prompt → Conversation Chain (from "prompt" to "systemPrompt")
2. vLLM → Conversation Chain (from "model" to "llm")
3. Buffer Memory → Conversation Chain (from "memory" to "memory")
4. Conversation Chain → Chat Trigger (from "output" to "input")

### 5. Save and Test

1. Click the "Save" button at the top right
2. Click the "Chat" button to test your chatflow

## Using the Flowise API

You can interact with your Chatflow through the Flowise API.

### Authentication

Add the following header to your API requests:
```
  "Authorization: Bearer YOUR_DEFAULT_TOKEN_HERE"
```