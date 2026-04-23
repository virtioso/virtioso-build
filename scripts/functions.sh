SCRIPT_NAME=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_NAME}`
SCRIPT_BASENAME=`basename ${SCRIPT_NAME}`

# Detect whether should enter container:
#   docker     -> '/.dockerenv' file exists
#   lxc/podman -> 'container' variable is set to runtime name.
#
# With 'container' variable we support native builds too:
# export container="skip", or similar, before calling make, and entering
# container is skipped.
if [ -z "${container:-}" ] && [ ! -f /.dockerenv ]; then
  # shellcheck disable=SC2068
  exec docker/enter_container.sh "$(pwd)" scripts/${SCRIPT_BASENAME} $@
fi

CONFIG_FILE="$(pwd)/.config"
if [ ! -f "${CONFIG_FILE}" ] && [ -f "$(pwd)/virtioso-build/.config" ]; then
  CONFIG_FILE="$(pwd)/virtioso-build/.config"
fi

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: no configuration found at $(pwd)/.config or $(pwd)/virtioso-build/.config" >&2
  exit 1
fi

# shellcheck disable=SC1091
. "${CONFIG_FILE}"

CONFIGURED_ARCH="${CONFIG_ARCH}"

if [ -n "${ARCH:-}" ] && [ "${ARCH}" != "${CONFIGURED_ARCH}" ]; then
    echo "ERROR: ARCH=${ARCH} does not match configured architecture ${CONFIGURED_ARCH}" >&2
    exit 1
fi

if [ -n "${CROSS_COMPILE:-}" ]; then
    CONFIG_CROSS_COMPILER_PREFIX="${CROSS_COMPILE}"
fi

# Export PLATFORM for use by build scripts (from CONFIG_PLATFORM)
PLATFORM="${CONFIG_PLATFORM}"
BUILD_TARGET="${CONFIG_BUILD_TARGET}"

# Load cmake variable name mapping
MAPFILE="${SCRIPT_DIR}/cmake_vars.map"

# Function to translate Kconfig name to cmake name
translate_var() {
    kconfig_name="$1"
    cmake_name=""

    # Look up in mapping file
    if [ -f "$MAPFILE" ]; then
        cmake_name=$(awk -F= -v key="$kconfig_name" '$1 == key { print $2; exit }' "$MAPFILE" 2>/dev/null)
    fi

    # If no mapping found, use original name (pass-through)
    if [ -z "$cmake_name" ]; then
        cmake_name="$kconfig_name"
    fi

    echo "$cmake_name"
}

skip_var() {
    case "$1" in
        ARCH|BUILD_TARGET|HYPERVISOR) return 0 ;;
        *) return 1 ;;
    esac
}

# Convert Kconfig .config format to cmake flags
# Input:  CONFIG_HYPERVISOR=y
#         CONFIG_PLATFORM="qemu-arm-virt"
# Output: -DARM_HYP=ON
#         -DPLATFORM=qemu-arm-virt
CMAKE_FLAGS=""
while IFS= read -r line; do
    # Skip comments and empty lines
    case "$line" in
        \#*|"") continue ;;
    esac

    # Extract variable name and value
    # Format: CONFIG_NAME=value or CONFIG_NAME="value"
    name=$(echo "$line" | sed 's/^CONFIG_//' | cut -d= -f1)
    value=$(echo "$line" | cut -d= -f2- | sed 's/"//g')

    if skip_var "$name"; then
        continue
    fi

    if [ "$name" = "CROSS_COMPILER_PREFIX" ] && [ -n "${CROSS_COMPILE:-}" ]; then
        value="${CROSS_COMPILE}"
    fi

    # Translate variable name
    cmake_name=$(translate_var "$name")

    # Convert y/n to CMake booleans
    case "$value" in
        y) value="ON" ;;
        n) value="OFF" ;;
    esac

    CMAKE_FLAGS="$CMAKE_FLAGS -D${cmake_name}=${value}"
done < "${CONFIG_FILE}"

# Trim leading space
CMAKE_FLAGS=$(echo "$CMAKE_FLAGS" | sed 's/^ //')
