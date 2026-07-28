#!/usr/bin/env bash
# Cross-platform notification script
# Usage: notify.sh "Title" "Message"

TITLE="${1:-Notification}"
MESSAGE="${2:-}"

# Sanitize inputs to prevent command injection
# Removes backticks, dollar signs, and escapes single quotes
sanitize() {
    local input="$1"
    printf '%s' "$input" | tr -d '`$' | sed "s/'/'\\\\''/g"
}

SAFE_TITLE=$(sanitize "$TITLE")
SAFE_MESSAGE=$(sanitize "$MESSAGE")

case "$(uname -s)" in
  Linux*)
    if command -v notify-send &> /dev/null; then
        notify-send "$SAFE_TITLE" "$SAFE_MESSAGE"
    else
        echo "$SAFE_TITLE: $SAFE_MESSAGE"
        echo "Warning: notify-send not found. Install libnotify-bin for desktop notifications." >&2
    fi
    ;;
  Darwin*)
    osascript -e "display notification \"$SAFE_MESSAGE\" with title \"$SAFE_TITLE\""
    ;;
  MINGW*|CYGWIN*|MSYS*)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Backgrounded + detached so this hook returns immediately instead of
    # blocking on the notification (a modal MessageBox previously stalled
    # the whole session until a human clicked OK).
    (powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden \
        -File "$SCRIPT_DIR/notify-windows.ps1" \
        -Title "$SAFE_TITLE" -Message "$SAFE_MESSAGE" \
        > /dev/null 2>&1 &)
    ;;
  *)
    echo "$SAFE_TITLE: $SAFE_MESSAGE"
    ;;
esac
