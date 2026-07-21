import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

// Regular
Uuid nrfUUID = Uuid.parse("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartRX = Uuid.parse("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
Uuid uartTX = Uuid.parse("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

// DFU
Uuid dfuUUID = Uuid.parse("FE59");
Uuid dfuControl = Uuid.parse("8EC90001-F315-4F60-9FB8-838830DAEA50");
Uuid dfuFirmware = Uuid.parse("8EC90002-F315-4F60-9FB8-838830DAEA50");

class BLESerial extends AbstractSerial {
  FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  QualifiedCharacteristic? txCharacteristic;
  QualifiedCharacteristic? rxCharacteristic;
  QualifiedCharacteristic? firmwareCharacteristic;
  Stream<List<int>>? receivedDataStream;
  StreamSubscription<ConnectionStateUpdate>? connection;
  Map<String, Chameleon> chameleonMap = {};
  bool inSearch = false;

  BLESerial({required super.log});

  Future<List> availableDevices() async {
    if (inSearch) {
      log.w("Multiple searches in one time not allowed! FIXME");
      return [];
    }

    List<DiscoveredDevice> foundDevices = [];
    await performDisconnect();

    Completer<List<DiscoveredDevice>> completer =
        Completer<List<DiscoveredDevice>>();
    StreamSubscription<DiscoveredDevice> subscription;

    inSearch = true;
    subscription = flutterReactiveBle.scanForDevices(
      withServices: [nrfUUID, dfuUUID],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (!foundDevices.contains(device)) {
        for (var foundDevice in foundDevices) {
          if (foundDevice.id == device.id) {
            return;
          }
        }
        foundDevices.add(device);
      }
    }, onError: (e) {
      log.e("Got BLE search error: $e");
      inSearch = false;
      if (Platform.isIOS) {
        throw (e); // BLE is primary there, throw exception
      } else {
        completer.complete([]); // Other platforms: we don't care
      }
    });

    Timer(const Duration(seconds: 2), () {
      subscription.cancel();
      inSearch = false;
      try {
        completer.complete(foundDevices);
        log.d('Found BLE devices: ${foundDevices.length}');
      } catch (_) {}
    });

    return completer.future;
  }

  @override
  bool isManualConnectionSupported() {
    return false;
  }

  @override
  Future<List<Chameleon>> availableChameleons(bool onlyDFU) async {
    List<Chameleon> output = [];
    for (var bleDevice in await availableDevices()) {
      var dfuMode = false;
      if (bleDevice.name.startsWith('ChameleonUltra')) {
        device = ChameleonDevice.ultra;
      } else if (bleDevice.name.startsWith('ChameleonLite')) {
        device = ChameleonDevice.lite;
      } else if (bleDevice.name.startsWith('CU-')) {
        device = ChameleonDevice.ultra;
        dfuMode = true;
      } else if (bleDevice.name.startsWith('CL-')) {
        device = ChameleonDevice.lite;
        dfuMode = true;
      } else {
        // regular nRF device with UART
        continue;
      }

      connectionType = ConnectionType.ble;

      log.d("Found Chameleon ${chameleonDeviceName(device)}!");
      if (!onlyDFU || onlyDFU && dfuMode) {
        output.add(Chameleon(
            port: bleDevice.id,
            device: device,
            type: connectionType,
            dfu: dfuMode));
      }

      chameleonMap[bleDevice.id] = Chameleon(
          port: bleDevice.id,
          device: device,
          type: connectionType,
          dfu: dfuMode);
    }

    return output;
  }

  @override
  Future<bool> connectSpecificDevice(dynamic devicePort) async {
    // BLE can fail transiently, so retry with a short backoff. Kept low
    // deliberately: each attempt now has its own timeout, and too many rapid
    // attempts trip Android's ~5-scans-per-30s throttle (which then makes
    // every subsequent scan/connect silently fail).
    bool ret = false;
    for (var i = 0; i < 2; i++) {
      ret = await connectSpecificInternal(devicePort);
      if (ret) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return ret;
  }

  Future<bool> connectSpecificInternal(dynamic devicePort) async {
    Completer<bool> completer = Completer<bool>();

    await performDisconnect();
    pendingConnection = true;
    // Connect directly by id instead of connectToAdvertisingDevice. The latter
    // pre-scans for a live advertisement, which (a) adds another BLE scan that
    // trips Android's scan throttle, and (b) never resolves when the device is
    // not currently advertising - e.g. right after an unclean disconnect, while
    // it still holds the stale link. connectToDevice connects by id, honours a
    // real connectionTimeout, and does not require catching an advertisement.
    connection = flutterReactiveBle
        .connectToDevice(
      id: devicePort,
      connectionTimeout: const Duration(seconds: 10),
    )
        .listen((connectionState) async {
      log.w(connectionState);
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        if (chameleonMap[devicePort]!.dfu) {
          connected = true;
          pendingConnection = false;
          txCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuControl,
              deviceId: connectionState.deviceId);
          receivedDataStream =
              flutterReactiveBle.subscribeToCharacteristic(txCharacteristic!);
          receivedDataStream!.listen((data) async {
            if (messageCallback != null) {
              try {
                await messageCallback(Uint8List.fromList(data));
              } catch (_) {
                log.w(
                    "Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}");
              }
            }
          }, onError: (dynamic error) async {
            await performDisconnect();
            log.e(error);
          });

          rxCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuControl,
              deviceId: connectionState.deviceId);

          firmwareCharacteristic = QualifiedCharacteristic(
              serviceId: dfuUUID,
              characteristicId: dfuFirmware,
              deviceId: connectionState.deviceId);

          portName = devicePort;
          device = chameleonMap[devicePort]!.device;
          activeDevicePort = devicePort;

          isDFU = true;
          completer.complete(true);
        } else {
          txCharacteristic = QualifiedCharacteristic(
              serviceId: nrfUUID,
              characteristicId: uartTX,
              deviceId: connectionState.deviceId);
          receivedDataStream =
              flutterReactiveBle.subscribeToCharacteristic(txCharacteristic!);
          receivedDataStream!.listen((data) async {
            if (messageCallback != null) {
              try {
                await messageCallback(Uint8List.fromList(data));
              } catch (_) {
                log.w(
                    "Received unexpected data: ${bytesToHex(Uint8List.fromList(data))}");
              }
            }
          }, onError: (dynamic error) async {
            await performDisconnect();
            log.e(error);
          });

          rxCharacteristic = QualifiedCharacteristic(
              serviceId: nrfUUID,
              characteristicId: uartRX,
              deviceId: connectionState.deviceId);

          try {
            await flutterReactiveBle.writeCharacteristicWithResponse(
                rxCharacteristic!,
                value: Uint8List.fromList([
                  0x11,
                  0xef,
                  0x03,
                  0xfb,
                  0x00,
                  0x00,
                  0x00,
                  0x00,
                  0x02,
                  0x00
                ]));

            connected = true;
            portName = devicePort;
            device = chameleonMap[devicePort]!.device;
            activeDevicePort = devicePort;

            connectionType = ConnectionType.ble;
            isDFU = false;

            completer.complete(true);
          } catch (_) {
            try {
              completer.complete(false);
            } catch (_) {}
          }
        }
      } else if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        await performDisconnect();
        try {
          completer.complete(false);
        } catch (_) {}
      }
    }, onError: (Object error) {
      log.e(error);
      completer.complete(false);
    });

    // Backstop timeout: even connectToDevice's connectionTimeout can, in rare
    // cases, fail to surface a state on Android. Guarantee the attempt always
    // resolves so pendingConnection is cleared and the UI never wedges on the
    // "connecting" spinner.
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () async {
        log.w("BLE connection attempt timed out");
        await performDisconnect();
        return false;
      },
    );
  }

  @override
  Future<bool> performDisconnect() async {
    final hadState = hasConnectionState || connection != null;
    resetConnectionState();
    txCharacteristic = null;
    rxCharacteristic = null;
    firmwareCharacteristic = null;
    receivedDataStream = null;
    if (connection != null) {
      await connection!.cancel();
      connection = null;
      connected = false;
      if (hadState) {
        notifyConnectionStateChanged();
      }
      return true;
    }
    connected = false; // For debug button
    if (hadState) {
      notifyConnectionStateChanged();
    }
    return false;
  }

  @override
  Future<bool> write(Uint8List command, {bool firmware = false}) async {
    if (firmware) {
      await flutterReactiveBle.writeCharacteristicWithoutResponse(
          firmwareCharacteristic!,
          value: command);
    } else {
      await flutterReactiveBle
          .writeCharacteristicWithResponse(rxCharacteristic!, value: command);
    }

    return true;
  }
}
