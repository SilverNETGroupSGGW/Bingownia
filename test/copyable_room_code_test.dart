import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bingo_sggw/features/multiplayer/widgets/copyable_room_code.dart';

void main() {
  testWidgets('dotknięcie kodu kopiuje go i pokazuje komunikat',
      (WidgetTester tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CopyableRoomCode(roomId: 'ABC123', prefix: 'Kod pokoju: '),
        ),
      ),
    );

    expect(find.text('Kod pokoju: ABC123'), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);

    await tester.tap(find.byType(CopyableRoomCode));
    await tester.pump();
    await tester.pump();

    expect(copied, 'ABC123');
    expect(find.text('Skopiowano kod pokoju'), findsOneWidget);
  });
}
