#!/bin/sh

set quiet false
set do_export true

for arg in $argv
  switch "$arg"
    case --quiet
      set quiet true
    case --find-only
      set do_export false
    case *
      echo >&2 "Unrecognized option: '$arg'"
      exit 1
  end
end

if which idf.py >/dev/null 2>&1
  test "$quiet" = false && echo >&2 "esp-idf already exported"
  return 0
end

if test -n "$IDF_PATH"
  test "$quiet" = false && echo >&2 "esp-idf path declared in variable IDF_PATH=$IDF_PATH"
  set export_path "$IDF_PATH/export.fish"

  if ! test -f "$export_path"
    test "$quiet" = false && echo >&2 "no esp-idf under $IDF_PATH"
    return 1
  end

  if test "$do_export" = true
    test "$quiet" = false && echo >&2 "sourcing $export_path"
    
    . "$export_path"
  end
  return 0
end

for dir in "$HOME/esp/esp-idf" "./.esp-idf"
  set export_path "$dir/export.fish"
  if test -f "$export_path"
    test "$quiet" = false && echo >&2 "esp-idf found at $dir"

    if test "$do_export" = true
      test "$quiet" = false && echo >&2 "exporting IDF_PATH"
      set -x IDF_PATH "$dir"

      test "$quiet" = false && echo >&2 "sourcing $export_path"
      . "$export_path"
    end
    return 0
  end
end

test "$quiet" = false && echo >&2 "esp-idf not found, install required"
return 1
