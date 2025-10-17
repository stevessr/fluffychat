import 'package:matrix/matrix.dart';

import '../../config/app_config.dart';
import '../poll_extension.dart';

extension VisibleInGuiExtension on List<Event> {
  List<Event> filterByVisibleInGui({String? exceptionEventId}) => where(
        (event) => event.isVisibleInGui || event.eventId == exceptionEventId,
      ).toList();
}

extension IsStateExtension on Event {
  bool get isVisibleInGui =>
      // always filter out edit and reaction relationships
      !{RelationshipTypes.edit, RelationshipTypes.reaction}
          .contains(relationshipType) &&
      // always filter out m.key.* events
      !type.startsWith('m.key.verification.') &&
      // filter out im.ponies.room_emotes events (custom emote pack configuration)
      type != 'im.ponies.room_emotes' &&
      // event types to hide: redaction, reaction, poll response and poll end events
      // if a reaction has been redacted we also want it to be hidden in the timeline
      // poll responses and poll end events should not be shown as individual messages
      !{EventTypes.Reaction, EventTypes.Redaction}.contains(type) &&
      !isPollResponse &&
      !isPollEnd &&
      // if we enabled to hide all redacted events, don't show those
      (!AppConfig.hideRedactedEvents || !redacted) &&
      // if we enabled to hide all unknown events, don't show those
      (!AppConfig.hideUnknownEvents || isEventTypeKnown);

  bool get isState => !{
        EventTypes.Message,
        EventTypes.Sticker,
        EventTypes.Encrypted,
      }.contains(type);

  bool get isCollapsedState => !{
        EventTypes.Message,
        EventTypes.Sticker,
        EventTypes.Encrypted,
        EventTypes.RoomCreate,
        EventTypes.RoomTombstone,
      }.contains(type);
}
