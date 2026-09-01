import 'package:firebase_auth/firebase_auth.dart';
import 'database_service.dart';

class AiBackend {
  static const String baseUrl = 'https://rag-backend-647731796550.asia-south1.run.app';

  static Future<Map<String, String>> headers([String? companyIdOverride]) async {
    final companyId = companyIdOverride ?? DatabaseService().companyId;
    if (companyId.isEmpty) {
      throw StateError('Workspace not ready: companyId is missing.');
    }
    
    final user = FirebaseAuth.instance.currentUser;
    final idToken = user != null ? await user.getIdToken() : null;
    
    return {
      'Content-Type': 'application/json',
      'x-company-id': companyId,
      if (idToken != null) 'Authorization': 'Bearer $idToken',
    };
  }
}
