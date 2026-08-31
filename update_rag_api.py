import re

with open('lib/services/rag_api_service.dart', 'r') as f:
    content = f.read()

content = content.replace("import 'database_service.dart';", "import 'database_service.dart';\nimport 'ai_backend.dart';")
content = re.sub(r"static const String _baseUrl =\s*'https://rag-backend-647731796550.asia-south1.run.app';", "", content)
content = re.sub(r"static Map<String, String> _headers\(\) \{[\s\S]*?\}", "", content)

content = content.replace("Uri.parse('$_baseUrl/api/chat')", "Uri.parse('${AiBackend.baseUrl}/api/chat')")
content = content.replace("Uri.parse('$_baseUrl/api/chat/stream')", "Uri.parse('${AiBackend.baseUrl}/api/chat/stream')")
content = content.replace("Uri.parse('$_baseUrl/api/inventory/sync')", "Uri.parse('${AiBackend.baseUrl}/api/inventory/sync')")
content = content.replace("Uri.parse('$_baseUrl/api/cache/clear')", "Uri.parse('${AiBackend.baseUrl}/api/cache/clear')")

content = content.replace("_headers()", "AiBackend.headers()")

with open('lib/services/rag_api_service.dart', 'w') as f:
    f.write(content)
