#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Generates the examples and localization glue used by the command picker.
#
# How to use this:
# - Add a hint to lib/l10n/intl_en.arb named commandHint_<command>.
# - Add a non-trivial usage string to command_example_groups below when needed.
# - Run this script and then flutter test test/command_hint_test.dart.

cd "$(dirname "$0")/.."

python3 <<'PY'
import json
from pathlib import Path

arb_path = Path('lib/l10n/intl_en.arb')
output_path = Path('lib/pages/chat/command_hints.dart')
arb = json.loads(arb_path.read_text(encoding='utf-8'))
commands = [
    key.removeprefix('commandHint_')
    for key in arb
    if key.startswith('commandHint_')
]

command_example_groups = [
    (
        ['markasdm', 'kick', 'dm', 'ban', 'unban', 'ignore', 'unignore', 'invite'],
        '<matrix-id>',
    ),
    (['html', 'rainbow', 'sendraw', 'plain'], '<message>'),
    (['op'], '<matrix-id> <power-level>'),
    (['banserver', 'unbanserver'], '<server-name-or-glob>'),
]

lines = [
    '// SPDX-FileCopyrightText: 2019-Present Christian Kußowski',
    '// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat',
    '//',
    '// SPDX-License-Identifier: AGPL-3.0-or-later',
    '',
    '// This file is auto-generated using scripts/generate_command_hints_glue.sh.',
    '',
    "import 'package:fluffychat/l10n/l10n.dart';",
    '',
    'String commandExample(String command) {',
    '  switch (command) {',
]

for grouped_commands, arguments in command_example_groups:
    for command in grouped_commands:
        lines.append(f"    case '{command}':")
    lines.append(f"      return '/$command {arguments}';")

lines.extend([
    '    default:',
    "      return '/$command';",
    '  }',
    '}',
    '',
    'String commandHint(L10n l10n, String command) {',
    '  switch (command) {',
])

for command in commands:
    lines.extend([
        f"    case '{command}':",
        f'      return l10n.commandHint_{command};',
    ])

lines.extend([
    '    default:',
    "      return '';",
    '  }',
    '}',
    '',
])

output_path.write_text('\n'.join(lines), encoding='utf-8')
PY

dart format lib/pages/chat/command_hints.dart
