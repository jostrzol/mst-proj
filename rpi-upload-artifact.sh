#!/bin/sh

if test -z "$1"; then
    echo >&2 "Usage: $0 <file_path>"
    echo >&2 "Example: $0 artifacts/fast/1-blinky-c"
    exit 1
fi

FILE_PATH="$1"
REMOTE_HOST="mst.local"
REMOTE_PATH="$FILE_PATH"
REMOTE_DIR=$(dirname "$REMOTE_PATH")

if test ! -f "$FILE_PATH"; then
    echo >&2 "File '$FILE_PATH' not found"
    exit 1
fi

LOCAL_CHECKSUM=$(sha256sum "$FILE_PATH" | cut -d' ' -f1)

REMOTE_CHECKSUM=$(
    ssh "$REMOTE_HOST" "
            if test -f '$REMOTE_PATH'; then
                sha256sum '$REMOTE_PATH' | cut -d' ' -f1
            else 
                mkdir -p '$REMOTE_DIR'
            fi
        " 2>/dev/null
)

if test "$LOCAL_CHECKSUM" = "$REMOTE_CHECKSUM" && test -n "$REMOTE_CHECKSUM"; then
    echo >&2 "File already exists with same checksum, skipping upload"
    exit 0
fi

echo >&2 "> rsync -av \"$FILE_PATH\" \"$REMOTE_HOST:$REMOTE_PATH\""
rsync -av "$FILE_PATH" "$REMOTE_HOST:$REMOTE_PATH"

if test $? -eq 0; then
    echo >&2 "Upload completed successfully"
else
    echo >&2 "Upload failed"
    exit 1
fi
