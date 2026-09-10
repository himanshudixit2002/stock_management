// GENERATED — DO NOT EDIT BY HAND.
//
// Source: rag_backend/openapi.json (API version 1.0.0)
// Regenerate: cd rag_backend && venv/bin/python tools/generate_client.py
//
// These are data classes for the inventory agent API, generated so that the
// field names on the wire exist in exactly one place. CI regenerates this file
// and fails if the result differs from what is committed, which is what stops
// a field renamed on the server from becoming a silent null here.
//
// ignore_for_file: type=lint

/// `ChatMessage` from the API contract.
class ChatMessage {
  final String content;
  final String role;

  const ChatMessage({
    required this.content,
    required this.role,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        content: json['content'] as String,
        role: json['role'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'content': content,
        'role': role,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'content',
    'role',
  ];
}

/// `GuardrailValidationRequest` from the API contract.
class GuardrailValidationRequest {
  final String actionType;
  final String? barcode;
  final Map<String, dynamic> payload;

  const GuardrailValidationRequest({
    required this.actionType,
    this.barcode,
    required this.payload,
  });

  factory GuardrailValidationRequest.fromJson(Map<String, dynamic> json) => GuardrailValidationRequest(
        actionType: json['action_type'] as String,
        barcode: json['barcode'] as String?,
        payload: (json['payload'] == null ? null : Map<String, dynamic>.from(json['payload'] as Map)) ?? const {},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'action_type': actionType,
        'barcode': barcode,
        'payload': payload,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'action_type',
    'barcode',
    'payload',
  ];
}

/// `InventorySyncRequest` from the API contract.
class InventorySyncRequest {
  final List<Map<String, dynamic>> products;

  const InventorySyncRequest({
    required this.products,
  });

  factory InventorySyncRequest.fromJson(Map<String, dynamic> json) => InventorySyncRequest(
        products: (json['products'] as List<dynamic>?)?.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'products': products,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'products',
  ];
}

/// `POApprovalRequest` from the API contract.
class POApprovalRequest {
  final String poId;

  const POApprovalRequest({
    required this.poId,
  });

  factory POApprovalRequest.fromJson(Map<String, dynamic> json) => POApprovalRequest(
        poId: json['po_id'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'po_id': poId,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'po_id',
  ];
}

/// `ProductIngestItem` from the API contract.
class ProductIngestItem {
  final String barcode;
  final String category;
  final double costPrice;
  final int leadTimeDays;
  final int minThreshold;
  final String name;
  final double salesVelocity;
  final double sellingPrice;
  final int stock;

  const ProductIngestItem({
    required this.barcode,
    this.category = "General",
    this.costPrice = 0.0,
    this.leadTimeDays = 3,
    this.minThreshold = 10,
    required this.name,
    this.salesVelocity = 0.0,
    this.sellingPrice = 0.0,
    required this.stock,
  });

  factory ProductIngestItem.fromJson(Map<String, dynamic> json) => ProductIngestItem(
        barcode: json['barcode'] as String,
        category: json['category'] as String? ?? "General",
        costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0.0,
        leadTimeDays: json['lead_time_days'] as int? ?? 3,
        minThreshold: json['min_threshold'] as int? ?? 10,
        name: json['name'] as String,
        salesVelocity: (json['sales_velocity'] as num?)?.toDouble() ?? 0.0,
        sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0.0,
        stock: json['stock'] as int,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'barcode': barcode,
        'category': category,
        'cost_price': costPrice,
        'lead_time_days': leadTimeDays,
        'min_threshold': minThreshold,
        'name': name,
        'sales_velocity': salesVelocity,
        'selling_price': sellingPrice,
        'stock': stock,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'barcode',
    'category',
    'cost_price',
    'lead_time_days',
    'min_threshold',
    'name',
    'sales_velocity',
    'selling_price',
    'stock',
  ];
}

/// `ProductIngestRequest` from the API contract.
class ProductIngestRequest {
  final List<ProductIngestItem> products;

  const ProductIngestRequest({
    required this.products,
  });

  factory ProductIngestRequest.fromJson(Map<String, dynamic> json) => ProductIngestRequest(
        products: (json['products'] as List<dynamic>?)?.map((dynamic e) => ProductIngestItem.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'products': products.map((e) => e.toJson()).toList(),
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'products',
  ];
}

/// `QueryRequest` from the API contract.
class QueryRequest {
  final String businessType;
  final String companyId;
  final String? context;
  final List<ChatMessage>? history;
  final String question;
  final String? sessionId;

  const QueryRequest({
    this.businessType = "retail_store",
    this.companyId = "default",
    this.context,
    this.history,
    required this.question,
    this.sessionId,
  });

  factory QueryRequest.fromJson(Map<String, dynamic> json) => QueryRequest(
        businessType: json['business_type'] as String? ?? "retail_store",
        companyId: json['company_id'] as String? ?? "default",
        context: json['context'] as String?,
        history: (json['history'] as List<dynamic>?)?.map((dynamic e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        question: json['question'] as String,
        sessionId: json['session_id'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'business_type': businessType,
        'company_id': companyId,
        'context': context,
        'history': history?.map((e) => e.toJson()).toList(),
        'question': question,
        'session_id': sessionId,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'business_type',
    'company_id',
    'context',
    'history',
    'question',
    'session_id',
  ];
}

/// `QueryResponse` from the API contract.
class QueryResponse {
  final Map<String, dynamic>? analyticsData;
  final String answer;
  final String? answeredBy;
  final List<Map<String, dynamic>>? clarificationOptions;
  final List<Map<String, dynamic>> executedActions;
  final String intent;
  final List<Map<String, dynamic>>? items;
  final Map<String, dynamic>? pendingAction;
  final String responseKind;
  final int retries;
  final List<Map<String, dynamic>>? updatedCatalog;

  const QueryResponse({
    this.analyticsData,
    required this.answer,
    this.answeredBy,
    this.clarificationOptions,
    this.executedActions = const [],
    this.intent = "KNOWLEDGE",
    this.items,
    this.pendingAction,
    this.responseKind = "prose",
    this.retries = 0,
    this.updatedCatalog,
  });

  factory QueryResponse.fromJson(Map<String, dynamic> json) => QueryResponse(
        analyticsData: json['analytics_data'] == null ? null : Map<String, dynamic>.from(json['analytics_data'] as Map),
        answer: json['answer'] as String,
        answeredBy: json['answered_by'] as String?,
        clarificationOptions: (json['clarification_options'] as List<dynamic>?)?.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList(),
        executedActions: (json['executed_actions'] as List<dynamic>?)?.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList() ?? const [],
        intent: json['intent'] as String? ?? "KNOWLEDGE",
        items: (json['items'] as List<dynamic>?)?.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList(),
        pendingAction: json['pending_action'] == null ? null : Map<String, dynamic>.from(json['pending_action'] as Map),
        responseKind: json['response_kind'] as String? ?? "prose",
        retries: json['retries'] as int? ?? 0,
        updatedCatalog: (json['updated_catalog'] as List<dynamic>?)?.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'analytics_data': analyticsData,
        'answer': answer,
        'answered_by': answeredBy,
        'clarification_options': clarificationOptions,
        'executed_actions': executedActions,
        'intent': intent,
        'items': items,
        'pending_action': pendingAction,
        'response_kind': responseKind,
        'retries': retries,
        'updated_catalog': updatedCatalog,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'analytics_data',
    'answer',
    'answered_by',
    'clarification_options',
    'executed_actions',
    'intent',
    'items',
    'pending_action',
    'response_kind',
    'retries',
    'updated_catalog',
  ];
}

/// `SwarmEventRequest` from the API contract.
class SwarmEventRequest {
  final String eventName;
  final Map<String, dynamic> payload;

  const SwarmEventRequest({
    required this.eventName,
    this.payload = const {},
  });

  factory SwarmEventRequest.fromJson(Map<String, dynamic> json) => SwarmEventRequest(
        eventName: json['event_name'] as String,
        payload: (json['payload'] == null ? null : Map<String, dynamic>.from(json['payload'] as Map)) ?? const {},
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'event_name': eventName,
        'payload': payload,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'event_name',
    'payload',
  ];
}

/// `SwarmQueryRequest` from the API contract.
class SwarmQueryRequest {
  final String query;

  const SwarmQueryRequest({
    required this.query,
  });

  factory SwarmQueryRequest.fromJson(Map<String, dynamic> json) => SwarmQueryRequest(
        query: json['query'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'query': query,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'query',
  ];
}

/// `VisualAuditItem` from the API contract.
class VisualAuditItem {
  final int count;
  final String name;

  const VisualAuditItem({
    required this.count,
    required this.name,
  });

  factory VisualAuditItem.fromJson(Map<String, dynamic> json) => VisualAuditItem(
        count: json['count'] as int,
        name: json['name'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'count': count,
        'name': name,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'count',
    'name',
  ];
}

/// `VisualAuditRequest` from the API contract.
class VisualAuditRequest {
  final List<VisualAuditItem> detectedItems;

  const VisualAuditRequest({
    required this.detectedItems,
  });

  factory VisualAuditRequest.fromJson(Map<String, dynamic> json) => VisualAuditRequest(
        detectedItems: (json['detected_items'] as List<dynamic>?)?.map((dynamic e) => VisualAuditItem.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'detected_items': detectedItems.map((e) => e.toJson()).toList(),
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'detected_items',
  ];
}

/// `VoiceCommandRequest` from the API contract.
class VoiceCommandRequest {
  final String speechText;

  const VoiceCommandRequest({
    required this.speechText,
  });

  factory VoiceCommandRequest.fromJson(Map<String, dynamic> json) => VoiceCommandRequest(
        speechText: json['speech_text'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'speech_text': speechText,
      };

  /// Every wire key this model reads, so a contract test can
  /// assert the hand-written parser reads the same ones.
  static const List<String> wireKeys = <String>[
    'speech_text',
  ];
}
