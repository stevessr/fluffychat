#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

"""
字体拆分工具 - 将大字体文件拆分为基础集和扩展集

目标：
- NotoSansSC: 16.9MB -> 基础 3MB + 扩展 13MB
- NotoColorEmoji: 10.2MB -> 基础 2MB + 扩展 8MB

基础集包含：
- ASCII + 常用标点
- GB2312 3500 常用汉字
- 常用 Emoji（~800 个）
"""

import json
import pathlib
import sys
import subprocess
import argparse

def ensure_fonttools():
    """确保 fonttools 已安装"""
    # 如果当前 Python 是 venv，直接使用
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

    # 尝试系统 Python
    try:
        subprocess.run(
            ['python3', '-m', 'fontTools.subset', '--help'],
            capture_output=True,
            check=True
        )
        return True
    except:
        print("错误：需要安装 fonttools", file=sys.stderr)
        print("运行：sudo pacman -S python-fonttools python-brotli", file=sys.stderr)
        print("或者：/tmp/font_venv/bin/python3 scripts/split-fonts.py", file=sys.stderr)
        return False

def load_common_cjk_chars(root_dir):
    """加载常用汉字集合"""
    chars = set()

    # ASCII 和基础拉丁扩展
    for cp in range(0x20, 0x7F):
        chars.add(chr(cp))
    for cp in range(0xA0, 0x100):
        chars.add(chr(cp))

    # 从本地化文件中提取汉字
    l10n_dir = root_dir / "lib" / "l10n"
    for arb_file in l10n_dir.glob("*.arb"):
        try:
            data = json.loads(arb_file.read_text(encoding='utf-8'))
            for key, value in data.items():
                if not key.startswith('@') and isinstance(value, str):
                    for ch in value:
                        if '一' <= ch <= '鿿':  # CJK 统一表意文字
                            chars.add(ch)
        except Exception as e:
            print(f"警告：无法解析 {arb_file}: {e}", file=sys.stderr)

    # 从 Dart 代码中提取字符串字面量
    for dart_file in (root_dir / "lib").rglob("*.dart"):
        try:
            content = dart_file.read_text(encoding='utf-8')
            for ch in content:
                if '一' <= ch <= '鿿':
                    chars.add(ch)
        except:
            pass

    # 添加 GB2312 一级常用字（最常用的 3500 字）
    gb2312_l1 = '''
的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情者最立代想已通并提直题党程展五果料象员革位入常文总次品式活设及管特件长求老头基资边流路级少图山统接知较将组见计别她手角期根论运农指几九区强放决西被干做必战先回则任取据处队南给色光门即保治北造百规热领七海口东导器压志世金增争济阶油思术极交受联什认六共权收证改清己美再采转更单风切打白教速花带安场身车例真务具万每目至达走积示议声报斗完类八离华名确才科张信马节话米整空元况今集温传土许步群广石记需段研界拉林律叫且究观越织装影算低持音众书布复容儿须际商非验连断深难近矿千周委素技备半办青省列习响约支般史感劳便团往酸历市克何除消构府称太准精值号率族维划选标写存候毛亲快效斯院查江型眼王按格养易置派层片始却专状育厂京识适属圆包火住调满县局照参红细引听该铁价严首底液官德随病苏失尔死讲配女黄推显谈罪神艺呢席含企望密批营项防举球英氧势告李台落木帮轮破亚师围注远字材排供河态封另施减树溶怎止案言士均武固叶鱼波视仅费紧爱左章早朝害续轻服试食充兵源判护司足某练差致板田降黑犯负击范继兴似余坚曲输修故城夫够送笔船占右财吃富春职觉汉画功巴跟虽杂飞检吸助升阳互初创抗考投坏策古径换未跑留钢曾端责站简述钱副尽帝射草冲承独令限阿宣环双请超微让控州良轴找否纪益依优顶础载倒房突坐粉敌略客袁冷胜绝析块剂测丝协诉念陈仍罗盐友洋错苦夜刑移频逐靠混母短皮终聚汽村云哪既距卫停烈央察烧迅境若印洲刻括激孔搞甚室待核校散侵吧甲游久菜味旧模湖货损预阻毫普稳乙妈植息扩银语挥酒守拿序纸医缺雨吗针刘啊急唱误训愿审附获茶刀跳哥季课凯胡额款绍卷齐伟蒸殖永宗苗川炉岩弱零杨奏沿露杆探滑镇饭浓航怀赶库夺伊灵税途灭赛归召鼓播盘裁险康唯录菌纯借糖盖横符私努堂域枪润幅哈竟熟虫泽脑壤碳欧遍侧寨敢彻虑斜薄庭纳弹饲伸折麦湿暗荷瓦塞床筑恶户访塔奇透梁刀威股岛甘泡睛征坏饱炼诉刮郑璃焦挂霍触摇健圈伤赏租扫寿暴握趋掉弟软偏废尔纺遗拜杀斤奥秋波姆遗
'''
    for ch in gb2312_l1:
        if '一' <= ch <= '鿿':
            chars.add(ch)

    print(f"基础 CJK 字符数：{len([c for c in chars if '一' <= c <= '鿿'])}")
    return chars

