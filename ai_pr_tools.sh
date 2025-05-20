#!/bin/bash

aipr() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is not installed. Please install jq to continue." >&2
    echo "On macOS: brew install jq" >&2
    return 1
  fi

  local current_branch=$(git branch --show-current)
  echo "Comparing $current_branch with main..."

  local diff_output=$(git diff --no-color main..$current_branch)

  if [ -z "$diff_output" ]; then
    echo "No changes detected between $current_branch and main."
    return 0
  fi

  local prompt_text="In markdown, write a concise and clear pull request description. Structure the description into two main sections: Backend and Frontend. Within each section, group the changes by specific features or modules. Use bullet points and keep the language straightforward and informative. If there are no changes in one of the sections, omit it.

  At the top of the description, include a short summary (1-2 sentences) of what this pull request introduces or modifies.

  Here are the changes:
  $diff_output"

  local escaped_prompt=$(echo "$prompt_text" | jq -R -s 'tojson')

  local json_payload
  json_payload=$(printf '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 1000,
    "messages": [
      {
        "role": "user",
        "content": %s
      }
    ]
  }' "$escaped_prompt")

  echo "Sending to Claude API..."
  local response=$(
    curl -s -w "\nHTTP_STATUS_CODE:%{http_code}" https://api.anthropic.com/v1/messages \
      -H "Content-Type: application/json" \
      -H "x-api-key: $CLAUDE_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      --data-binary "$json_payload"
  )

  local body=$(echo "$response" | sed '$d')
  local http_status=$(echo "$response" | tail -n1 | sed 's/HTTP_STATUS_CODE://')

  if [ "$http_status" -ne 200 ]; then
    echo "Error: Claude API request failed with status $http_status" >&2
    echo "Response:" >&2
    echo "$body" >&2
    # Optionally print the raw payload for debugging
    # echo "Sent Payload:" >&2
    # echo "$json_payload" >&2
    return 1
  fi

  local result_content=$(echo "$body" | sed -n 's/.*"content":\[{"type":"text","text":"\(.*\)"}],"stop.*/\1/p' | sed 's/\\"/"/g' | sed 's/\\n/\n/g')

  if [ -z "$result_content" ]; then
    echo "First extraction attempt failed, trying alternative method..." >&2

    local tmp_file=$(mktemp)
    echo "$body" >"$tmp_file"

    local start_pos=$(grep -b -o '"text":"' "$tmp_file" | head -1 | cut -d: -f1)
    local end_pos=$(grep -b -o '"}],"stop' "$tmp_file" | head -1 | cut -d: -f1)

    if [ -n "$start_pos" ] && [ -n "$end_pos" ]; then
      # Add the length of the "text":" pattern to the start position
      start_pos=$((start_pos + 8))

      local content_length=$((end_pos - start_pos))

      local extracted_content=$(dd if="$tmp_file" bs=1 skip="$start_pos" count="$content_length" 2>/dev/null)

      result_content=$(echo "$extracted_content" | sed 's/\\"/"/g' | sed 's/\\n/\n/g')

      echo "Binary extraction succeeded." >&2
    else
      echo "Binary extraction failed." >&2
      echo "Raw Response Body:" >&2
      echo "$body" >&2
      rm -f "$tmp_file"
      return 1
    fi

    rm -f "$tmp_file"
  fi

  if [ -z "$result_content" ]; then
    echo "All extraction methods failed." >&2
    echo "Raw Response Body:" >&2
    echo "$body" >&2
    return 1
  fi

  echo "$result_content" | pbcopy

  echo "Generated PR description (copied to clipboard):"
  echo "$result_content"
}
