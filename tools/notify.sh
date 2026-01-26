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
    powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('$SAFE_MESSAGE','$SAFE_TITLE')"
    ;;
  *)
    echo "$SAFE_TITLE: $SAFE_MESSAGE"
    ;;
esac