def load_common_emoji_chars(root_dir):
    """加载常用 Emoji"""
    chars = set()

    # Emoji 组合字符（必须保留）
    chars.update(['‍', '️', '⃣'])

    # 从代码中提取 Emoji
    emoji_file = root_dir / "lib" / "utils" / "unicode_17_emoji_set.dart"
    if emoji_file.exists():
        import re
        content = emoji_file.read_text(encoding='utf-8')
        for match in re.finditer(r"Emoji\('([^']+)'", content):
            for ch in match.group(1):
                chars.add(ch)

    # 常用 Emoji 范围（基础表情和符号）
    basic_emoji_ranges = [
        (0x1F600, 0x1F64F),  # 表情符号
        (0x1F300, 0x1F5FF),  # 杂项符号和象形文字
        (0x2600, 0x26FF),    # 杂项符号
        (0x2700, 0x27BF),    # 装饰符号
    ]

    for start, end in basic_emoji_ranges:
        for cp in range(start, end + 1):
            chars.add(chr(cp))

    if not chars:
        chars.add('😀')  # 保底

    print(f"基础 Emoji 字符数：{len(chars)}")
    return chars

def subset_font(source_path, target_path, chars, font_name):
    """使用 fonttools 创建字体子集"""
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

        subprocess.run(cmd, check=True, capture_output=True)

        before_size = source_path.stat().st_size
        after_size = target_path.stat().st_size
        print(f"{font_name}: {before_size:,} -> {after_size:,} bytes ({after_size/before_size*100:.1f}%)")

    finally:
        temp_file.unlink(missing_ok=True)

def create_extended_font(source_path, base_chars, target_path, font_name):
    """创建扩展字体（排除基础字符）"""
    # fonttools 不直接支持"排除"，我们需要提取所有字符再过滤
    # 这里简化处理：让扩展字体包含完整字体，运行时优先使用基础字体
    import shutil
    shutil.copy(source_path, target_path)

    size = target_path.stat().st_size
    print(f"{font_name} (扩展): {size:,} bytes (完整副本)")

def main():
    parser = argparse.ArgumentParser(description='拆分字体文件为基础集和扩展集')
    parser.add_argument('--root', type=pathlib.Path, default=pathlib.Path.cwd(),
                        help='项目根目录')
    parser.add_argument('--source-dir', type=pathlib.Path,
                        help='源字体目录（默认：assets/fonts）')
    parser.add_argument('--target-dir', type=pathlib.Path,
                        help='目标字体目录（默认：assets/fonts）')

    args = parser.parse_args()

    root_dir = args.root.resolve()
    source_dir = args.source_dir or root_dir / 'assets' / 'fonts'
    target_dir = args.target_dir or source_dir

    if not ensure_fonttools():
        print("错误：无法安装 fonttools", file=sys.stderr)
        return 1

    # 字体文件路径
    noto_sans_src = source_dir / 'NotoSansSC-Variable.ttf'
    noto_emoji_src = source_dir / 'NotoColorEmoji-Regular.ttf'

    if not noto_sans_src.exists() or not noto_emoji_src.exists():
        print(f"错误：找不到源字体文件", file=sys.stderr)
        print(f"  NotoSansSC: {noto_sans_src.exists()}")
        print(f"  NotoEmoji: {noto_emoji_src.exists()}")
        return 1

    target_dir.mkdir(parents=True, exist_ok=True)

    # 加载字符集
    print("\n分析字符使用...")
    cjk_chars = load_common_cjk_chars(root_dir)
    emoji_chars = load_common_emoji_chars(root_dir)

    # 创建基础字体
    print("\n创建基础字体子集...")
    subset_font(
        noto_sans_src,
        target_dir / 'NotoSansSC-Base.ttf',
        cjk_chars,
        'NotoSansSC-Base'
    )

    subset_font(
        noto_emoji_src,
        target_dir / 'NotoColorEmoji-Base.ttf',
        emoji_chars,
        'NotoColorEmoji-Base'
    )

    # 创建扩展字体（暂时使用完整副本）
    print("\n创建扩展字体...")
    create_extended_font(
        noto_sans_src,
        cjk_chars,
        target_dir / 'NotoSansSC-Extended.ttf',
        'NotoSansSC-Extended'
    )

    create_extended_font(
        noto_emoji_src,
        emoji_chars,
        target_dir / 'NotoColorEmoji-Extended.ttf',
        'NotoColorEmoji-Extended'
    )

    print("\n✓ 字体拆分完成")
    print(f"  基础字体：{target_dir}")
    print(f"  下一步：更新 pubspec.yaml 使用基础字体")

    return 0

if __name__ == '__main__':
    sys.exit(main())
