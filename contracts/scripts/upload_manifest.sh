#!/bin/bash

# Extract ACTIONS_NAME from manifest.json
export ACTIONS_NAME=$(cat ./target/dev/manifest.json | jq -r '.contracts | first | .name' | sed 's/_actions$//')

# Define default URL and JSON file path
DEFAULT_URL="http://localhost:3000/manifests/"
JSON_FILE="./target/dev/manifest.json"

# Use the first argument as the URL if provided, otherwise use the default URL
URL=${1:-$DEFAULT_URL}

# Append ACTIONS_NAME to the URL
URL+="$ACTIONS_NAME"

# Send a POST request to the URL with the contents of the JSON file
echo "Uploading $JSON_FILE to $URL"
curl -X POST -H "Content-Type: application/json" -d @"$JSON_FILE" "$URL"
