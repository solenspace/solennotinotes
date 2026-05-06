import 'package:permission_handler/permission_handler.dart' as ph;

import 'package:noti_notes_app/services/permissions/permission_result.dart';

abstract class PermissionsService {
  Future<PermissionResult> requestMicrophone();
  Future<PermissionResult> microphoneStatus();

  Future<PermissionResult> requestCamera();
  Future<PermissionResult> cameraStatus();

  Future<PermissionResult> requestPhotos();
  Future<PermissionResult> photosStatus();

  Future<PermissionResult> requestNotifications();
  Future<PermissionResult> notificationsStatus();

  Future<PermissionResult> requestBluetoothScan();
  Future<PermissionResult> bluetoothScanStatus();

  Future<PermissionResult> requestBluetoothConnect();
  Future<PermissionResult> bluetoothConnectStatus();

  Future<PermissionResult> requestBluetoothAdvertise();
  Future<PermissionResult> bluetoothAdvertiseStatus();

  Future<PermissionResult> requestNearbyWifiDevices();
  Future<PermissionResult> nearbyWifiDevicesStatus();

  /// Opens the OS app-settings panel for this app. Use when a permission
  /// returns `permanentlyDenied` and the user wants to re-enable it.
  Future<void> openSettings();
}

class PluginPermissionsService implements PermissionsService {
  const PluginPermissionsService();

  @override
  Future<PermissionResult> requestMicrophone() => _request(ph.Permission.microphone);

  @override
  Future<PermissionResult> microphoneStatus() => _status(ph.Permission.microphone);

  @override
  Future<PermissionResult> requestCamera() => _request(ph.Permission.camera);

  @override
  Future<PermissionResult> cameraStatus() => _status(ph.Permission.camera);

  @override
  Future<PermissionResult> requestPhotos() => _request(ph.Permission.photos);

  @override
  Future<PermissionResult> photosStatus() => _status(ph.Permission.photos);

  @override
  Future<PermissionResult> requestNotifications() => _request(ph.Permission.notification);

  @override
  Future<PermissionResult> notificationsStatus() => _status(ph.Permission.notification);

  @override
  Future<PermissionResult> requestBluetoothScan() => _request(ph.Permission.bluetoothScan);

  @override
  Future<PermissionResult> bluetoothScanStatus() => _status(ph.Permission.bluetoothScan);

  @override
  Future<PermissionResult> requestBluetoothConnect() => _request(ph.Permission.bluetoothConnect);

  @override
  Future<PermissionResult> bluetoothConnectStatus() => _status(ph.Permission.bluetoothConnect);

  @override
  Future<PermissionResult> requestBluetoothAdvertise() =>
      _request(ph.Permission.bluetoothAdvertise);

  @override
  Future<PermissionResult> bluetoothAdvertiseStatus() => _status(ph.Permission.bluetoothAdvertise);

  @override
  Future<PermissionResult> requestNearbyWifiDevices() => _request(ph.Permission.nearbyWifiDevices);

  @override
  Future<PermissionResult> nearbyWifiDevicesStatus() => _status(ph.Permission.nearbyWifiDevices);

  @override
  Future<void> openSettings() async {
    await ph.openAppSettings();
  }

  Future<PermissionResult> _request(ph.Permission p) async {
    final status = await p.request();
    return _map(status);
  }

  Future<PermissionResult> _status(ph.Permission p) async {
    final status = await p.status;
    return _map(status);
  }

  PermissionResult _map(ph.PermissionStatus s) => switch (s) {
        ph.PermissionStatus.granted => PermissionResult.granted,
        ph.PermissionStatus.denied => PermissionResult.denied,
        ph.PermissionStatus.permanentlyDenied => PermissionResult.permanentlyDenied,
        ph.PermissionStatus.restricted => PermissionResult.restricted,
        ph.PermissionStatus.limited => PermissionResult.limited,
        // iOS-only "provisional" notification authorization behaves like granted.
        ph.PermissionStatus.provisional => PermissionResult.granted,
      };
}
