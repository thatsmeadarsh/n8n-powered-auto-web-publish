#!/bin/bash
# watch-and-publish.sh
# Watches for new .md files in Hugo content/posts/, commits to the Hugo repo
# (triggering GitHub Actions for build + deploy), and notifies n8n for LinkedIn posting.

set -euo pipefail

# --- Load Config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.env not found at $CONFIG_FILE"
  echo "Copy config.sample.env to config.env and update the values."
  exit 1
fi

source "$CONFIG_FILE"

# --- Setup ---
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/watcher.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting watcher on $POSTS_DIR"

# --- Watch Loop ---
fswatch -0 --event Created "$POSTS_DIR" | while read -d '' file; do
  # Only process .md files
  [[ "$file" != *.md ]] && continue

  # Wait briefly for file to finish writing
  sleep 2

  FILENAME=$(basename "$file")
  SLUG="${FILENAME%.md}"

  log "New post detected: $FILENAME"

  # Step 1: Commit and push new post to Hugo repo (triggers GitHub Actions)
  log "Committing to Hugo repo..."
  cd "$HUGO_DIR"
  git add "content/posts/$FILENAME"

  if git diff --cached --quiet; then
    log "Post already committed, skipping"
  else
    git commit -m "Add post: $SLUG"
    git push origin main
    log "Pushed to Hugo repo — GitHub Actions will build and deploy"
  fi

  # Step 2: Send file content to n8n webhook for LinkedIn posting
  log "Triggering n8n webhook..."
  FILE_CONTENT=$(cat "$file")

  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg fileName "$FILENAME" \
      --arg slug "$SLUG" \
      --arg content "$FILE_CONTENT" \
      --arg siteUrl "$SITE_BASE_URL" \
      '{fileName: $fileName, slug: $slug, fileContent: $content, siteBaseUrl: $siteUrl}')")

  if [ "$HTTP_STATUS" -eq 200 ]; then
    log "n8n webhook triggered successfully"
  else
    log "WARNING: n8n webhook returned HTTP $HTTP_STATUS"
  fi

  log "Done processing $FILENAME"
  log "---"
done
