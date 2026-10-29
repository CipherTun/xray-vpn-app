import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../models.dart';
import 'infra.dart';

/// SSH tunnel: DartSSH2 client + a local SOCKS5 (CONNECT) server on 127.0.0.1:[port].
/// Each SOCKS connection is carried over an SSH direct-tcpip channel (forwardLocal).
/// Xray then uses this SOCKS server as its outbound (see socksOutbound()).
class SshTunnel {
  SSHClient? _client;
  ServerSocket? _server;
  void Function()? onClosed;
  bool _stopping = false;

  bool get active => _client != null;

  Future<void> start(ServerConfig c, int localPort, int keepAliveSec) async {
    await stop();
    _stopping = false;
    final host = c.host!;
    final port = c.port ?? 22;
    AppLog.i('SSH: connecting to $host:$port as ${c.user}');

    final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 15));
    final key = (c.privateKey ?? '').trim();
    final client = SSHClient(
      socket,
      username: c.user ?? 'root',
      onPasswordRequest: () => c.password ?? '',
      identities: key.isEmpty
          ? null
          : SSHKeyPair.fromPem(key, (c.passphrase ?? '').isEmpty ? null : c.passphrase),
      keepAliveInterval: Duration(seconds: keepAliveSec <= 0 ? 10 : keepAliveSec),
    );
    await client.authenticated;
    _client = client;
    AppLog.i('SSH: authenticated');

    client.done.then((_) => _dropped(), onError: (_) => _dropped());

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    _server = server;
    server.listen((s) => _handle(s));
    AppLog.i('SSH: SOCKS5 listening on 127.0.0.1:$localPort');
  }

  void _dropped() {
    if (_stopping || _client == null) return;
    AppLog.e('SSH: connection closed by server/network');
    onClosed?.call();
  }

  Future<void> stop() async {
    _stopping = true;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  Future<void> _handle(Socket s) async {
    final r = _BufReader(s);
    SSHForwardChannel? ch;
    try {
      final h = await r.read(2); // VER, NMETHODS
      if (h[0] != 5) throw 'not socks5';
      await r.read(h[1]);
      s.add([5, 0]); // no auth (loopback only)
      final q = await r.read(4); // VER CMD RSV ATYP
      if (q[1] != 1) {
        s.add([5, 7, 0, 1, 0, 0, 0, 0, 0, 0]); // only CONNECT
        throw 'cmd ${q[1]} unsupported';
      }
      String dest;
      if (q[3] == 1) {
        dest = (await r.read(4)).join('.');
      } else if (q[3] == 3) {
        final n = (await r.read(1))[0];
        dest = utf8.decode(await r.read(n));
      } else if (q[3] == 4) {
        dest = InternetAddress.fromRawAddress(Uint8List.fromList(await r.read(16))).address;
      } else {
        throw 'atyp ${q[3]}';
      }
      final pb = await r.read(2);
      final dport = (pb[0] << 8) | pb[1];

      final client = _client;
      if (client == null) throw 'ssh down';
      ch = await client.forwardLocal(dest, dport);
      s.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);

      final channel = ch;
      channel.stream.listen(
        (d) => s.add(d),
        onDone: () => s.destroy(),
        onError: (_) => s.destroy(),
        cancelOnError: true,
      );
      final rest = r.takeRest();
      if (rest.isNotEmpty) channel.sink.add(rest);
      await r.pump((d) => channel.sink.add(d));
      await channel.sink.close();
    } catch (_) {
      try {
        s.add([5, 5, 0, 1, 0, 0, 0, 0, 0, 0]);
      } catch (_) {}
      ch?.destroy();
      s.destroy();
    }
  }
}

class _BufReader {
  _BufReader(Stream<List<int>> s) : _it = StreamIterator<List<int>>(s);
  final StreamIterator<List<int>> _it;
  final List<int> _buf = [];

  Future<List<int>> read(int n) async {
    while (_buf.length < n) {
      if (!await _it.moveNext()) throw StateError('eof');
      _buf.addAll(_it.current);
    }
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  List<int> takeRest() {
    final o = List<int>.from(_buf);
    _buf.clear();
    return o;
  }

  Future<void> pump(void Function(List<int>) sink) async {
    while (await _it.moveNext()) {
      sink(_it.current);
    }
  }
}
