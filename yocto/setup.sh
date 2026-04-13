# assume we're in the same dir as layers
if [ -n "$BASH_SOURCE" ]; then
  SCRIPT=$BASH_SOURCE
else
  SCRIPT=$0
fi
LAYERS_ROOT="$(realpath -e "$(dirname "$SCRIPT")")"

# Read MACHINE from Kconfig-generated .config
CONFIG_FILE="${LAYERS_ROOT}/../.config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: .config not found. Run 'make <platform>_defconfig' first." 1>&2
  return 1
fi

MACHINE=$(grep '^CONFIG_MACHINE=' "$CONFIG_FILE" | cut -d= -f2 | tr -d '"')

if [ -z "$MACHINE" ]; then
  echo "ERROR: MACHINE not set in .config" 1>&2
  return 1
fi

export MACHINE

if [ -n "$YOCTO_SOURCE_MIRROR_DIR" ]; then
  export INHERIT="own-mirrors"
  export SOURCE_MIRROR_URL=file://${YOCTO_SOURCE_MIRROR_DIR%/}/
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} SOURCE_MIRROR_URL INHERIT"
fi

. "${LAYERS_ROOT}/poky/oe-init-build-env" "$@"

sed -i -e '/LAYERS_ROOT/d' conf/bblayers.conf

echo 'LAYERS_ROOT = "'${LAYERS_ROOT}'"' >> conf/bblayers.conf
echo 'include ${LAYERS_ROOT}/conf/layers/extra.conf' >> conf/bblayers.conf
echo 'include ${LAYERS_ROOT}/conf/layers/machine/${MACHINE}.conf' >> conf/bblayers.conf
