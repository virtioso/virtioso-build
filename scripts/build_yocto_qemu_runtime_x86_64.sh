#!/bin/bash

set -euo pipefail

. "${0%/*}/functions.sh"

cd vm-images
set +u
. setup.sh
set -u

bitbake virtioso-qemu-runtime-x86_64
