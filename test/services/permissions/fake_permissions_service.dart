import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';

/// Test double. Configure per-test by setting public fields; defaults to
/// [PermissionResult.denied] across the board so tests opt into success.
class FakePermissionsService implements PermissionsService {
  PermissionResult microphone = PermissionResult.denied;
  PermissionResult camera = PermissionResult.denied;
  PermissionResult photos = PermissionResult.denied;
  PermissionResult notifications = PermissionResult.denied;
  PermissionResult bluetoothScan = PermissionResult.denied;
  PermissionResult bluetoothConnect = PermissionResult.denied;
  PermissionResult bluetoothAdvertise = PermissionResult.denied;
  PermissionResult nearbyWifiDevices = PermissionResult.denied;
  bool settingsOpened = false;

  final List<String> requestLog = [];

  Future<PermissionResult> _log(String name, PermissionResult r) async {
    requestLog.add(name);
    return r;
  }

  @override
  Future<PermissionResult> requestMicrophone() => _log('microphone', microphone);
  @override
  Future<PermissionResult> microphoneStatus() async => microphone;

  @override
  Future<PermissionResult> requestCamera() => _log('camera', camera);
  @override
  Future<PermissionResult> cameraStatus() async => camera;

  @override
  Future<PermissionResult> requestPhotos() => _log('photos', photos);
  @override
  Future<PermissionResult> photosStatus() async => photos;

  @override
  Future<PermissionResult> requestNotifications() => _log('notifications', notifications);
  @override
  Future<PermissionResult> notificationsStatus() async => notifications;

  @override
  Future<PermissionResult> requestBluetoothScan() => _log('bluetoothScan', bluetoothScan);
  @override
  Future<PermissionResult> bluetoothScanStatus() async => bluetoothScan;

  @override
  Future<PermissionResult> requestBluetoothConnect() => _log('bluetoothConnect', bluetoothConnect);
  @override
  Future<PermissionResult> bluetoothConnectStatus() async => bluetoothConnect;

  @override
  Future<PermissionResult> requestBluetoothAdvertise() =>
      _log('bluetoothAdvertise', bluetoothAdvertise);
  @override
  Future<PermissionResult> bluetoothAdvertiseStatus() async => bluetoothAdvertise;

  @override
  Future<PermissionResult> requestNearbyWifiDevices() =>
      _log('nearbyWifiDevices', nearbyWifiDevices);
  @override
  Future<PermissionResult> nearbyWifiDevicesStatus() async => nearbyWifiDevices;

  @override
  Future<void> openSettings() async {
    settingsOpened = true;
  }
}
