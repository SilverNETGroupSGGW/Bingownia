import 'package:flutter_test/flutter_test.dart';

import 'package:bingo_sggw/core/utils/join_link.dart';

void main() {
  test('w przeglądarce link prowadzi do tej samej strony z kodem pokoju', () {
    final link = buildJoinLink(
      'ABC123',
      base: Uri.parse('https://silvernetgroupsggw.github.io/bingo_sggw/'),
      isWeb: true,
    );

    expect(link, 'https://silvernetgroupsggw.github.io/bingo_sggw/?room=ABC123');
  });

  test('link w przeglądarce zastępuje stary kod i fragment', () {
    final link = buildJoinLink(
      'NEW999',
      base: Uri.parse('http://localhost:8080/?room=OLD111#/cos'),
      isWeb: true,
    );

    expect(link, 'http://localhost:8080/?room=NEW999');
  });

  test('poza przeglądarką link prowadzi do publicznej strony', () {
    final link = buildJoinLink('ABC123', isWeb: false);

    expect(link, startsWith('https://'));
    expect(link, endsWith('?room=ABC123'));
  });

  test('kod pokoju z adresu jest odczytywany i zamieniany na wielkie litery', () {
    expect(roomFromUri(Uri.parse('https://x.pl/?room=abc123')), 'ABC123');
    expect(roomFromUri(Uri.parse('bingo://join?room=XYZ789')), 'XYZ789');
  });

  test('brak lub pusty kod daje null', () {
    expect(roomFromUri(Uri.parse('https://x.pl/')), isNull);
    expect(roomFromUri(Uri.parse('https://x.pl/?room=')), isNull);
    expect(roomFromUri(Uri.parse('https://x.pl/?room=%20')), isNull);
  });
}
