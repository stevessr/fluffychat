#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_FONT_DIR="${ROOT_DIR}/assets/fonts"
TARGET_FONT_DIR="${1:-${ROOT_DIR}/build/web/assets/assets/fonts}"

SANS_FONT_NAME="NotoSansSC-Variable.ttf"
EMOJI_FONT_NAME="NotoColorEmoji-Regular.ttf"
CODE_FONT_NAME="GoogleSansCode-Regular.ttf"
CODE_ITALIC_FONT_NAME="GoogleSansCode-Italic.ttf"

SANS_SOURCE="${SOURCE_FONT_DIR}/${SANS_FONT_NAME}"
EMOJI_SOURCE="${SOURCE_FONT_DIR}/${EMOJI_FONT_NAME}"
CODE_SOURCE="${SOURCE_FONT_DIR}/${CODE_FONT_NAME}"
CODE_ITALIC_SOURCE="${SOURCE_FONT_DIR}/${CODE_ITALIC_FONT_NAME}"
SANS_TARGET="${TARGET_FONT_DIR}/${SANS_FONT_NAME}"
EMOJI_TARGET="${TARGET_FONT_DIR}/${EMOJI_FONT_NAME}"
CODE_TARGET="${TARGET_FONT_DIR}/${CODE_FONT_NAME}"
CODE_ITALIC_TARGET="${TARGET_FONT_DIR}/${CODE_ITALIC_FONT_NAME}"

if [ ! -d "${TARGET_FONT_DIR}" ]; then
  echo "Font subset skipped: build font directory not found: ${TARGET_FONT_DIR}" >&2
  exit 0
fi

if [ ! -f "${SANS_SOURCE}" ] || [ ! -f "${EMOJI_SOURCE}" ] || [ ! -f "${CODE_SOURCE}" ] || [ ! -f "${CODE_ITALIC_SOURCE}" ]; then
  echo "Font subset skipped: source fonts not found in ${SOURCE_FONT_DIR}" >&2
  exit 0
fi

ensure_fonttools() {
  if python3 -m fontTools.subset --help >/dev/null 2>&1; then
    return 0
  fi

  echo "Installing fonttools for font subsetting..."

  if ! python3 -m pip --version >/dev/null 2>&1; then
    python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
  fi

  if python3 -m pip --version >/dev/null 2>&1; then
    python3 -m pip install --quiet --user fonttools brotli zopfli
    python3 -m fontTools.subset --help >/dev/null 2>&1
    return $?
  fi

  return 1
}

if ! ensure_fonttools; then
  echo "Font subset skipped: fonttools is not available in this environment." >&2
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

python3 - "${ROOT_DIR}" "${TMP_DIR}" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
tmp = pathlib.Path(sys.argv[2])

texts = []

for arb in sorted((root / "lib" / "l10n").glob("*.arb")):
    try:
        data = json.loads(arb.read_text(encoding="utf-8"))
    except Exception:
        continue
    for key, value in data.items():
        if key.startswith("@"):
            continue
        if isinstance(value, str):
            texts.append(value)

for dart in sorted((root / "lib").rglob("*.dart")):
    try:
        texts.append(dart.read_text(encoding="utf-8"))
    except Exception:
        continue

all_text = "\n".join(texts)

sans_chars = set()
emoji_chars = set()
emoji_sequences = set()

# Keep ASCII and common punctuation/spacing baseline for safety.
for cp in range(0x20, 0x7F):
    sans_chars.add(chr(cp))
for cp in range(0xA0, 0x100):
    sans_chars.add(chr(cp))

# Preserve emoji composition chars.
emoji_chars.update({"‍", "️", "⃣"})

for ch in all_text:
    cp = ord(ch)
    if not ch.isprintable():
        continue
    if (
        0x1F000 <= cp <= 0x1FAFF
        or 0x2600 <= cp <= 0x27BF
        or 0x1F1E6 <= cp <= 0x1F1FF
    ):
        emoji_chars.add(ch)
        continue
    if cp in (0x200D, 0xFE0F, 0x20E3):
        emoji_chars.add(ch)
        continue
    sans_chars.add(ch)

u17_file = root / "lib" / "utils" / "unicode_17_emoji_set.dart"
if u17_file.exists():
    text = u17_file.read_text(encoding="utf-8")
    emoji_sequences.update(m.group(1) for m in re.finditer(r"Emoji\('([^']+)'", text))

app_config_file = root / "lib" / "config" / "app_config.dart"
if app_config_file.exists():
    text = app_config_file.read_text(encoding="utf-8")
    for match in re.finditer(r"'([^']+)'", text):
        value = match.group(1)
        if any(
            0x1F000 <= ord(ch) <= 0x1FAFF or 0x2600 <= ord(ch) <= 0x27BF
            for ch in value
        ):
            emoji_sequences.add(value)

for seq in emoji_sequences:
    for ch in seq:
        emoji_chars.add(ch)

if not emoji_chars:
    emoji_chars.add("😀")

(tmp / "noto_sans_chars.txt").write_text(
    "".join(sorted(sans_chars, key=ord)), encoding="utf-8"
)
(tmp / "noto_emoji_chars.txt").write_text(
    "".join(sorted(emoji_chars, key=ord)), encoding="utf-8"
)

print(f"NotoSansSC glyph chars: {len(sans_chars)}")
print(f"NotoColorEmoji glyph chars: {len(emoji_chars)}")
PY

before_sans_size="$(stat -c%s "${SANS_TARGET}" 2>/dev/null || stat -c%s "${SANS_SOURCE}")"
before_emoji_size="$(stat -c%s "${EMOJI_TARGET}" 2>/dev/null || stat -c%s "${EMOJI_SOURCE}")"

python3 -m fontTools.subset "${SANS_SOURCE}" \
  --output-file="${SANS_TARGET}" \
  --text-file="${TMP_DIR}/noto_sans_chars.txt" \
  --layout-features='*' \
  --glyph-names \
  --symbol-cmap \
  --legacy-cmap \
  --notdef-glyph \
  --notdef-outline \
  --recommended-glyphs \
  --name-IDs='*' \
  --name-languages='*'

python3 -m fontTools.subset "${EMOJI_SOURCE}" \
  --output-file="${EMOJI_TARGET}" \
  --text-file="${TMP_DIR}/noto_emoji_chars.txt" \
  --layout-features='*' \
  --glyph-names \
  --symbol-cmap \
  --legacy-cmap \
  --notdef-glyph \
  --notdef-outline \
  --recommended-glyphs \
  --name-IDs='*' \
  --name-languages='*'

after_sans_size="$(stat -c%s "${SANS_TARGET}")"
after_emoji_size="$(stat -c%s "${EMOJI_TARGET}")"

echo "Font subset done:"
echo "  ${SANS_FONT_NAME}: ${before_sans_size} -> ${after_sans_size} bytes"
echo "  ${EMOJI_FONT_NAME}: ${before_emoji_size} -> ${after_emoji_size} bytes"
echo "  ${CODE_FONT_NAME}: ${before_code_size} -> ${after_code_size} bytes"
echo "  ${CODE_ITALIC_FONT_NAME}: ${before_code_italic_size} -> ${after_code_italic_size} bytes"
