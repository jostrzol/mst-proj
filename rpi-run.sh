#!/bin/sh

if test -z "$1"; then
    echo >&2 "Usage: $0 <file_path>"
    echo >&2 "Example: $0 artifacts/fast/1-blinky-c"
    exit 1
fi

SCRIPT_DIR=$(dirname $0)
FILE_PATH="$1"
REMOTE_HOST="mst.local"

"$SCRIPT_DIR/rpi-upload-artifact.sh" "$FILE_PATH" || exit 1

echo >&2 "> ssh -t \"$REMOTE_HOST\" \"sudo $FILE_PATH\""
ssh -t "$REMOTE_HOST" "sudo $FILE_PATH"
if test "$?" -ne 0; then
    echo >&2 "Could not connect to $REMOTE_HOST"
    exit 1
fi
