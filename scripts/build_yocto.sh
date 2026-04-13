#!/bin/bash

set -euo pipefail

. ${0%/*}/functions.sh

cd vm-images
set +u
. setup.sh
set -u

targets=(
    vm-image-user
    vm-image-driver
    vm-image-boot
    vm-image-minimal
)

bitbake "${targets[@]}"
