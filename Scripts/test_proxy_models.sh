#!/bin/bash

# Test request for the OpenAI-compatible models endpoint

# Test the /v1/models endpoint
echo "Testing /v1/models..."
curl -s http://127.0.0.1:8080/v1/models | jq .

# Also test the /models endpoint
echo -e "\nTesting /models..."
curl -s http://127.0.0.1:8080/models | jq . 