// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

Future<void> initVodozemac({required String wasmPath}) =>
    vod.init(wasmPath: wasmPath);
