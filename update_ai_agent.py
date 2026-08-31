import re

with open('lib/services/ai_agent_service.dart', 'r') as f:
    content = f.read()

content = content.replace("import 'database_service.dart';", "import 'database_service.dart';\nimport 'ai_backend.dart';")
content = re.sub(r"static String get _baseUrl \{\s*return 'https://rag-backend-647731796550.asia-south1.run.app';\s*\}", "", content)
content = re.sub(r"static Map<String, String> _getHeaders\(\[String\? companyId\]\) \{[\s\S]*?\}", "", content)

content = content.replace("Uri.parse('$_baseUrl", "Uri.parse('${AiBackend.baseUrl}")
content = content.replace("_getHeaders()", "AiBackend.headers()")
content = content.replace("_getHeaders(companyId)", "AiBackend.headers(companyId)")

with open('lib/services/ai_agent_service.dart', 'w') as f:
    f.write(content)
