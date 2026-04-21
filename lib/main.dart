import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress trackpad assertion on Flutter web — a known framework bug
  // where PointerEventConverter rejects PointerDeviceKind.trackpad.
  if (kIsWeb) {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('PointerDeviceKind.trackpad')) return;
      originalOnError?.call(details);
    };
  }

  FlutterError.onError ??= FlutterError.presentError;
  final previousOnError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if (kReleaseMode) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      return;
    }
    previousOnError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught platform error: $error\n$stack');
    return true;
  };

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFFFFFFFF),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  if (!kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  runApp(const StockManagementApp());
}
