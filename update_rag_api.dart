import 'dart:io';

void main() {
  final file = File('lib/services/rag_api_service.dart');
  var content = file.readAsStringSync();
  
  content = content.replaceFirst(
    "import 'database_service.dart';",
    "import 'database_service.dart';\nimport 'ai_backend.dart';"
  );
  
  content = content.replaceAll(
    "static const String _baseUrl =\n      'https://rag-backend-647731796550.asia-south1.run.app';",
    ""
  );

  content = content.replaceAll(
    "static Map<String, String> _headers() {\n    final companyId = DatabaseService().companyId;\n    return {\n      'Content-Type': 'application/json',\n      if (companyId.isNotEmpty) 'x-company-id': companyId,\n    };\n  }",
    ""
  );

  content = content.replaceAll("Uri.parse('\$_baseUrl/api/chat')", "Uri.parse('\${AiBackend.baseUrl}/api/chat')");
  content = content.replaceAll("Uri.parse('\$_baseUrl/api/chat/stream')", "Uri.parse('\${AiBackend.baseUrl}/api/chat/stream')");
  content = content.replaceAll("Uri.parse('\$_baseUrl/api/inventory/sync')", "Uri.parse('\${AiBackend.baseUrl}/api/inventory/sync')");
  content = content.replaceAll("Uri.parse('\$_baseUrl/api/cache/clear')", "Uri.parse('\${AiBackend.baseUrl}/api/cache/clear')");
  
  content = content.replaceAll("_headers()", "AiBackend.headers()");

  file.writeAsStringSync(content);
}
