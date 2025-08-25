#!/bin/sh

idf_py_path="$(which idf.py >/dev/null 2>&1)"
if test "$?" -eq 0; then
  echo "$(realpath "$(dirname "$idf_py_path")/..")"
  exit
fi

if test -n "$IDF_PATH"; then
  echo "$IDF_PATH"
  exit
fi

for dir in "$HOME/esp/esp-idf" "./.esp-idf"; do
  export_path="$dir/export.sh"
  if test -f "$export_path"; then
    echo $(realpath "$dir")
    exit
  fi
done

exit 1
