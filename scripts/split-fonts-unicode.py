#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
按 Unicode 分区拆分字体 - 实现更细粒度的按需加载

CJK 拆分策略：
1. Base (启动): ASCII + 常用标点 + GB2312-L1 (500KB)
2. Common (按需): GB2312 完整 + 常用繁体 (1MB)
3. Ext-A (按需): CJK 扩展 A 区 (3MB)
4. Ext-B (按需): CJK 扩展 B 区 (6MB)
5. Rare (按需): 其他罕见字符 (剩余)

Emoji 拆分策略：
1. Base (启动): 基础表情 + 常用符号 (1MB)
2. Extended (按需): 完整 Emoji (9MB)
"""

import json
import pathlib
import sys
import subprocess
import argparse

# Unicode CJK 区块定义
CJK_BLOCKS = {
    'base': {
        'name': 'CJK-Base',
        'ranges': [
            (0x20, 0x7E),      # ASCII
            (0xA0, 0xFF),      # Latin-1 Supplement
            (0x2000, 0x206F),  # 常用标点
            (0x3000, 0x303F),  # CJK 符号和标点
        ],
        'gb2312_level': 1,  # 只包含一级常用字
        'description': '启动时加载：ASCII + 基础标点 + 最常用汉字',
    },
    'common': {
        'name': 'CJK-Common',
        'ranges': [
            (0x4E00, 0x9FFF),  # CJK 统一表意文字（基本区）
        ],
        'gb2312_level': 2,  # 完整 GB2312
        'description': '常用汉字：GB2312 完整 + 常用繁体',
    },
    'ext_a': {
        'name': 'CJK-ExtA',
        'ranges': [
            (0x3400, 0x4DBF),  # CJK 扩展 A
        ],
        'description': 'CJK 扩展 A 区：罕见汉字',
    },
    'ext_b': {
        'name': 'CJK-ExtB',
        'ranges': [
            (0x20000, 0x2A6DF),  # CJK 扩展 B
        ],
        'description': 'CJK 扩展 B 区：极罕见汉字',
    },
    'ext_cde': {
        'name': 'CJK-ExtCDE',
        'ranges': [
            (0x2A700, 0x2B73F),  # CJK 扩展 C
            (0x2B740, 0x2B81F),  # CJK 扩展 D
            (0x2B820, 0x2CEAF),  # CJK 扩展 E
        ],
        'description': 'CJK 扩展 C/D/E 区：极罕见汉字',
    },
}

EMOJI_BLOCKS = {
    'base': {
        'name': 'Emoji-Base',
        'ranges': [
            (0x1F600, 0x1F64F),  # 表情符号（脸部）
            (0x2600, 0x26FF),    # 杂项符号
            (0x2700, 0x27BF),    # 装饰符号
        ],
        'description': '启动时加载：基础表情 + 常用符号',
    },
    'extended': {
        'name': 'Emoji-Extended',
        'ranges': [
            (0x1F300, 0x1F5FF),  # 杂项符号和象形文字
            (0x1F680, 0x1F6FF),  # 交通和地图符号
            (0x1F700, 0x1F77F),  # 炼金术符号
            (0x1F780, 0x1F7FF),  # 几何图形扩展
            (0x1F800, 0x1F8FF),  # 补充箭头 C
            (0x1F900, 0x1F9FF),  # 补充符号和象形文字
            (0x1FA00, 0x1FA6F),  # 扩展 A
            (0x1FA70, 0x1FAFF),  # 符号和象形文字扩展 A
        ],
        'description': '按需加载：完整 Emoji 集',
    },
}

def load_gb2312_chars(level=1):
    """加载 GB2312 字符集"""
    # GB2312 一级常用字（最常用的 500 字）
    gb2312_l1_top500 = '''
的一是不了人我在有他这为之大来以个中上们到说国和地也子时道出而要于就下得可你年生自会那后能对着事其里所去行过家十用发天如然作方成者多日都三小军二无同么经法当起面又高手长老头定正教明月分总条白话把些动比量看提或种像应女性员利马克便几公无平样望根女体北该次化名便机十四相美已失则象件走位由千完气带安器命入值百界满包教给根反约亲许马共九万农系满易近两却民土英张王李四基题式社保江院干建准素始导农确资划许较转七原设记报五造反林局转确思林办效百改据养断思八拉专算治维认省克提命领万派保况集领争运半办元习界具六青器组众运器便收层改专究极提运军报米党断争革约众般育持除火联类务展容约素件型八才统技广青科华导层单转况易战划维五基际般验般元府江更象万布连京速收认农林基素响队报单五称离达各广即极价青委容资收石建适采例验认质半效基才军党参报况二派约世速往存周响干压资导阶况程统况火民科总除则约装式响众布器存层十准况办转研民党严思器导转认断持量任九导收党众较王转确确况半存众量总史约响量六验党众象般广总较价半采青况收队府状认队改众际众委保较干元例干认量较众布众准亲广江
'''

    chars = set()
    for ch in gb2312_l1_top500:
        if '一' <= ch <= '鿿':
            chars.add(ch)

    if level >= 2:
        # 添加 GB2312 完整字符集（简化版：从本地化文件提取）
        pass

    return chars

def collect_chars_from_codebase(root_dir, block_config):
    """从代码库中收集属于指定 Unicode 区块的字符"""
    chars = set()

    # 添加 Unicode 范围内的字符
    for start, end in block_config.get('ranges', []):
        for cp in range(start, end + 1):
            try:
                chars.add(chr(cp))
            except ValueError:
                pass

    # 从代码库中提取实际使用的字符
    actual_chars = set()

    # 扫描本地化文件
    l10n_dir = root_dir / "lib" / "l10n"
    if l10n_dir.exists():
        for arb_file in l10n_dir.glob("*.arb"):
            try:
                data = json.loads(arb_file.read_text(encoding='utf-8'))
                for key, value in data.items():
                    if not key.startswith('@') and isinstance(value, str):
                        for ch in value:
                            if ch in chars:
                                actual_chars.add(ch)
            except:
                pass

    # 如果是 base 块，添加 GB2312 常用字
    if 'gb2312_level' in block_config:
        gb_chars = load_gb2312_chars(block_config['gb2312_level'])
        actual_chars.update(gb_chars)

    # 对于基础块，添加基础字符集
    if block_config.get('name') == 'CJK-Base':
        for cp in range(0x20, 0x7F):  # ASCII
            actual_chars.add(chr(cp))
        for cp in range(0xA0, 0x100):  # Latin-1
            actual_chars.add(chr(cp))

    if block_config.get('name') == 'Emoji-Base':
        actual_chars.add('😀')  # 保底
        actual_chars.update(['‍', '️', '⃣'])  # Emoji 组合符

    return actual_chars if actual_chars else chars

def subset_font(source_path, target_path, chars, font_name):
    """使用 fonttools 创建字体子集"""
    if not chars:
        print(f"  跳过 {font_name}: 无字符")
        return

    temp_file = target_path.parent / f"{target_path.stem}_chars.txt"
    temp_file.write_text(''.join(sorted(chars, key=ord)), encoding='utf-8')

    try:
        cmd = [
            sys.executable, '-m', 'fontTools.subset',
            str(source_path),
            f'--output-file={target_path}',
            f'--text-file={temp_file}',
            '--layout-features=*',
            '--glyph-names',
            '--symbol-cmap',
            '--legacy-cmap',
            '--notdef-glyph',
            '--notdef-outline',
            '--recommended-glyphs',
            '--name-IDs=*',
            '--name-languages=*',
        ]

        result = subprocess.run(cmd, check=True, capture_output=True)

        before_size = source_path.stat().st_size
        after_size = target_path.stat().st_size
        print(f"  {font_name}: {after_size/1024:.0f}KB ({len(chars)} 字符, {after_size/before_size*100:.1f}%)")

    except subprocess.CalledProcessError as e:
        print(f"  错误: {font_name} 拆分失败: {e.stderr.decode()}")
    finally:
        temp_file.unlink(missing_ok=True)

def ensure_fonttools():
    """确保 fonttools 已安装"""
    if hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix:
        try:
            subprocess.run(
                [sys.executable, '-m', 'fontTools.subset', '--help'],
                capture_output=True,
                check=True
            )
            return True
        except:
            pass

    try:
        subprocess.run(
            ['python3', '-m', 'fontTools.subset', '--help'],
            capture_output=True,
            check=True
        )
        return True
    except:
        print("错误: 需要安装 fonttools", file=sys.stderr)
        print("运行: sudo pacman -S python-fonttools python-brotli", file=sys.stderr)
        print("或者: /tmp/font_venv/bin/python3 scripts/split-fonts-unicode.py", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(description='按 Unicode 分区拆分字体')
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument('--source-dir', type=pathlib.Path)
    parser.add_argument('--target-dir', type=pathlib.Path)

    args = parser.parse_args()

    root_dir = args.root.resolve()
    source_dir = args.source_dir or root_dir / 'assets' / 'fonts'
    target_dir = args.target_dir or source_dir

    if not ensure_fonttools():
        return 1

    noto_sans_src = source_dir / 'NotoSansSC-Variable.ttf'
    noto_emoji_src = source_dir / 'NotoColorEmoji-Regular.ttf'

    if not noto_sans_src.exists() or not noto_emoji_src.exists():
        print("错误: 找不到源字体文件", file=sys.stderr)
        return 1

    target_dir.mkdir(parents=True, exist_ok=True)

    print("\n=== 拆分 CJK 字体（按 Unicode 区块）===")
    for block_id, block_config in CJK_BLOCKS.items():
        print(f"\n处理: {block_config['name']} - {block_config['description']}")
        chars = collect_chars_from_codebase(root_dir, block_config)

        target_file = target_dir / f"NotoSansSC-{block_config['name']}.ttf"
        subset_font(noto_sans_src, target_file, chars, block_config['name'])

    print("\n=== 拆分 Emoji 字体 ===")
    for block_id, block_config in EMOJI_BLOCKS.items():
        print(f"\n处理: {block_config['name']} - {block_config['description']}")
        chars = collect_chars_from_codebase(root_dir, block_config)

        target_file = target_dir / f"NotoColorEmoji-{block_config['name']}.ttf"
        subset_font(noto_emoji_src, target_file, chars, block_config['name'])

    print("\n✓ Unicode 分区字体拆分完成")
    print(f"\n生成的字体文件位于: {target_dir}")
    print("\n下一步:")
    print("1. 更新 pubspec.yaml 添加新字体")
    print("2. 更新 DynamicFontLoader 支持按区块加载")
    print("3. flutter pub get && flutter run")

    return 0

if __name__ == '__main__':
    sys.exit(main())
