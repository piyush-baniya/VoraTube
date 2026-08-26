import 'package:permission_handler/permission_handler.dart';

enum MediaPermissionStatus { granted, denied, permanentlyDenied }

class PermissionService {
  const PermissionService();

  Future<MediaPermissionStatus> audioStatus() async {
    return _map(await Permission.audio.status);
  }

  Future<MediaPermissionStatus> requestAudio() async {
    return _map(await Permission.audio.request());
  }

  Future<void> openAppSettingsPage() => openAppSettings();

  MediaPermissionStatus _map(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
        return MediaPermissionStatus.granted;
      case PermissionStatus.permanentlyDenied:
        return MediaPermissionStatus.permanentlyDenied;
      case PermissionStatus.denied:
      case PermissionStatus.restricted:
      case PermissionStatus.provisional:
        return MediaPermissionStatus.denied;
    }
  }
}
