#!/usr/bin/env bash
# Build, host-test and atomically bundle the validated BYO-data release.
set -euo pipefail

export LC_ALL=C
export TZ=UTC
export PYTHONDONTWRITEBYTECODE=1

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PORT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
# NXRelease is the internal NextOS release tool; it is not distributed with
# this repository. Point NXRELEASE at a checkout to package a release.
NXRELEASE=${NXRELEASE:?NXRELEASE must point at the internal nxrelease.py (tool not distributed)}
NXRELEASE_VERSION=0.2.6
MANIFEST="$PORT_DIR/nxrelease.json"
DESTINATION=${1:-"$PORT_DIR/.build/release"}
ARCHIVE_NAME=angrybirds.zip

fail() {
  printf 'angrybirds package error: %s\n' "$*" >&2
  exit 1
}

[[ -f $NXRELEASE && -f $MANIFEST ]] ||
  fail "canonical NXRelease or manifest is missing"
ACTUAL_VERSION=$(python3 -B "$NXRELEASE" --version)
[[ $ACTUAL_VERSION == "nxrelease $NXRELEASE_VERSION" ]] ||
  fail "NXRelease version drifted: $ACTUAL_VERSION"
[[ ! -e $DESTINATION && ! -L $DESTINATION ]] ||
  fail "destination already exists (package outputs are never overwritten): $DESTINATION"
mkdir -p -- "$(dirname -- "$DESTINATION")"

WORK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/angrybirds-package.XXXXXX")
cleanup() {
  case $WORK_ROOT in
    "${TMPDIR:-/tmp}"/angrybirds-package.*)
      [[ -d $WORK_ROOT ]] && rm -rf -- "$WORK_ROOT"
      ;;
    *)
      printf 'refusing unsafe cleanup target: %s\n' "$WORK_ROOT" >&2
      ;;
  esac
}
trap cleanup EXIT INT TERM

if [[ ${AB_SKIP_BUILD:-0} != 1 ]]; then
  "$PORT_DIR/tests/run-host.sh"
  "$PORT_DIR/build.sh"
fi

python3 -B "$NXRELEASE" validate --manifest "$MANIFEST"
python3 -B "$NXRELEASE" bundle \
  --manifest "$MANIFEST" \
  --stage "$WORK_ROOT/stage" \
  --destination "$DESTINATION" \
  --archive-name "$ARCHIVE_NAME"

printf 'ANGRYBIRDS PACKAGE OK: %s/%s\n' "$DESTINATION" "$ARCHIVE_NAME"
sha256sum -- "$DESTINATION/$ARCHIVE_NAME"
