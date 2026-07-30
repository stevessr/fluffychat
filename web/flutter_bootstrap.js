// SPDX-FileCopyrightText: 2019-Present FluffyChat Contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      useColorEmoji: true,
      fontFallbackBaseUrl: 'https://fonts.gstatic.com/s/',
    });
    await appRunner.runApp();
  },
});
