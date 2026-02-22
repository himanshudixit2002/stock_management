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
  web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..click();
  web.URL.revokeObjectURL(url);
}

Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('readFileBytes is not used on web');
}
