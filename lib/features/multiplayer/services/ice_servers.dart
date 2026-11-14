const _turnServer = String.fromEnvironment('TURN_SERVER');
const _turnUsername = String.fromEnvironment('TURN_USERNAME');
const _turnPassword = String.fromEnvironment('TURN_PASSWORD');

final List<Map<String, dynamic>> fallbackIceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
];

List<Map<String, dynamic>> buildIceServers({
  String server = _turnServer,
  String username = _turnUsername,
  String password = _turnPassword,
}) {
  if (server.trim().isEmpty || username.isEmpty || password.isEmpty) {
    return fallbackIceServers;
  }

  final addresses = server
      .split(',')
      .map((s) => s.trim().replaceFirst(RegExp(r'^turns?:'), ''))
      .where((s) => s.isNotEmpty);

  return [
    ...fallbackIceServers,
    {
      'urls': [
        for (final address in addresses) ...[
          'turn:$address',
          'turn:$address?transport=tcp',
        ],
      ],
      'username': username,
      'credential': password,
    },
  ];
}
