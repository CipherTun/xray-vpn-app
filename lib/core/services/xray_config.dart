import 'dart:convert';

import '../models.dart';
import 'infra.dart';

const metricsPort = 49227;

const _lan = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '169.254.0.0/16',
  '100.64.0.0/10',
  '127.0.0.0/8',
  '224.0.0.0/4',
  'fc00::/7',
  'fe80::/10',
];

/// Outbound that points Xray at the local SOCKS5 server run by [SshTunnel].
Map<String, dynamic> socksOutbound(int port) => {
      'tag': 'proxy',
      'protocol': 'socks',
      'settings': {
        'servers': [
          {'address': '127.0.0.1', 'port': port}
        ]
      },
    };

/// Full Xray config: TUN inbound (fd injected natively), local HTTP inbound for tools,
/// DNS handled by Xray, LAN bypass, optional geo bypass, stats + metrics.
Map<String, dynamic> buildXrayConfig({required Map<String, dynamic> outbound, required AppSettings s}) {
  final proxy = Map<String, dynamic>.from(outbound)..['tag'] = 'proxy';
  final proto = proxy['protocol'];
  final isVisionFlow = jsonEncode(proxy).contains('xtls-rprx');
  if (s.mux &&
      !isVisionFlow &&
      proxy['mux'] == null &&
      const ['vmess', 'vless', 'trojan', 'shadowsocks'].contains(proto)) {
    proxy['mux'] = {'enabled': true, 'concurrency': 8};
  }

  final sniff = {
    'enabled': s.sniffing,
    'destOverride': ['http', 'tls', 'quic'],
    'routeOnly': true,
  };

  final rules = <Map<String, dynamic>>[
    {'type': 'field', 'network': 'udp', 'port': '53', 'outboundTag': 'dns-out'},
    if (s.bypassLan) {'type': 'field', 'ip': _lan, 'outboundTag': 'direct'},
  ];

  final region = s.geoBypass;
  if (region != 'none') {
    if (AppPaths.hasGeo) {
      rules.add({
        'type': 'field',
        'ip': ['geoip:$region'],
        'outboundTag': 'direct'
      });
      if (region == 'cn') {
        rules.add({
          'type': 'field',
          'domain': ['geosite:cn'],
          'outboundTag': 'direct'
        });
      }
    } else {
      AppLog.e('Geo bypass "$region" skipped: geo files not downloaded (Tools > Update geo files)');
    }
  }

  return {
    'log': {'loglevel': s.logLevel, 'access': 'none', 'error': AppPaths.coreLog},
    'env': {'xray.location.asset': AppPaths.geoDir},
    'stats': {},
    'metrics': {'listen': '127.0.0.1:$metricsPort'},
    'policy': {
      'system': {
        'statsInboundUplink': true,
        'statsInboundDownlink': true,
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      }
    },
    'dns': {
      'servers': [s.remoteDns],
      'queryStrategy': s.ipv6 ? 'UseIP' : 'UseIPv4',
    },
    'inbounds': [
      {
        'tag': 'tun-in',
        'protocol': 'tun',
        'settings': {'name': 'xray0', 'MTU': s.mtu},
        'sniffing': sniff,
      },
      {
        'tag': 'http-in',
        'listen': '127.0.0.1',
        'port': s.httpPort,
        'protocol': 'http',
        'settings': {},
      },
    ],
    // First outbound is the default route.
    'outbounds': [
      proxy,
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
      {'tag': 'dns-out', 'protocol': 'dns'},
    ],
    'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': rules},
  };
}
