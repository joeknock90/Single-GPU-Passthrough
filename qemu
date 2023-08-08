#!/usr/bin/env bash
#
# Author: SharkWipf
#
# Copy this file to /etc/libvirt/hooks, make sure it's called "qemu".
# After this file is installed, restart libvirt.
# From now on, you can easily add per-guest qemu hooks.
# Add your hooks in /etc/libvirt/hooks/qemu.d/vm_name/hook_name/state_name.
# For a list of available hooks, please refer to https://www.libvirt.org/hooks.html
#

GUEST_NAME="$1"
HOOK_NAME="$2"
STATE_NAME="$3"
MISC="${@:4}"

BASEDIR="$(dirname $0)"

HOOKPATH="$BASEDIR/qemu.d/$GUEST_NAME/$HOOK_NAME/$STATE_NAME"

set -e # If a script exits with an error, we should as well.

# check if it's a non-empty executable file
if [ -f "$HOOKPATH" ] && [ -s "$HOOKPATH" ] && [ -x "$HOOKPATH" ]; then
    eval \"$HOOKPATH\" "$@"
elif [ -d "$HOOKPATH" ]; then
    while read file; do
        # check for null string
        if [ ! -z "$file" ]; then
          eval \"$file\" "$@"
        fi
    done <<< "$(find -L "$HOOKPATH" -maxdepth 1 -type f -executable -print;)"
fi

