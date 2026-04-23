#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f android/app/google-services.json ]]; then
  echo "google-services.json not found; skipping Firebase Messaging setup."
  exit 0
fi

flutter pub add fcm_shared_isolate
flutter pub get

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  sed -i '' -e 's,^/\*,,' -e 's,\*/$,,' android/app/src/main/kotlin/chat/fluffy/fluffychat/FcmPushService.kt
else
  sed -i 's,//<GOOGLE_SERVICES>,,g' lib/utils/background_push.dart
  sed -i -e 's,^/\*,,' -e 's,\*/$,,' android/app/src/main/kotlin/chat/fluffy/fluffychat/FcmPushService.kt
fi
