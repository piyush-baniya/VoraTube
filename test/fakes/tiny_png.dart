import 'dart:io' show Directory, File, Platform, zlib;
import 'dart:typed_data';

/// Tiny deterministic PNG writer used by palette tests.
///
/// Encodes truecolor+alpha (bit depth 8, color type 6) with a filter byte of
/// 0 per scanline — the same shape [ArtworkPaletteExtractor.extractFromBytes]
/// must decode. Tests never depend on GPU rendering; only the engine's image
/// codec reads these bytes.
Uint8List encodePng({
  required int width,
  required int height,
  required List<int> rgba,
}) {
  if (rgba.length != width * height * 4) {
    throw ArgumentError('rgba length ${rgba.length} != $width*$height*4');
  }
  final stride = width * 4 + 1;
  final raw = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    raw[y * stride] = 0;
    for (var x = 0; x < width; x++) {
      final s = y * stride + 1 + x * 4;
      final p = (y * width + x) * 4;
      raw[s] = rgba[p];
      raw[s + 1] = rgba[p + 1];
      raw[s + 2] = rgba[p + 2];
      raw[s + 3] = rgba[p + 3];
    }
  }
  final idat = zlib.encode(raw);

  final out = BytesBuilder(copy: false);
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', idat);
  _chunk(out, 'IEND', const []);
  return out.toBytes();
}

/// Solid RGBA buffer filled with one color.
Uint8List solidRgba({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
  int a = 255,
}) {
  final out = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    out[i * 4] = r;
    out[i * 4 + 1] = g;
    out[i * 4 + 2] = b;
    out[i * 4 + 3] = a;
  }
  return out;
}

/// Rectangular-region RGBA buffer: every pixel takes the color of the region
/// covering its top-left corner. Regions are `(x, y, w, h, r, g, b, a)`.
Uint8List regionsRgba({
  required int width,
  required int height,
  required List<(int, int, int, int, int, int, int, int)> regions,
}) {
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var chosen = const (0, 0, 0, 255);
      for (final (rx, ry, rw, rh, r, g, b, a) in regions) {
        if (x >= rx && x < rx + rw && y >= ry && y < ry + rh) {
          chosen = (r, g, b, a);
          break;
        }
      }
      final i = (y * width + x) * 4;
      out[i] = chosen.$1;
      out[i + 1] = chosen.$2;
      out[i + 2] = chosen.$3;
      out[i + 3] = chosen.$4;
    }
  }
  return out;
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final len = ByteData(4)..setUint32(0, data.length);
  out.add(len.buffer.asUint8List());
  final name = type.codeUnits;
  out.add(name);
  out.add(data);
  out.add(_crc32([...name, ...data]));
}

/// Table-less bitwise CRC32 (IEEE 802.3), plenty for small test PNGs.
List<int> _crc32(List<int> data) {
  const poly = 0xEDB88320;
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ poly : crc >> 1;
    }
  }
  final result = crc ^ 0xFFFFFFFF;
  return [
    (result >> 24) & 0xFF,
    (result >> 16) & 0xFF,
    (result >> 8) & 0xFF,
    result & 0xFF,
  ];
}

/// Writes [bytes] to a fresh temp file path inside [dir], returning the file.
Future<File> writeTempFile(Directory dir, String name, List<int> bytes) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}
