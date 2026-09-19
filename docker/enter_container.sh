#! /bin/sh

DIR=$1
if [ -z "${DIR}" ]; then
  DIR=$(pwd)
else
  shift
fi

CMD=$*
if [ -z "${CMD}" ]; then
  CMD="/bin/bash"
fi

# Support for non-terminal runs
INTERACTIVE=
if [ -t 0 ]; then
  INTERACTIVE="-it"
fi

# Resolve runtime specific options
CONTAINER_ENGINE=${CONTAINER_ENGINE:-"docker"}
if [ "${CONTAINER_ENGINE}" = "podman" ]; then
  CONTAINER_ENGINE_OPTS="--userns keep-id --pids-limit -1"
  CONTAINER_REGISTRY_PREFIX="localhost/"
else
  # Use host network for DNS/internet access (bridge network has routing issues)
  CONTAINER_ENGINE_OPTS="--network=host"
fi

CONTAINER_ENV_FLAGS=
if [ -n "${DOCKER_EXPORT}" ]; then
  CONTAINER_ENV_FLAGS=$(echo "${DOCKER_EXPORT}" | xargs -d ' ' -Ivar -- echo --env var)
fi

# Nothing private from $HOME enters the container: a recipe's tasks are
# arbitrary code with network, so a mounted ~/.ssh is a private key any layer
# in the build could publish. Git over ssh from inside (repo sync, push) goes
# through the host's agent socket instead -- the key never leaves the host --
# with known_hosts and .gitconfig mounted read-only where they exist.
HOME_KNOWN_HOSTS=""; [ -r "${HOME}/.ssh/known_hosts" ] && HOME_KNOWN_HOSTS="${HOME}/.ssh/known_hosts"
HOME_GITCONFIG=""; [ -r "${HOME}/.gitconfig" ] && HOME_GITCONFIG="${HOME}/.gitconfig"
# shellcheck disable=SC2086
exec ${CONTAINER_ENGINE} run --rm ${INTERACTIVE} \
  ${CONTAINER_ENV_FLAGS} \
  -w "${DIR}" \
  -v "${DIR}:${DIR}:z" \
  ${YOCTO_SOURCE_MIRROR_DIR:+--env YOCTO_SOURCE_MIRROR_DIR="${DIR}"/downloads} \
  ${YOCTO_SOURCE_MIRROR_DIR:+-v "${YOCTO_SOURCE_MIRROR_DIR}":"${DIR}"/downloads:z} \
  ${BUILD_CACHE_DIR:+--env BUILD_CACHE_DIR="${HOME}"/.stack} \
  ${BUILD_CACHE_DIR:+-v "${BUILD_CACHE_DIR}"/stack:"${HOME}"/.stack:z} \
  ${SSH_AUTH_SOCK:+-v "${SSH_AUTH_SOCK}:/run/host-ssh-agent.sock:z" --env SSH_AUTH_SOCK=/run/host-ssh-agent.sock} \
  ${HOME_KNOWN_HOSTS:+-v "${HOME_KNOWN_HOSTS}:${HOME}/.ssh/known_hosts:ro,z"} \
  ${HOME_GITCONFIG:+-v "${HOME_GITCONFIG}:${HOME}/.gitconfig:ro,z"} \
  ${CONTAINER_ENGINE_OPTS} \
  "${CONTAINER_REGISTRY_PREFIX}virtioso/build:latest" ${CMD}
