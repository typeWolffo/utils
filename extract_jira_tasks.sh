#!/bin/zsh

extract_pr_number() {
  local commit_msg="$1"
  if echo "$commit_msg" | grep -q "(#[0-9]\+)"; then
    # Format like "fix: something (#123)"
    echo "$commit_msg" | grep -o "(#[0-9]\+)" | grep -o "[0-9]\+"
  elif echo "$commit_msg" | grep -q "Merge pull request #[0-9]\+"; then
    # Format like "Merge pull request #123"
    echo "$commit_msg" | grep -o "pull request #[0-9]\+" | grep -o "[0-9]\+"
  elif echo "$commit_msg" | grep -q "#[0-9]\+"; then
    # Regular hashtag #123
    echo "$commit_msg" | grep -o "#[0-9]\+" | grep -o "[0-9]\+"
  else
    # Try to catch just the number in parentheses at the end of message
    echo "$commit_msg" | grep -o "([0-9]\+)" | grep -o "[0-9]\+"
  fi
}

extract_jira_keys() {
  local text="$1"
  echo "$text" | grep -o 'ZAK-[0-9]\+' | sort -u
}

get_repo_info() {
  local REPO_URL=$(git config --get remote.origin.url)
  local REPO_OWNER=""
  local REPO_NAME=""

  if [[ "$REPO_URL" =~ github.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
    REPO_OWNER=${match[1]}
    REPO_NAME=${match[2]%.git}
  else
    echo "Could not determine repository owner and name, using defaults: $REPO_OWNER/$REPO_NAME" >&2
    return 1
  fi

  echo "$REPO_OWNER/$REPO_NAME"
}

process_commits() {
  local commit_from_ref="$1"
  local commit_to_ref="$2"
  local prs_file="$3"
  local jira_file="$4"
  local commits_file="$5"

  git log "$commit_from_ref".."$commit_to_ref" --pretty=format:"%h %s" >"$commits_file"

  while IFS= read -r commit; do
    local commit_hash=$(echo "$commit" | cut -d' ' -f1)
    local commit_msg=$(echo "$commit" | cut -d' ' -f2-)

    local pr_nums=$(extract_pr_number "$commit_msg")
    if [ -n "$pr_nums" ]; then
      for pr_num in $pr_nums; do
        echo "$pr_num" >>"$prs_file"
      done
    else
      echo "  No PR number found"
    fi

    local jira_keys_commit=$(extract_jira_keys "$commit_msg")
    if [ -n "$jira_keys_commit" ]; then
      echo "$jira_keys_commit" >>"$jira_file"
    fi
  done <"$commits_file"

  sort -u "$prs_file" -o "$prs_file"
}

process_pull_requests() {
  local prs_file="$1"
  local repo_owner="$2"
  local repo_name="$3"
  local pr_details_file="$4"
  local jira_file="$5"

  while IFS= read -r pr_num; do
    if ! gh pr view "$pr_num" --repo "$repo_owner/$repo_name" --json title,body >"$pr_details_file" 2>/dev/null; then
      echo "  Could not fetch PR #$pr_num" >&2
      continue
    fi

    local PR_TITLE=$(jq -r '.title' <"$pr_details_file")
    local PR_BODY=$(jq -r '.body' <"$pr_details_file")

    local jira_keys_title=$(extract_jira_keys "$PR_TITLE")
    local jira_keys_body=$(extract_jira_keys "$PR_BODY")

    local jira_urls=$(echo "$PR_BODY" | grep -o 'https://selleolabs.atlassian.net/browse/ZAK-[0-9]\+' | sort -u)

    if [ -n "$jira_urls" ]; then
      while IFS= read -r url; do
        local jira_key=$(echo "$url" | grep -o 'ZAK-[0-9]\+')
        echo "$jira_key" >>"$jira_file"
      done < <(echo "$jira_urls")
    fi

    if [ -n "$jira_keys_title" ]; then
      echo "$jira_keys_title" >>"$jira_file"
    fi

    if [ -n "$jira_keys_body" ]; then
      echo "$jira_keys_body" >>"$jira_file"
    fi

    local markdown_refs=$(echo "$PR_BODY" | grep -o '\[ZAK-[0-9]\]\+]:')
    if [ -n "$markdown_refs" ]; then
      while IFS= read -r ref; do
        local jira_key=$(echo "$ref" | grep -o 'ZAK-[0-9]\+')
        echo "$jira_key" >>"$jira_file"
      done < <(echo "$markdown_refs")
    fi

  done <"$prs_file"
}

generate_markdown_report() {
  local commit_from_ref="$1"
  local commit_to_ref="$2"
  local commits_file="$3"
  local prs_file="$4"
  local jira_file="$5"
  local markdown_file="$6"
  local repo_owner="$7"
  local repo_name="$8"

  echo "# Deployment summary: $commit_from_ref..$commit_to_ref" >"$markdown_file"
  echo "" >>"$markdown_file"
  echo "## Commits and related tasks" >>"$markdown_file"
  echo "" >>"$markdown_file"

  while IFS= read -r commit; do
    local commit_hash=$(echo "$commit" | cut -d' ' -f1)
    local commit_msg=$(echo "$commit" | cut -d' ' -f2-)

    local jira_keys_commit_report=$(extract_jira_keys "$commit_msg")

    if [ -n "$jira_keys_commit_report" ]; then
      local MARKDOWN_LINE="- \`$commit_hash\`: $commit_msg"

      local JIRA_LINKS_STRING_ACCUMULATOR=""
      local IS_FIRST_JIRA_LINK=true
      for jira_key_raw in $(echo "$jira_keys_commit_report"); do
        local current_jira_key=$(echo "$jira_key_raw" | tr -d '\r')
        if [ -z "$current_jira_key" ]; then continue; fi

        markdown_link_for_current_jira_task=$(printf "[%s](https://selleolabs.atlassian.net/browse/%s)" "$current_jira_key" "$current_jira_key")
        echo -n "" >&2

        if [[ "$IS_FIRST_JIRA_LINK" == "true" ]]; then
          IS_FIRST_JIRA_LINK=false
          JIRA_LINKS_STRING_ACCUMULATOR="$markdown_link_for_current_jira_task"
        else
          JIRA_LINKS_STRING_ACCUMULATOR="$JIRA_LINKS_STRING_ACCUMULATOR, $markdown_link_for_current_jira_task"
        fi
      done

      if [ -n "$JIRA_LINKS_STRING_ACCUMULATOR" ]; then
        MARKDOWN_LINE="$MARKDOWN_LINE $JIRA_LINKS_STRING_ACCUMULATOR"
      fi

      echo "$MARKDOWN_LINE" >>"$markdown_file"
    else
      echo "- \`$commit_hash\`: $commit_msg" >>"$markdown_file"
    fi
  done <"$commits_file"

  echo "" >>"$markdown_file"
  echo "## Pull Requests" >>"$markdown_file"
  echo "" >>"$markdown_file"

  while IFS= read -r pr_num; do
    if [ -n "$pr_num" ]; then
      echo "- [#$pr_num](https://github.com/$repo_owner/$repo_name/pull/$pr_num)" >>"$markdown_file"
    fi
  done <"$prs_file"

  echo "" >>"$markdown_file"
  echo "## Jira Tasks" >>"$markdown_file"
  echo "" >>"$markdown_file"

  sort -u "$jira_file" -o "$jira_file"

  while IFS= read -r task; do
    if [ -n "$task" ]; then
      echo "- [$task](https://selleolabs.atlassian.net/browse/$task)" >>"$markdown_file"
    fi
  done <"$jira_file"
}

deploy_report() {
  if ! command -v gh &>/dev/null; then
    echo "GitHub CLI (gh) is not installed. Please install it to fetch PR descriptions."
    echo "brew install gh   # on macOS"
    echo "Then authenticate with: gh auth login"
    return 1
  fi

  if [ "$#" -lt 2 ]; then
    echo "Usage: extract_jira_tasks <from_commit> <to_commit>"
    echo "Example: extract_jira_tasks 590975ca c97ce7f9"
    return 1
  else
    local COMMIT_FROM="$1"
    local COMMIT_TO="$2"
  fi

  local REPO_INFO=$(get_repo_info)
  local REPO_OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
  local REPO_NAME=$(echo "$REPO_INFO" | cut -d'/' -f2)

  local TEMP_COMMITS=$(mktemp)
  local TEMP_PRS=$(mktemp)
  local TEMP_JIRA=$(mktemp)
  local TEMP_MARKDOWN=$(mktemp)
  local TEMP_PR_DETAILS=$(mktemp)

  echo "# Deployment summary: $COMMIT_FROM..$COMMIT_TO" >$TEMP_MARKDOWN
  echo "" >>$TEMP_MARKDOWN
  echo "## Commits and related tasks" >>$TEMP_MARKDOWN
  echo "" >>$TEMP_MARKDOWN

  process_commits "$COMMIT_FROM" "$COMMIT_TO" "$TEMP_PRS" "$TEMP_JIRA" "$TEMP_COMMITS"
  process_pull_requests "$TEMP_PRS" "$REPO_OWNER" "$REPO_NAME" "$TEMP_PR_DETAILS" "$TEMP_JIRA"

  generate_markdown_report "$COMMIT_FROM" "$COMMIT_TO" "$TEMP_COMMITS" "$TEMP_PRS" "$TEMP_JIRA" "$TEMP_MARKDOWN" "$REPO_OWNER" "$REPO_NAME"

  cat $TEMP_MARKDOWN

  rm $TEMP_COMMITS $TEMP_PRS $TEMP_JIRA $TEMP_MARKDOWN $TEMP_PR_DETAILS

  echo -e "\nFinished analysis of range $COMMIT_FROM..$COMMIT_TO"
}

alias depr='deploy_report'

echo "Function 'deploy_report' has been loaded."
