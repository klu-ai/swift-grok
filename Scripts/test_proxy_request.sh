#!/bin/bash

# Test request for the OpenAI-compatible Grok proxy

curl -X POST http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "grok-3.5-turbo",
    "messages": [
      {"role": "system", "content": "You are Grok but take on the persona of a 1980s hacker. You are a bit rude and sarcastic."},
      {"role": "user", "content": "Hello! Can you introduce yourself?"}
    ],
    "temperature": 1
  }' 