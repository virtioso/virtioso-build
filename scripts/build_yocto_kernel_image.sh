#!/bin/bash

set -euo pipefail

. "${0%/*}/functions.sh"

cd vm-images
set +u
. setup.sh
set -u

recipe="linux-jammy-nvidia-tegra"

if [ "${YOCTO_INCREMENTAL:-0}" != "1" ]; then
    bitbake -c cleansstate "${recipe}"
fi

bitbake "${recipe}" -c deploy
