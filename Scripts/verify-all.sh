#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift test -c release
swift build -c release
if [[ -z "${SPECQR_ORACLE:-}" ]]; then
  export SPECQR_ORACLE="$PWD/.build/oracles/SpecQR"
  if [[ ! -d "$SPECQR_ORACLE/.git" ]]; then
    git clone --no-checkout https://github.com/SpecQR/SpecQR.git "$SPECQR_ORACLE"
  fi
  git -C "$SPECQR_ORACLE" checkout --detach 15ad15e5c770ea0e39072f8f88b2733018f02ffd
fi
[[ "$(git -C "$SPECQR_ORACLE" rev-parse HEAD)" == 15ad15e5c770ea0e39072f8f88b2733018f02ffd ]]
npm --prefix "$SPECQR_ORACLE" ci --ignore-scripts --cache "$PWD/.build/npm-cache"
export SPECQR_CLI="$(swift build -c release --show-bin-path)/specqr-cli"
node Scripts/differential.mjs
node Scripts/verify-zxing.mjs
python3 Scripts/verify-zxing-cpp.py
