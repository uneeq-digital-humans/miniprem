#!/bin/bash

# Wait for Flowise to be ready
echo "Waiting for Flowise to be ready..."
until $(curl --output /dev/null --silent --head --fail http://flowise:3000/); do
    printf '.'
    sleep 5
done
echo "Flowise is up and running!"

# Create a chatflow with Anthropic integration
echo "Creating Chatflow with Anthropic integration..."
curl -X POST "http://flowise:3000/api/v1/chatflows" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Anthropic Claude Test",
    "description": "Test chatflow using Claude 3 Sonnet",
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
          "prompt": "You are Claude, a helpful AI assistant."
        }
      },
      {
        "width": 300,
        "height": 464,
        "id": "anthropic",
        "type": "ChatAnthropic",
        "position": {
          "x": 450,
          "y": 200
        },
        "data": {
          "anthropicApiKey": "${ANTHROPIC_API_KEY}",
          "modelName": "claude-3-sonnet-20240229",
          "temperature": 0.7,
          "maxTokens": 1024,
          "streaming": true,
          "debug": true
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
          "maxTokenLimit": 4000
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
        "source": "anthropic",
        "sourceHandle": "model",
        "target": "conversationChain",
        "targetHandle": "llm",
        "id": "anthropic-conversationChain"
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