#!/bin/bash

# Test script for OpenAI-compatible streaming responses

echo "Testing streaming responses..."

# Test the streaming endpoint with a simple prompt
curl -v -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "grok-3",
    "messages": [
      {"role": "user", "content": "Count from 1 to 5 slowly, with a brief pause between each number."}
    ],
    "stream": true,
    "temperature": 0.7,
    "max_tokens": 100
  }'

echo -e "\n\nTesting completed."

# Optional: Test with a different example to verify consistent behavior
echo -e "\nTesting another streaming example..."
curl -v -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Write a haiku about programming."}
    ],
    "stream": true
  }'

echo -e "\n\nAll tests completed." 