// SPDX-FileCopyrightText: 2019-Present Famedly GmbH
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix_api_lite/utils/logs.dart';

bool isVersionGreaterThanOrEqualTo(String version, String target) {
  try {
    final versionParts = version
        .substring(1)
        .split('.')
        .map(int.parse)
        .toList();
    final targetParts = target.substring(1).split('.').map(int.parse).toList();

    for (var i = 0; i < versionParts.length; i++) {
      if (i >= targetParts.length) return true; // reached the end, both equal
      if (versionParts[i] > targetParts[i]) return true; // ver greater
      if (versionParts[i] < targetParts[i]) return false; // tar greater
    }

    return true;
  } catch (e) {
    Logs().w(
      '[_isVersionGreaterThanOrEqualTo] Failed to parse version $version',
      e,
    );
    return false;
  }
}

/// Checks an SDK versions response without relying on its collection generic
/// types surviving a browser storage round trip.
bool supportsAuthenticatedMedia(Object response) {
  final Object? rawVersions = (response as dynamic).versions;
  if (rawVersions is Iterable) {
    for (final Object? rawVersion in rawVersions) {
      final version = rawVersion is String
          ? rawVersion
          : rawVersion?.toString();
      if (version != null && isVersionGreaterThanOrEqualTo(version, 'v1.11')) {
        return true;
      }
    }
  }

  final Object? rawFeatures = (response as dynamic).unstableFeatures;
  if (rawFeatures is Map) {
    final value = rawFeatures['org.matrix.msc3916.stable'];
    return value == true || value == 1 || value == 'true';
  }
  return false;
}
