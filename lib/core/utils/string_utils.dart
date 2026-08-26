String? fallbackTitleFromPath(String? path) {
  if (path == null || path.isEmpty) {
    return null;
  }
  final normalized = path.replaceAll('\\', '/');
  final segment = normalized.split('/').last;
  final dot = segment.lastIndexOf('.');
  if (dot <= 0) {
    return segment;
  }
  return segment.substring(0, dot);
}

String? formatFromPath(String? path) {
  if (path == null) {
    return null;
  }
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) {
    return null;
  }
  final ext = path.substring(dot + 1).toLowerCase();
  if (ext.length > 5) {
    return null;
  }
  return ext;
}
