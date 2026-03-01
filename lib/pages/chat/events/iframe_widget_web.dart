// Web-specific implementation
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

void registerIframeView(String viewId, String src) {
  // Create iframe element
  final iframe = html.IFrameElement()
    ..src = src
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true
    ..allow = 'accelerometer; autoplay; clipboard-write; '
        'encrypted-media; gyroscope; picture-in-picture';

  // Register the iframe view
  ui_web.platformViewRegistry.registerViewFactory(
    viewId,
    (int viewId) => iframe,
  );
}
