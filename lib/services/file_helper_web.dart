import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveAndShareFile(String fileName, List<int> bytes) async {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [data.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Delay revoke so the browser can start the download before URL is invalidated
  await Future<void>.delayed(const Duration(milliseconds: 100));
  web.URL.revokeObjectURL(url);
}

Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('readFileBytes is not used on web');
}
