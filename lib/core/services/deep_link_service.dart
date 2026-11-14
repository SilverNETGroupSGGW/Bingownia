import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:bingo_sggw/core/utils/join_link.dart';

class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  void initDeepLinks(Function(String roomId) onRoomIdReceived) async {
    Uri? initialUri;

    try {
      initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri, onRoomIdReceived);
      }
    } catch (_) {
      // Brak początkowego linku lub platforma go nie wspiera (np. testy).
    }

    var skipRepeatedInitial = kIsWeb && initialUri != null;

    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        if (skipRepeatedInitial && uri == initialUri) {
          skipRepeatedInitial = false;
          return;
        }
        _handleUri(uri, onRoomIdReceived);
      },
      onError: (err) {
      },
    );
  }

  void _handleUri(Uri uri, Function(String roomId) onRoomIdReceived) {
    final roomId = roomFromUri(uri);

    if (roomId != null) {
      onRoomIdReceived(roomId);
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}