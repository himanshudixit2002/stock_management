import 'database_service.dart';

class AiBackend {
  static const String baseUrl = 'https://rag-backend-647731796550.asia-south1.run.app';

  static Map<String, String> headers([String? companyIdOverride]) {
    final companyId = companyIdOverride ?? DatabaseService().companyId;
    if (companyId.isEmpty) {
      throw StateError('Workspace not ready: companyId is missing.');
    }
    return {
      'Content-Type': 'application/json',
      'x-company-id': companyId,
    };
  }
}
