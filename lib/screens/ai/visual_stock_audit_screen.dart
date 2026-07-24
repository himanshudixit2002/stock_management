import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/ai_agent_service.dart';

class VisualStockAuditScreen extends StatefulWidget {
  const VisualStockAuditScreen({super.key});

  @override
  State<VisualStockAuditScreen> createState() => _VisualStockAuditScreenState();
}

class _VisualStockAuditScreenState extends State<VisualStockAuditScreen> {
  bool _isScanning = false;
  Map<String, dynamic>? _auditSummary;

  final List<Map<String, dynamic>> _sampleDetectedItems = [
    {'name': 'Fresh Apples (kg)', 'count': 14},
    {'name': 'Pro Laptops (15-inch)', 'count': 98},
    {'name': 'Sparkling Water (Pack of 12)', 'count': 195},
    {'name': 'Organic Whole Milk (1L)', 'count': 5},
  ];

  Future<void> _runVisualAudit() async {
    setState(() {
      _isScanning = true;
      _auditSummary = null;
    });

    // Simulate camera image capture processing time (1.2s)
    await Future.delayed(const Duration(milliseconds: 1200));

    final res = await AiAgentService.submitVisualAudit(_sampleDetectedItems);

    if (mounted) {
      setState(() {
        _auditSummary = res;
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Multimodal AI Visual Shelf Audit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('How Visual Audit Works'),
                  content: const Text(
                    'Point your device camera at a shelf or pallet. The Multimodal Vision Agent counts physical inventory items, compares them against Firestore expected stock, and logs audit discrepancies automatically.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Camera / Image Viewport Container
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.violetColor, width: 2),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isScanning ? Icons.center_focus_strong : Icons.camera_alt_rounded,
                          size: 56,
                          color: AppTheme.violetColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isScanning
                              ? 'Multimodal Vision Model Scanning Shelf...'
                              : 'Tap below to capture shelf & run AI stock audit',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  if (_isScanning)
                    const Positioned.fill(
                      child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryLight),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Scan Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isScanning ? null : _runVisualAudit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.violetColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.document_scanner_rounded),
                label: Text(
                  _isScanning ? 'Processing Vision Model...' : 'Capture & Audit Shelf Inventory',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Audit Summary Results
            if (_auditSummary != null) ...[
              Text(
                'Audit Results & Ledger Updates',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Audited ${_auditSummary!['audited_items_count']} items at ${_auditSummary!['timestamp']?.toString().split('.').first}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),

              ...(_auditSummary!['results'] as List? ?? []).map((res) {
                final disc = res['discrepancy'] ?? 0;
                final isMatch = disc == 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isMatch ? AppTheme.successColor.withValues(alpha: 0.3) : AppTheme.dangerColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isMatch ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        color: isMatch ? AppTheme.successColor : AppTheme.dangerColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              res['product_name'] ?? 'Product',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              'Expected: ${res['expected_stock']} | Vision Counted: ${res['visual_counted_stock']}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isMatch ? AppTheme.successColor.withValues(alpha: 0.1) : AppTheme.dangerColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isMatch ? 'PERFECT MATCH' : 'DIFF: $disc',
                          style: TextStyle(
                            color: isMatch ? AppTheme.successColor : AppTheme.dangerColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
