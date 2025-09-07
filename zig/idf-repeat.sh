#!/bin/sh

repeat=false
args=""
for arg in "$@"; do
    case "$arg" in
        --repeat)
            repeat=true
            ;;
        *)
            args="$args $arg"
            ;;
    esac
done

if test "$repeat" = true; then
    idf.py $args || idf.py $args
else
    idf.py $args
fi
