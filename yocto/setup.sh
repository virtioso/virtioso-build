# assume we're in the same dir as layers
if [ -n "$BASH_SOURCE" ]; then
  SCRIPT=$BASH_SOURCE
else
  SCRIPT=$0
fi
LAYERS_ROOT="$(realpath -e "$(dirname "$SCRIPT")")"

# Read MACHINE from the canonical workspace-root Kconfig output.
CONFIG_FILE="${LAYERS_ROOT}/../.config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: .config not found at ${LAYERS_ROOT}/../.config. Run 'make <platform>_defconfig' first from workspace root." 1>&2
  return 1
fi

MACHINE=$(grep '^CONFIG_MACHINE=' "$CONFIG_FILE" | cut -d= -f2 | tr -d '"')

if [ -z "$MACHINE" ]; then
  echo "ERROR: MACHINE not set in ${CONFIG_FILE}" 1>&2
  return 1
fi

export MACHINE

if [ -n "$YOCTO_SOURCE_MIRROR_DIR" ]; then
  export INHERIT="own-mirrors"
  export SOURCE_MIRROR_URL=file://${YOCTO_SOURCE_MIRROR_DIR%/}/
  export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} SOURCE_MIRROR_URL INHERIT"
fi

# wrynose: poky was split; use oe-core + meta-yocto template.
# bitbake is found automatically at $OEROOT/../bitbake (sibling of oe-core).
# Remove stale bblayers.conf from any pre-wrynose build dir so oe-init-build-env
# regenerates it from the template rather than keeping poky paths.
_builddir="${1:-build}"
if [ -f "${_builddir}/conf/bblayers.conf" ] && \
   grep -q 'vm-images/poky' "${_builddir}/conf/bblayers.conf" 2>/dev/null; then
    rm "${_builddir}/conf/bblayers.conf"
fi
unset _builddir
TEMPLATECONF="${LAYERS_ROOT}/virtioso-yocto-layers/meta-virtioso/conf/templates/default" \
    . "${LAYERS_ROOT}/oe-core/oe-init-build-env" "$@"

sed -i -e '/LAYERS_ROOT/d' conf/bblayers.conf

echo 'LAYERS_ROOT = "'${LAYERS_ROOT}'"' >> conf/bblayers.conf
echo 'include ${LAYERS_ROOT}/conf/layers/extra.conf' >> conf/bblayers.conf
echo 'include ${LAYERS_ROOT}/conf/layers/machine/${MACHINE}.conf' >> conf/bblayers.conf
