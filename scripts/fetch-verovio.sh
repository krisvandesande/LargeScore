#!/bin/bash
# Fetches the pinned, unmodified Verovio release the app is built with.
# Anyone can change VEROVIO_TAG and rebuild to link a different Verovio (LGPL-3).
set -euo pipefail
cd "$(dirname "$0")/.."
VEROVIO_TAG="${VEROVIO_TAG:-version-6.4.1}"
if [ -d Packages/VerovioKit/verovio/.git ]; then
  echo "Packages/VerovioKit/verovio exists; delete it to fetch $VEROVIO_TAG again"
  exit 0
fi
mkdir -p Packages/VerovioKit
git clone --depth 1 --branch "$VEROVIO_TAG" https://github.com/rism-digital/verovio Packages/VerovioKit/verovio
