#!/bin/bash

set -euo pipefail

. ${0%/*}/functions.sh

cd vm-images
set +u
. setup.sh
set -u

targets=(
    isengard-initramfs
    isengard-image-native
)

bitbake "${targets[@]}"
