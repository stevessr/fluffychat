#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "正在拆分字体文件..."

# 检查虚拟环境
if [ -x "${ROOT_DIR}/.venv/bin/python" ]; then
  PYTHON="${ROOT_DIR}/.venv/bin/python"
elif [ -d "/tmp/font_venv" ]; then
  PYTHON="/tmp/font_venv/bin/python3"
else
  # 尝试系统 Python
  if python3 -m fontTools.subset --help >/dev/null 2>&1; then
    PYTHON="python3"
  else
    echo "错误: 需要安装 fonttools"
    echo "运行: sudo pacman -S python-fonttools python-brotli"
    echo "或者: python3 -m venv /tmp/font_venv && /tmp/font_venv/bin/pip install fonttools brotli"
    exit 1
  fi
fi

"${PYTHON}" "${ROOT_DIR}/scripts/split-fonts.py"
"${PYTHON}" "${ROOT_DIR}/scripts/split-fonts-unicode.py"

echo ""
echo "✓ 字体拆分完成"
echo ""
echo "基础字体大小对比:"
echo "  NotoSansSC: 源字体放在 tooling/fonts，不进入 Flutter assets"
echo "  NotoColorEmoji: 源字体放在 tooling/fonts，不进入 Flutter assets"
echo "  Extended 完整副本不再生成；Web 优先走 Google Fonts CDN，失败后再走本地分块"
echo ""
echo "下一步: flutter pub get && flutter run"
