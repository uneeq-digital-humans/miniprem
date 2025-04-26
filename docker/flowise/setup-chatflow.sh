#!/bin/bash

# Wait for Flowise to be ready
echo "Waiting for Flowise to be ready..."
until $(curl --output /dev/null --silent --head --fail http://flowise:3000/); do
    printf '.'
    sleep 5
done
echo "Flowise is up and running!"

# Create a chatflow with Ollama integration
echo "Creating Chatflow with Ollama integration..."
curl -X POST "http://flowise:3000/api/v1/chatflows" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Ollama Gemma3 Chatflow",
    "description": "Chatflow using Gemma3:4b via Ollama with Buffer Memory",
    "chatflow": {
    "nodes": [
      {
          "width": 300,
          "height": 262,
        "id": "systemPrompt",
        "type": "SystemPrompt",
        "position": {
          "x": 150,
          "y": 100
        },
        "data": {
            "prompt": "You are a helpful assistant powered by Gemma3. Provide concise and accurate responses."
        }
      },
      {
          "width": 300,
          "height": 464,
        "id": "llmOllama",
          "type": "OllamaLocal",
        "position": {
          "x": 450,
          "y": 200
        },
        "data": {
            "baseUrl": "http://ollama:11434",
          "model": "Gemma3:4b",
          "temperature": 0.7,
            "topP": 0.9,
            "topK": 50,
            "maxTokens": 1000
        }
      },
      {
          "width": 300,
          "height": 367,
        "id": "conversationChain",
        "type": "ConversationChain",
        "position": {
          "x": 750,
          "y": 100
        },
        "data": {}
      },
      {
          "width": 300,
          "height": 334,
        "id": "bufferMemory",
        "type": "BufferMemory",
        "position": {
          "x": 450,
          "y": 400
        },
        "data": {
          "memoryKey": "chat_history",
          "returnMessages": true,
            "inputKey": "input",
            "outputKey": "output",
          "maxTokenLimit": 2000
        }
      },
      {
          "width": 300,
          "height": 418,
        "id": "chatTrigger",
        "type": "ChatTrigger",
        "position": {
          "x": 1050,
          "y": 200
        },
          "data": {
            "inputQuestion": "",
            "outputAnswer": "",
            "chatHistory": ""
      }
        }
    ],
    "edges": [
      {
        "source": "systemPrompt",
          "sourceHandle": "prompt",
        "target": "conversationChain",
          "targetHandle": "systemPrompt",
          "id": "systemPrompt-conversationChain"
      },
      {
        "source": "llmOllama",
          "sourceHandle": "model",
        "target": "conversationChain",
          "targetHandle": "llm",
          "id": "llmOllama-conversationChain"
      },
      {
        "source": "bufferMemory",
          "sourceHandle": "memory",
        "target": "conversationChain",
          "targetHandle": "memory",
          "id": "bufferMemory-conversationChain"
      },
      {
        "source": "conversationChain",
        "sourceHandle": "output",
        "target": "chatTrigger",
          "targetHandle": "input",
          "id": "conversationChain-chatTrigger"
      }
    ]
    }
  }'

echo "Chatflow setup complete!"