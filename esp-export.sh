#!/bin/sh

quiet=false
do_export=true

for arg in "$@"; do
  case "$arg" in
    --quiet) quiet=true;;
    --find-only) do_export=false;;
    *) echo >&2 "Unrecognized option: '$arg'"; exit 1
  esac
done

if which idf.py >/dev/null 2>&1; then
  test "$quiet" == false && >&2 "esp-idf already exported"
  exit 0
fi

if test -n "$IDF_PATH"; then
  test "$quiet" == false && echo >&2 "esp-idf path declared in variable IDF_PATH=$IDF_PATH"
  export_path="$IDF_PATH/export.sh"

  if test "$do_export" == true; then
    test "$quiet" == false && echo >&2 "sourcing $export_path"
    
    . "$export_path"
  fi
  exit 0
fi

for dir in "$HOME/esp/esp-idf" "./.esp-idf"; do
  export_path="$dir/export.sh"
  if test -f "$export_path"; then
    test "$quiet" == false && echo >&2 "esp-idf found at $dir"

    if test "$do_export" == true; then
      test "$quiet" == false && echo >&2 "exporting IDF_PATH"
      export IDF_PATH="$dir"

      test "$quiet" == false && echo >&2 "sourcing $export_path"
      . "$export_path"
    fi
    exit 0
  fi
done

test "$quiet" == false && echo >&2 "esp-idf not found, install required"
exit 1

# if which idf.py >/dev/null 2>&1; then
#   test "$quiet" == false && >&2 "esp-idf already exported"
#   exit 0
# fi
#
# esp_idf_path="$(sh esp-idf-path.sh)"
#
# if test "$?" -eq 0; then
#   echo >&2 "esp-idf found at $esp_idf_path"
#   export_path="$esp_idf_path/export.sh"
#
#   test "$quiet" == false && echo >&2 "sourcing $export_path"
#   . "$export_path"
#   exit 0
# fi
#
# test "$quiet" == false && echo >&2 "esp-idf not found, installation required"
# exit 1
