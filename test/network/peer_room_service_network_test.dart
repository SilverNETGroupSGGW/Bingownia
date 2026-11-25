// Real-network test of PeerRoomService: public PeerJS signalling + WebRTC.
// Browser-only (WebRTC is not available on the Dart VM), so plain `flutter test` skips it:
//   flutter test test/network/peer_room_service_network_test.dart --platform chrome
@TestOn('browser')
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bingo_sggw/features/board_creation/models/bingo_board.dart';
import 'package:bingo_sggw/features/gameplay/models/bingo_tile.dart';
import 'package:bingo_sggw/features/multiplayer/services/peer_room_service.dart';
import 'package:bingo_sggw/features/multiplayer/services/room_service.dart';

const guestCount = int.fromEnvironment('GUESTS', defaultValue: 5);
const randomToggles = int.fromEnvironment('TOGGLES', defaultValue: 120);
const latencyToggles = int.fromEnvironment('LATENCY_TOGGLES', defaultValue: 30);
const runs = int.fromEnvironment('RUNS', defaultValue: 5);
const converge = Duration(seconds: 15);

final rng = Random();
const service = PeerRoomService();

String randomRoomId() => List.generate(
  6,
  (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[rng.nextInt(32)],
).join();

BingoBoard board() => BingoBoard(
  id: 'net-test',
  title: 'Net test',
  size: 5,
  tiles: [for (var i = 0; i < 25; i++) BingoTile(id: 't$i', text: 'T$i')],
);

Future<void> waitFor(
  List<ValueListenable<Object?>> sources,
  bool Function() done,
  String what,
) async {
  if (done()) return;
  final completer = Completer<void>();
  void check() {
    if (!completer.isCompleted && done()) completer.complete();
  }

  for (final s in sources) {
    s.addListener(check);
  }
  try {
    await completer.future.timeout(
      converge,
      onTimeout: () => throw TimeoutException('convergence: $what'),
    );
  } finally {
    for (final s in sources) {
      s.removeListener(check);
    }
  }
}

bool sameSet(Set<int> a, Set<int> b) =>
    a.length == b.length && a.containsAll(b);

// The run log is the test's output: counts, timings and mismatches.
// ignore: avoid_print
void log(String msg) => print('[net] $msg');

Future<T> stage<T>(String name, Future<T> Function() body) async {
  try {
    return await body();
  } catch (e) {
    log('FAIL stage=$name error=$e');
    rethrow;
  }
}

void main() {
  for (var run = 1; run <= runs; run++) {
    test(
      'run $run: host + $guestCount guests stay in sync over real PeerJS/WebRTC',
      () async {
        final roomId = randomRoomId();
        log('run=$run room=$roomId guests=$guestCount');
        final sessions = <RoomSession>[];
        addTearDown(() {
          for (final s in sessions) {
            s.dispose();
          }
        });

        final host = await stage(
          'hostRoom',
          () => service.hostRoom(roomId: roomId, hostName: 'Host'),
        );
        sessions.add(host);

        final guests = <RoomSession>[];
        for (var i = 0; i < guestCount; i++) {
          final t = Stopwatch()..start();
          final g = await stage(
            'joinRoom#$i',
            () => service.joinRoom(roomId: roomId, name: 'G$i'),
          );
          log('join#$i ms=${t.elapsedMilliseconds}');
          guests.add(g);
          sessions.add(g);
        }
        var all = [host, ...guests];

        await stage(
          'playersList',
          () => waitFor(
            [for (final s in all) s.players],
            () => all.every((s) => s.players.value.length == guestCount + 1),
            'all peers see ${guestCount + 1} players',
          ),
        );

        await host.startGame(board());
        await stage(
          'start',
          () => waitFor(
            [for (final g in guests) g.startedBoard],
            () => guests.every((g) => g.startedBoard.value != null),
            'guests received start',
          ),
        );

        // Expected state is order-independent: a tile is checked iff it was
        // toggled an odd number of times.
        final counts = List.filled(25, 0);
        Set<int> expected() => {
          for (var i = 0; i < 25; i++)
            if (counts[i].isOdd) i,
        };
        Future<void> converged(String what) async {
          try {
            await waitFor(
              [for (final s in all) s.checkedTiles],
              () => all.every((s) => sameSet(s.checkedTiles.value, expected())),
              what,
            );
          } on TimeoutException {
            final bad = all
                .where((s) => !sameSet(s.checkedTiles.value, expected()))
                .length;
            log('MISMATCH $what peers_out_of_sync=$bad/${all.length}');
            rethrow;
          }
        }

        // Serial toggles from random guests (guest -> host -> every guest, the
        // longest path): time until every peer shows the new state.
        final latencies = <int>[];
        for (var n = 0; n < latencyToggles; n++) {
          final who = guests[rng.nextInt(guests.length)];
          final index = rng.nextInt(25);
          counts[index]++;
          final t = Stopwatch()..start();
          who.toggleTile(index);
          await stage('latency#$n', () => converged('serial toggle $n'));
          latencies.add(t.elapsedMilliseconds);
        }
        latencies.sort();
        log(
          'latency serial n=${latencies.length} '
          'median_ms=${latencies[latencies.length ~/ 2]} '
          'p95_ms=${latencies[(latencies.length * 0.95).floor().clamp(0, latencies.length - 1)]} '
          'max_ms=${latencies.last}',
        );

        // Concurrent bursts: several guests toggle the same and different tiles
        // in the same event-loop turn, so the messages race to the host.
        var sent = 0;
        while (sent < randomToggles) {
          final sameTile = rng.nextInt(25);
          for (final g in guests) {
            final index = rng.nextBool() ? sameTile : rng.nextInt(25);
            counts[index]++;
            g.toggleTile(index);
            sent++;
          }
          if (rng.nextBool()) {
            counts[sameTile]++;
            host.toggleTile(sameTile);
            sent++;
          }
          if (rng.nextInt(4) == 0) await Future<void>.delayed(Duration.zero);
        }
        await stage('burst', () => converged('after $sent concurrent toggles'));
        log(
          'burst toggles=$sent final_checked=${expected().length} mismatches=0',
        );

        final late = await stage(
          'lateJoin',
          () => service.joinRoom(roomId: roomId, name: 'Late'),
        );
        sessions.add(late);
        await stage(
          'lateState',
          () => waitFor(
            [late.startedBoard, late.checkedTiles],
            () =>
                late.startedBoard.value != null &&
                sameSet(late.checkedTiles.value, expected()),
            'late joiner got board + current tiles',
          ),
        );
        log('late joiner received start + ${expected().length} checked tiles');
        all = [...all, late];

        final leaver = guests.removeAt(0);
        leaver.dispose();
        sessions.remove(leaver);
        all.remove(leaver);
        final t = Stopwatch()..start();
        await stage(
          'leave',
          () => waitFor(
            [for (final s in all) s.players],
            () => all.every((s) {
              final names = s.players.value.map((p) => p.name).toList();
              return names.length == guestCount + 1 &&
                  !names.contains('G0') &&
                  names.contains('Late');
            }),
            'player list updated after G0 left',
          ),
        );
        log('leave propagated ms=${t.elapsedMilliseconds}');

        for (var n = 0; n < 10; n++) {
          final who = all[rng.nextInt(all.length)];
          final index = rng.nextInt(25);
          counts[index]++;
          who.toggleTile(index);
        }
        await stage('afterLeave', () => converged('toggles after leave'));
        log('toggles after leave converged');

        host.resetTiles();
        counts.fillRange(0, 25, 0);
        await stage('reset', () => converged('reset'));
        expect(all.every((s) => s.checkedTiles.value.isEmpty), isTrue);
        log('RESULT ok run=$run room=$roomId');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}
