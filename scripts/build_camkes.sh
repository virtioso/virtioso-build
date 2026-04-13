#! /bin/sh

set -e

. ${0%/*}/functions.sh

APP_DIR=$(find projects -path "*/apps/*/${CAMKES_VM_APP}" -type d | head -n 1)

if [ -z "${APP_DIR}" ]; then
  echo "Unable to locate app '${CAMKES_VM_APP}' under projects/*/apps/*/" >&2
  exit 1
fi

DIR=$(echo "${APP_DIR}" | cut -f-2 -d/)
APP_CMAKELISTS="${APP_DIR}/CMakeLists.txt"

exec ${SCRIPT_DIR}/build_sel4.sh \
  ${BUILD_TARGET}_${CAMKES_VM_APP} \
  ${DIR} \
  -DCAMKES_VM_APP=${CAMKES_VM_APP}
