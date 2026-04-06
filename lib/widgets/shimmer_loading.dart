import 'package:flutter/material.dart';
import '../config/theme.dart';

enum ShimmerLayout { card, stat, listTile }

class ShimmerLoading extends StatefulWidget {
  final int itemCount;
  final ShimmerLayout layout;

  const ShimmerLoading({
    super.key,
    this.itemCount = 5,
    this.layout = ShimmerLayout.card,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _curved = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return switch (widget.layout) {
          ShimmerLayout.stat => _buildStatLayout(),
          ShimmerLayout.listTile => _buildListTileLayout(),
          ShimmerLayout.card => _buildCardLayout(),
        };
      },
    );
  }

  Widget _buildCardLayout() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: widget.itemCount,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _shimmerBox(height: 80, borderRadius: 20),
      ),
    );
  }

  Widget _buildStatLayout() {
    return Row(
      children: List.generate(
        3,
        (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
            child: _shimmerBox(height: 100, borderRadius: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildListTileLayout() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: widget.itemCount,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            _shimmerBox(width: 44, height: 44, borderRadius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.7,
                    alignment: Alignment.centerLeft,
                    child: _shimmerBox(height: 14, borderRadius: 8),
                  ),
                  const SizedBox(height: 6),
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    alignment: Alignment.centerLeft,
                    child: _shimmerBox(height: 10, borderRadius: 8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox({
    double? width,
    required double height,
    required double borderRadius,
  }) {
    final value = _curved.value;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * value, 0),
          end: Alignment(1.0 + 2.0 * value, 0),
          colors: [
            AppTheme.dividerC(context),
            AppTheme.inputFill(context),
            AppTheme.dividerC(context),
          ],
        ),
      ),
    );
  }
}
