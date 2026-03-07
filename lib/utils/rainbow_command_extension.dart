import 'dart:convert';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:matrix/matrix.dart';

const _matrixHtmlFormat = 'org.matrix.custom.html';
const _rainbowLightness = 75.0;
const _rainbowChroma = 1.0;
const _labRange = 127.0;
const _xyzThreshold = 0.2069;
const _xyzFactor = 0.1284;
const _xyzOffset = 0.01771;
const _rgbThreshold = 0.0031308;
const _rgbLinearFactor = 12.92;
const _rgbGammaFactor = 1.055;
const _rgbGammaOffset = 0.055;
const _rgbGamma = 2.4;
const _maxRgb = 255;
const HtmlEscape _htmlEscape = HtmlEscape();

extension RainbowCommandExtension on Client {
  void registerRainbowCommand() {
    addCommand('rainbow', (args, _) async {
      final room = args.room;
      if (room == null) {
        throw const RoomCommandException();
      }
      if (args.msg.isEmpty) {
        throw const CommandException(
          'You must provide a message when using /rainbow',
        );
      }
      return room.sendEvent(
        buildRainbowTextEventContent(args.msg),
        inReplyTo: args.inReplyTo,
        editEventId: args.editEventId,
        txid: args.txid,
        threadRootEventId: args.threadRootEventId,
        threadLastEventId: args.threadLastEventId,
      );
    });
  }
}

Map<String, dynamic> buildRainbowTextEventContent(String message) => {
  'msgtype': MessageTypes.Text,
  'body': message,
  'format': _matrixHtmlFormat,
  'formatted_body': textToHtmlRainbow(message),
};

String textToHtmlRainbow(String message) {
  final characters = message.characters.toList(growable: false);
  if (characters.isEmpty) return '';

  final frequency = (2 * math.pi) / characters.length;
  final buffer = StringBuffer();

  for (var index = 0; index < characters.length; index++) {
    final character = characters[index];
    if (character == ' ') {
      buffer.write(character);
      continue;
    }
    if (character == '\n') {
      buffer.write('<br>');
      continue;
    }

    final (a, b) = _generateAB(index * frequency, _rainbowChroma);
    final (red, green, blue) = _labToRgb(_rainbowLightness, a, b);
    buffer
      ..write('<span data-mx-color="#')
      ..write(_toHex(red))
      ..write(_toHex(green))
      ..write(_toHex(blue))
      ..write('">')
      ..write(_htmlEscape.convert(character))
      ..write('</span>');
  }

  return buffer.toString();
}

(double, double) _generateAB(double hue, double chroma) {
  final a = chroma * _labRange * math.cos(hue);
  final b = chroma * _labRange * math.sin(hue);
  return (a, b);
}

(int, int, int) _labToRgb(double lightness, double a, double b) {
  var y = (lightness + 16) / 116;
  final x = _adjustXyz(y + a / 500) * 0.9505;
  final z = _adjustXyz(y - b / 200) * 1.089;

  y = _adjustXyz(y);

  final red = 3.24096994 * x - 1.53738318 * y - 0.49861076 * z;
  final green = -0.96924364 * x + 1.8759675 * y + 0.04155506 * z;
  final blue = 0.05563008 * x - 0.20397696 * y + 1.05697151 * z;

  return (_adjustRgb(red), _adjustRgb(green), _adjustRgb(blue));
}

double _adjustXyz(double value) {
  if (value > _xyzThreshold) {
    return math.pow(value, 3).toDouble();
  }
  return _xyzFactor * value - _xyzOffset;
}

double _gammaCorrection(double value) {
  if (value <= _rgbThreshold) {
    return _rgbLinearFactor * value;
  }
  return _rgbGammaFactor * math.pow(value, 1 / _rgbGamma).toDouble() -
      _rgbGammaOffset;
}

int _adjustRgb(double value) {
  final corrected = _gammaCorrection(value);
  final limited = corrected.clamp(0, 1);
  return (limited * _maxRgb).round();
}

String _toHex(int value) => value.toRadixString(16).padLeft(2, '0');
