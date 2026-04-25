import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

class DiscoveredHost {
  final String name;
  final String ip;
  final int port;
  final String roomCode;

  DiscoveredHost({
    required this.name,
    required this.ip,
    required this.port,
    required this.roomCode,
  });
}

/// mDNS(Bonjour) 기반 호스트 광고/검색.
///
/// v0.0.41 이전엔 raw UDP 255.255.255.255 broadcast 사용했지만, iOS 14+ 보안상
/// raw multicast/broadcast 송신은 `com.apple.developer.networking.multicast`
/// entitlement 필요(Apple에 사유 신청). nsd 패키지로 시스템 mDNS(NSNetService /
/// NsdManager) wrap → entitlement 없이 양방향(iOS 호스트 ↔ Android 게스트 등)
/// 검색 가능. iOS Info.plist `NSBonjourServices=_synchorus._tcp` 등록 필요(이미 있음).
/// Android는 manifest `CHANGE_WIFI_MULTICAST_STATE` 필요(이미 있음).
class DiscoveryService {
  static const String serviceType = '_synchorus._tcp';
  static const String _txtRoomCodeKey = 'roomCode';

  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  StreamController<DiscoveredHost>? _hostController;

  /// 호스트: 자기 서비스를 mDNS에 publish.
  Future<void> startBroadcast({
    required String hostName,
    required int tcpPort,
    required String roomCode,
  }) async {
    await stop();
    _registration = await nsd.register(nsd.Service(
      name: hostName,
      type: serviceType,
      port: tcpPort,
      txt: {
        _txtRoomCodeKey: Uint8List.fromList(utf8.encode(roomCode)),
      },
    ));
  }

  /// 게스트: 같은 LAN의 호스트 서비스를 mDNS browse.
  /// `addresses`에 IPv4가 들어오면 emit. 같은 호스트가 여러 번 found될 수 있어
  /// 호출자가 중복 처리 책임.
  Stream<DiscoveredHost> discoverHosts() async* {
    await stop();
    final controller = StreamController<DiscoveredHost>();
    _hostController = controller;

    nsd.Discovery? discovery;
    try {
      discovery = await nsd.startDiscovery(
        serviceType,
        ipLookupType: nsd.IpLookupType.any,
      );
    } catch (e) {
      controller.addError(e);
      await controller.close();
      _hostController = null;
      return;
    }
    _discovery = discovery;

    discovery.addServiceListener((service, status) {
      if (controller.isClosed) return;
      if (status != nsd.ServiceStatus.found) return;

      final addresses = service.addresses;
      final port = service.port;
      if (addresses == null || addresses.isEmpty || port == null) return;

      // IPv4 우선 (link-local IPv6는 일부 환경에서 connect 불안정).
      InternetAddress? ipv4;
      for (final a in addresses) {
        if (a.type == InternetAddressType.IPv4) {
          ipv4 = a;
          break;
        }
      }
      final addr = ipv4 ?? addresses.first;

      final txt = service.txt;
      String roomCode = '';
      if (txt != null) {
        final bytes = txt[_txtRoomCodeKey];
        if (bytes != null) {
          try {
            roomCode = utf8.decode(bytes);
          } catch (_) {}
        }
      }

      controller.add(DiscoveredHost(
        name: service.name ?? 'Unknown',
        ip: addr.address,
        port: port,
        roomCode: roomCode,
      ));
    });

    yield* controller.stream;
  }

  Future<void> stop() async {
    if (_registration != null) {
      try {
        await nsd.unregister(_registration!);
      } catch (_) {}
      _registration = null;
    }
    if (_discovery != null) {
      try {
        await nsd.stopDiscovery(_discovery!);
      } catch (_) {}
      _discovery = null;
    }
    final c = _hostController;
    _hostController = null;
    if (c != null && !c.isClosed) {
      await c.close();
    }
  }
}
