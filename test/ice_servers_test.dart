import 'package:flutter_test/flutter_test.dart';

import 'package:bingo_sggw/features/multiplayer/services/ice_servers.dart';

void main() {
  test('bez danych zwraca sam STUN', () {
    final servers = buildIceServers(server: '', username: '', password: '');

    expect(servers, fallbackIceServers);
  });

  test('brak hasła też wraca do samego STUN', () {
    final servers =
        buildIceServers(server: 'relay.example.com:3478', username: 'u', password: '');

    expect(servers, fallbackIceServers);
  });

  test('z danymi dodaje serwer TURN po UDP i TCP', () {
    final servers = buildIceServers(
      server: 'relay.example.com:3478',
      username: 'user',
      password: 'pass',
    );

    expect(servers.first, fallbackIceServers.first);
    final turn = servers.last;
    expect(turn['urls'], [
      'turn:relay.example.com:3478',
      'turn:relay.example.com:3478?transport=tcp',
    ]);
    expect(turn['username'], 'user');
    expect(turn['credential'], 'pass');
  });

  test('adres z przedrostkiem turn: nie jest podwajany', () {
    final servers = buildIceServers(
      server: 'turn:relay.example.com:3478',
      username: 'user',
      password: 'pass',
    );

    expect(servers.last['urls'].first, 'turn:relay.example.com:3478');
  });

  test('kilka adresów po przecinku daje komplet adresów', () {
    final servers = buildIceServers(
      server: 'a.example.com:3478, b.example.com:80',
      username: 'user',
      password: 'pass',
    );

    expect((servers.last['urls'] as List).length, 4);
    expect(servers.last['urls'], contains('turn:b.example.com:80'));
  });
}
