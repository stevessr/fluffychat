#!/bin/sh -ve

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Compile Vodozemac for web
version=$(yq ".dependencies.flutter_vodozemac" < pubspec.yaml)
version=$(printf "%s" "$version" | tr -d '"^')
git clone https://github.com/famedly/dart-vodozemac.git -b ${version} .vodozemac
cd .vodozemac
# Keep the Rust-generated web bindings on the same ABI/codegen version as the
# patched Dart runtime in third_party/flutter_rust_bridge.
cargo install flutter_rust_bridge_codegen --version 2.11.1 --locked
flutter_rust_bridge_codegen build-web --dart-root dart --rust-root $(readlink -f rust) --release
cd ..
rm -f ./assets/vodozemac/vodozemac_bindings_dart*
mv .vodozemac/dart/web/pkg/vodozemac_bindings_dart* ./assets/vodozemac/
rm -rf .vodozemac
# flutter_rust_bridge_codegen can leave a package graph based on the dependency
# state before the final root pub get. Flutter parses package_graph.json during
# pub get post-processing, so remove the stale graph before running pub get.
rm -f .dart_tool/package_graph.json
flutter pub get
dart compile js ./web/native_executor.dart -o ./web/native_executor.js -m

# Download native_imaging for web:
version=$(yq ".dependencies.native_imaging" < pubspec.yaml)
version=$(printf "%s" "$version" | tr -d '"^')
curl -L "https://github.com/famedly/dart_native_imaging/releases/download/v${version}/native_imaging.zip" > native_imaging.zip
unzip native_imaging.zip
mv js/* web/
rmdir js
rm native_imaging.zip

# Upstream native_imaging 0.4.0 ships a few web-only bugs that matter under
# Flutter wasm thumbnail generation. Patch them after the zip extract so
# prepare-web stays the single source of Imaging.js.
python3 - <<'PY'
from pathlib import Path
path = Path('web/Imaging.js')
text = path.read_text()
replacements = [
    (
        'return Image(data.width, data.height, data.data);',
        'return Image.fromRGBA(data.width, data.height, data.data);',
    ),
    (
        'c.toBlob(resolve, "image/jpeg", {quality: quality / 100});',
        '''c.toBlob(function(result) {
        if (result == null) {
          reject(new Error("canvas.toBlob returned null"));
          return;
        }
        resolve(result);
      }, "image/jpeg", quality / 100);''',
    ),
    (
        '''return {init() {
  if (!prom) prom = single_init.call(this);
  return prom;
}};''',
        '''return {init() {
  if (!prom) {
    const pending = single_init.call(this);
    prom = pending;
    pending.catch(function() {
      if (prom === pending) prom = undefined;
    });
  }
  return prom;
}};''',
    ),
]
for old, new in replacements:
    if old not in text:
        raise SystemExit(f'Imaging.js patch target missing:\n{old}')
    text = text.replace(old, new, 1)
path.write_text(text)
print('Patched web/Imaging.js for wasm thumbnail quality and init retry')
PY

# Fail closed if vodozemac web bindings were not produced. A bare
# `flutter build web --wasm` without these assets boots a non-E2EE shell.
for f in \
  assets/vodozemac/vodozemac_bindings_dart.js \
  assets/vodozemac/vodozemac_bindings_dart_bg.wasm \
  web/native_executor.js \
  web/Imaging.js \
  web/Imaging.wasm
do
  if [ ! -f "$f" ]; then
    echo "prepare-web missing required artifact: $f" >&2
    exit 1
  fi
done
