import 'package:flutter/foundation.dart';

const _publicUrl = 'https://silvernetgroupsggw.github.io/bingo_sggw/';

String buildJoinLink(String roomId, {Uri? base, bool? isWeb}) {
  final origin = (isWeb ?? kIsWeb) ? (base ?? Uri.base) : Uri.parse(_publicUrl);

  return origin
      .removeFragment()
      .replace(queryParameters: {'room': roomId})
      .toString();
}

String? roomFromUri(Uri uri) {
  final room = uri.queryParameters['room']?.trim();
  if (room == null || room.isEmpty) return null;

  return room.toUpperCase();
}
