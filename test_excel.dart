import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

void main() {
  var value = TextCellValue('hello');
  debugPrint('Result: ${value.toString()}');
}
