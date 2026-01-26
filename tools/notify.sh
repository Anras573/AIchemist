#!/bin/bash
# Cross-platform notification script
# Usage: notify.sh "Title" "Message"

TITLE="${1:-Notification}"
MESSAGE="${2:-}"

case "$(uname -s)" in
  Linux*)
    notify-send "$TITLE" "$MESSAGE"
    ;;
  Darwin*)
    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\""
    ;;
  MINGW*|CYGWIN*|MSYS*)
    powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('$MESSAGE','$TITLE')"
    ;;
  *)
    echo "$TITLE: $MESSAGE"
    ;;
esac
