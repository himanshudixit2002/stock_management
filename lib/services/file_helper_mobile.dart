import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveAndShareFile(String fileName, List<int> bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final filePath = '${directory.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(bytes);
  await Share.shareXFiles(
    [XFile(filePath)],
    subject: 'Stock Report',
    text: 'Stock Management Report',
  );
}

Future<Uint8List> readFileBytes(String path) async {
  final file = File(path);
  return await file.readAsBytes();
}
