import re

with open('lib/screens/ai/rag_chat_screen.dart', 'r') as f:
    content = f.read()

# I will write a custom widget classes for the new responseKinds and append them to the file.
new_widgets = """
class _PreviewActionCard extends StatefulWidget {
  final Map<String, dynamic> pendingAction;
  final Function(String) onAction;
  
  const _PreviewActionCard({required this.pendingAction, required this.onAction});

  @override
  State<_PreviewActionCard> createState() => _PreviewActionCardState();
}

class _PreviewActionCardState extends State<_PreviewActionCard> {
  bool _responded = false;

  @override
  Widget build(BuildContext context) {
    final qty = widget.pendingAction['qty_change'] ?? 0;
    final productName = widget.pendingAction['product_name'] ?? 'Item';
    
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "⚡ Suggested Action",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            qty >= 0 ? "Add $qty units to $productName" : "Deduct ${qty.abs()} units from $productName",
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _responded ? null : () {
                    setState(() => _responded = true);
                    widget.onAction("cancel");
                  },
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _responded ? null : () {
                    setState(() => _responded = true);
                    widget.onAction("confirm");
                  },
                  child: const Text("Confirm"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _ProductDetailCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final Function(String) onAction;
  
  const _ProductDetailCard({required this.product, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final qty = product['quantity'] ?? 0;
    final threshold = product['min_threshold'] ?? 10;
    final days = product['days_of_supply'] ?? 0;
    final name = product['name'] ?? 'Item';
    
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Stock: $qty", style: TextStyle(fontSize: 13)),
              Text("Threshold: $threshold", style: TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: threshold > 0 ? (qty / (threshold * 2)).clamp(0.0, 1.0) : 1.0,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            color: qty <= threshold ? Colors.orange : Colors.green,
          ),
          const SizedBox(height: 8),
          Text("$days days of cover", style: TextStyle(fontSize: 12, color: AppTheme.textSec(context))),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onAction("deduct 1 from $name"),
                  child: const Text("Deduct"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => onAction("add 1 to $name"),
                  child: const Text("Add"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class _NoHistoryCallToAction extends StatelessWidget {
  final Function(String) onAction;
  
  const _NoHistoryCallToAction({required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(height: 8),
          const Text("No movement recorded. Start tracking stock to get insights.", textAlign: TextAlign.center),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => onAction("audit inventory"),
            child: const Text("Start tracking stock"),
          )
        ],
      ),
    );
  }
}
"""

if "_PreviewActionCard" not in content:
    content += "\n" + new_widgets

with open('lib/screens/ai/rag_chat_screen.dart', 'w') as f:
    f.write(content)
