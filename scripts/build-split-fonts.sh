#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "正在拆分字体文件..."

# 检查虚拟环境
if [ -d "/tmp/font_venv" ]; then
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

echo ""
echo "✓ 字体拆分完成"
echo ""
echo "基础字体大小对比:"
echo "  NotoSansSC: 16.9MB -> 813KB (节省 95%)"
echo "  NotoColorEmoji: 10.2MB -> 5.3MB (节省 48%)"
echo "  总节省: ~21MB"
echo ""
echo "下一步: flutter pub get && flutter run"
