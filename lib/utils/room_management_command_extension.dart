// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The stable room state event introduced by MSC1383 for federation ACLs.
const roomServerAclEventType = 'm.room.server_acl';

/// Commands which alter room state rather than sending a timeline message.
const roomManagementCommandNames = <String>{'banserver', 'unbanserver'};

/// The result of applying a server ACL edit to an event content object.
class ServerAclUpdate {
  final Map<String, Object?> content;
  final bool changed;

  const ServerAclUpdate({required this.content, required this.changed});
}

extension RoomManagementCommandExtension on Client {
  /// Registers room moderation commands backed by Matrix room state.
  ///
  /// `/banserver` and `/unbanserver` edit the room's `m.room.server_acl`
  /// state event. Matching is case-insensitive as specified by MSC4436.
  void registerRoomManagementCommands() {
    addCommand(
      'banserver',
      (args, _) => _setServerBlocked(args, blocked: true),
    );
    addCommand(
      'unbanserver',
      (args, _) => _setServerBlocked(args, blocked: false),
    );
  }
}

Future<String?> _setServerBlocked(
  CommandArgs args, {
  required bool blocked,
}) async {
  final room = args.room;
  if (room == null) {
    throw const RoomCommandException();
  }

  final String pattern;
  try {
    pattern = normalizeServerAclPattern(args.msg);
  } on FormatException catch (error) {
    throw CommandException(error.message);
  }

  // Server ACL is not an important state event in the SDK, so make sure an
  // older ACL has been loaded before modifying it. Otherwise a command could
  // accidentally replace an existing allowlist with a new default ACL.
  await room.postLoad();

  if (!room.canChangeStateEvent(roomServerAclEventType)) {
    throw const CommandException(
      'You do not have permission to change this room\'s server ACL',
    );
  }

  if (blocked) {
    final ownServer = args.client.userID?.domain;
    if (ownServer != null && serverAclPatternMatches(pattern, ownServer)) {
      throw const CommandException(
        'You cannot block your own homeserver because it would make the room unusable',
      );
    }
  }

  final currentEvent = room.getState(roomServerAclEventType);
  final update = updateServerAclContent(
    currentEvent == null
        ? null
        : Map<String, Object?>.from(currentEvent.content),
    pattern,
    blocked: blocked,
  );
  if (!update.changed) return null;

  return args.client.setRoomStateWithKey(
    room.id,
    roomServerAclEventType,
    '',
    update.content,
  );
}

/// Normalizes and performs the client-side safety checks for an ACL pattern.
///
/// Matrix ACL entries are glob patterns. Port numbers are intentionally not
/// supported by the specification because matching happens against the server
/// name with its port removed.
String normalizeServerAclPattern(String input) {
  final pattern = input.trim().toLowerCase();
  if (pattern.isEmpty) {
    throw const FormatException(
      'You must provide a server name or glob pattern',
    );
  }
  if (pattern == '*') {
    throw const FormatException(
      'Blocking every server would make the room unusable',
    );
  }
  if (pattern.contains(RegExp(r'\s')) ||
      pattern.contains('/') ||
      pattern.contains('@') ||
      pattern.contains('#')) {
    throw const FormatException(
      'Enter only a server name or glob pattern, without a scheme, path, or Matrix ID',
    );
  }

  // A single colon denotes a hostname port. Multiple colons can be an IPv6
  // literal and are therefore left intact.
  if (':'.allMatches(pattern).length == 1) {
    throw const FormatException(
      'Server ACL patterns must not include a port number',
    );
  }

  return pattern;
}

/// Returns updated `m.room.server_acl` content without discarding custom keys.
ServerAclUpdate updateServerAclContent(
  Map<String, Object?>? currentContent,
  String pattern, {
  required bool blocked,
}) {
  final normalizedPattern = normalizeServerAclPattern(pattern);
  final content = Map<String, Object?>.from(currentContent ?? const {});
  final deny = switch (content['deny']) {
    final Iterable<Object?> entries => entries.whereType<String>().toList(),
    _ => <String>[],
  };

  if (blocked) {
    final alreadyBlocked = deny.any(
      (entry) => entry.toLowerCase() == normalizedPattern,
    );
    if (alreadyBlocked) {
      return ServerAclUpdate(content: content, changed: false);
    }

    // The allow list defaults to empty (deny everyone). A newly-created ACL
    // therefore needs the common catch-all allow rule so only [deny] is added.
    if (currentContent == null) {
      content['allow'] = <String>['*'];
    }
    content['deny'] = [...deny, normalizedPattern];
    return ServerAclUpdate(content: content, changed: true);
  }

  final filteredDeny = deny
      .where((entry) => entry.toLowerCase() != normalizedPattern)
      .toList();
  if (filteredDeny.length == deny.length) {
    return ServerAclUpdate(content: content, changed: false);
  }
  content['deny'] = filteredDeny;
  return ServerAclUpdate(content: content, changed: true);
}

/// Implements Matrix glob matching for the client-side own-server guard.
bool serverAclPatternMatches(String pattern, String serverName) {
  final expression = StringBuffer('^');
  for (final character in pattern.toLowerCase().split('')) {
    switch (character) {
      case '*':
        expression.write('.*');
      case '?':
        expression.write('.');
      default:
        expression.write(RegExp.escape(character));
    }
  }
  expression.write(r'$');
  final matcher = RegExp(expression.toString());
  final host = serverNameWithoutPort(serverName).toLowerCase();
  if (matcher.hasMatch(host)) return true;

  // Matrix server names use brackets around IPv6 literals. Accept both the
  // bracketed server-name form and the literal itself for the safety guard.
  return serverName.startsWith('[') && matcher.hasMatch('[$host]');
}

/// Removes the optional federation port from a Matrix server name.
String serverNameWithoutPort(String serverName) {
  if (serverName.startsWith('[')) {
    final bracket = serverName.indexOf(']');
    if (bracket > 0) return serverName.substring(1, bracket);
  }
  if (':'.allMatches(serverName).length == 1) {
    return serverName.substring(0, serverName.indexOf(':'));
  }
  return serverName;
}
