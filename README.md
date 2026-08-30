<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

[FluffyChat](https://fluffy.chat) is an open source, nonprofit and cute [[matrix](https://matrix.org)] client written in [Flutter](https://flutter.dev). The goal of the app is to create an easy to use instant messenger which is open source and accessible for everyone.

### Links:

- 🌐 [[Weblate] Translate FluffyChat into your language](https://hosted.weblate.org/projects/fluffychat/)
- 🌍 [[m] Join the community](https://matrix.to/#/#fluffy-space:matrix.org)
- 📰 [[Mastodon] Get updates on social media](https://troet.cafe/@krille)
- 💝 [[Liberapay] Support FluffyChat development](https://de.liberapay.com/KrilleChritzelius)

<a href='https://ko-fi.com/krille' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

### Screenshots:

<img src="https://github.com/krille-chan/fluffychat-website/blob/main/public/img/screenshot_mobile.png?raw=true" height="300">
<img src="https://github.com/krille-chan/fluffychat-website/blob/main/public/img/screenshot_desktop.png?raw=true" height="300">

# Features

- 📩 Send all kinds of messages, images and files
- 🤙 Video calls with Matrix RTC
- 🎙️ Voice messages
- 📍 Location sharing
- 🔔 Push notifications
- 💬 Unlimited private and public group chats
- 📣 Public channels with thousands of participants
- 🛠️ Feature rich group moderation including all matrix features
- 🔍 Discover and join public groups
- 🎨 Material You design
- 😄 Custom emotes and stickers
- 🌌 Spaces
- 🔐 End to end encryption
- 🔒 Encrypted chat backup
- 😀 Emoji verification & cross signing
... and much more.


# Installation

Please visit the website for installation instructions:

- https://fluffy.chat

# Configuration and Mobile Device Management (MDM)

FluffyChat supports configuration via MDM on Android&iOS (since v2.10.0) and via a config.json file on web. You can see the populated configuration for MDM on Android in this file under `/android/app/src/main/res/xml/app_restrictions.xml`.
An example configuration can be found in the `config.sample.json` file.

# How to build

1. To build FluffyChat you need [Flutter](https://flutter.dev) and [Rust](https://www.rust-lang.org/tools/install)

2. Clone the repo:
```
git clone https://github.com/krille-chan/fluffychat.git
cd fluffychat
```
3. Choose your target platform below and enable support for it.
3.1 If you want, enable Googles Firebase Cloud Messaging:

`./scripts/add-firebase-messaging.sh`

4. Debug with: `flutter run`

### Android

* Build with: `flutter build apk`

### iOS / iPadOS

* Have a Mac with Xcode installed, and set up for Xcode-managed app signing
* If you want automatic app installation to connected devices, make sure you have Apple Configurator installed, with the Automation Tools (`cfgutil`) enabled
* Set a few environment variables
    * FLUFFYCHAT_NEW_TEAM: the Apple Developer team that your certificates should live under
    * FLUFFYCHAT_NEW_GROUP: the group you want App IDs and such to live under (ie: com.example.fluffychat)
    * FLUFFYCHAT_INSTALL_IPA: set to `1` if you want the IPA to be deployed to connected devices after building, otherwise unset
* Run `./scripts/build-ios.sh`

### Web

* Build with:
```bash
./scripts/prepare-web.sh # To install Vodozemac
flutter build web --release
```

* Optionally configure by serving a `config.json` at the same path as fluffychat.
  An example can be found at `config.sample.json`. All values there are optional.
  **Please only the values, you really need**. If you e.g. only want
  to change the default homeserver, then only modify the `defaultHomeserver` key.

#### URL rewriting (bypassing regional blocks)

FluffyChat can transparently rewrite outgoing request URLs at runtime, e.g. to
route traffic through a proxy when a homeserver is blocked in your region.

Rules are a list of `{pattern, replacement}` pairs. Each pattern matches either
with wildcards or as a regular expression (`"regex": true`):

* **Wildcard mode (default):** `*` matches any text. Each `*` is a capture
  group referenced as `$1`, `$2`, … in the replacement.
* **Regex mode:** the pattern is a Dart `RegExp` matched against the full
  request URL. Capture groups are `$1`, `$2`, …; `$0` is the whole match.

Both modes support `$UPPERCASE_NAME` variables, resolved from
`--dart-define`/`String.fromEnvironment` (e.g. `$PROXY_DOMAIN`), and `$$`
for a literal `$`. Rules are evaluated in order; the first match wins.

In the app you can manage the rules visually under
*Settings → Chat settings → Advanced configs → URL rewriting* — add, edit and
delete rules with a form (pattern type, pattern, replacement). Changes take
effect immediately, without restarting the app. The same rules can be set at
build/deploy time via `--dart-define` or `config.json`:

Example: route all `matrix.org` traffic through a proxy:

```bash
flutter build web --release \
  --dart-define=URL_REWRITE_RULES='[{"pattern":"https://*matrix.org/*","replacement":"https://$PROXY_DOMAIN/---https://$1matrix.org/$2"}]' \
  --dart-define=PROXY_DOMAIN=proxy.example.com
```

For web builds you can also set the rules at deploy time via `config.json`
(no rebuild needed):

```json
{
  "urlRewriteRules": "[{\"pattern\":\"https://*matrix.org/*\",\"replacement\":\"https://proxy.example.com/---https://$1matrix.org/$2\"}]"
}
```

Rules configured in the settings UI (or `config.json`) are combined with
`--dart-define` rules; the latter take precedence.

### Desktop (Linux, Windows, macOS)

* Enable Desktop support in Flutter: https://flutter.dev/desktop

#### Install custom dependencies (Linux)

```bash
sudo apt install libjsoncpp1 libsecret-1-dev libsecret-1-0 librhash0 libwebkit2gtk-4.0-dev lld
```

* Build with one of these:
```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## How to run integration tests

You need to have docker installed locally! Run the preparation script before every test run:

```sh
./scripts/prepare_integration_test.sh
```

Then run all tests with:

```sh
flutter test integration_test/mobile_test.dart
```


# Special thanks

* <a href="https://github.com/fabiyamada">Fabiyamada</a> is a graphics designer and has made the fluffychat logo and the banner. Big thanks for her great designs.

* Also thanks to all translators and testers! With your help, fluffychat is now available in more than 12 languages.

* The Matrix Foundation for making and maintaining the [emoji translations](https://github.com/matrix-org/matrix-spec/blob/main/data-definitions/sas-emoji.json) used for emoji verification, licensed Apache 2.0

* Special thanks to MTRNord, Sorunome and Advocatux.