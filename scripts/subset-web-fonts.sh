#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_FONT_DIR="${1:-${ROOT_DIR}/build/web/assets/assets/fonts}"

if [ ! -d "${TARGET_FONT_DIR}" ]; then
  echo "Web font check skipped: build font directory not found: ${TARGET_FONT_DIR}" >&2
  exit 0
fi

# These are source/full fallback files. They must not be shipped in web builds:
# Flutter Web should prefer Google Fonts CDN and only fall back to the local
# chunked assets below the current base href.
rm -f \
  "${TARGET_FONT_DIR}/NotoSansSC-Variable.ttf" \
  "${TARGET_FONT_DIR}/NotoSansSC-Extended.ttf" \
  "${TARGET_FONT_DIR}/NotoColorEmoji-Regular.ttf" \
  "${TARGET_FONT_DIR}/NotoColorEmoji-Extended.ttf"

echo "Web font chunks:"
find "${TARGET_FONT_DIR}" -maxdepth 1 -type f -name '*.ttf' -printf '  %f %s bytes\n' | sort

if find "${TARGET_FONT_DIR}" -maxdepth 1 -type f \
  \( -name 'NotoSansSC-Variable.ttf' \
     -o -name 'NotoSansSC-Extended.ttf' \
     -o -name 'NotoColorEmoji-Regular.ttf' \
     -o -name 'NotoColorEmoji-Extended.ttf' \) | grep -q .; then
  echo "Web font check failed: full source/Extended font leaked into build output" >&2
  exit 1
fi

echo "Web font check done: Google Fonts CDN remains first; local sub-deployment chunks are fallback only."
