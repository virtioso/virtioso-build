#!/bin/bash

set -euo pipefail

. "${0%/*}/functions.sh"

cd vm-images
set +u
. setup.sh
set -u

recipe="kernel-module-sel4-virt"

if [ "${YOCTO_INCREMENTAL:-0}" != "1" ]; then
    bitbake -c cleansstate "${recipe}"
fi

bitbake "${recipe}"
