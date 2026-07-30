#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

XML_DIR="xml/src"
OUT_DIR="generated"

mkdir -p "$OUT_DIR"

extensions=(
    xproto:core
    damage:damage
    dri3:dri3
    present:present
    render:render
    shape:shape
    xc_misc:xc_misc
    xf86dri:xf86dri
    xinerama:xinerama
    xprint:xprint
    xtest:xtest
    bigreq:bigreq
    dpms:dpms
    ge:ge
    randr:randr
    res:res
    shm:shm
    xf86vidmode:xf86vidmode
    xinput:xinput
    xv:xv
    composite:composite
    dri2:dri2
    glx:glx
    record:record
    screensaver:screensaver
    sync:sync
    xevie:xevie
    xfixes:xfixes
    xkb:xkb
    xselinux:xselinux
    xvmc:xvmc
)

for extension in "${extensions[@]}"; do
    xml="${extension%%:*}"
    name="${extension##*:}"

    python3 xcbxml_to_zon.py \
        "$XML_DIR/$xml.xml" \
        "$OUT_DIR/$name.zon"
done