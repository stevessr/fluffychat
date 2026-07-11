// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

void registerIframeView(String viewId, String src) {
  // Create iframe element
  final iframe = web.HTMLIFrameElement()
    ..src = src
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true
    ..allow =
        'accelerometer; autoplay; clipboard-write; '
        'encrypted-media; gyroscope; picture-in-picture';

  // Register the iframe view
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) => iframe,
  );
}
