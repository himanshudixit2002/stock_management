import '../models/landed_cost_model.dart';

/// Spreads a sheet's charges across its lines.
///
/// Pure and synchronous so the allocation can be shown live in the editor and
/// unit-tested without Firestore, and so the same numbers the user approved are
/// the ones written.
class LandedCostAllocator {
  LandedCostAllocator._();

  /// [lines] with `allocatedAmount` filled in from [charges].
  ///
  /// Every charge is allocated on its own basis and the results are summed, so
  /// freight can go by weight while duty goes by value on the same sheet.
  ///
  /// Rounding residue is given to the largest line rather than dropped: the
  /// allocated amounts must add up to the charges exactly, or the landed value
  /// stops reconciling to what was actually paid.
  static List<LandedCostLine> allocate({
    required List<LandedCostLine> lines,
    required List<LandedCostCharge> charges,
  }) {
    if (lines.isEmpty) return const [];

    final totals = List<double>.filled(lines.length, 0);

    for (final charge in charges) {
      if (charge.amount == 0) continue;
      final weights = _weightsFor(lines, charge.basis);
      final weightTotal = weights.fold(0.0, (acc, w) => acc + w);
      if (weightTotal <= 0) {
        // Nothing to weigh against — an all-zero-value receipt, say. Splitting
        // equally is the only allocation that does not silently discard the
        // charge.
        final share = charge.amount / lines.length;
        for (var i = 0; i < lines.length; i++) {
          totals[i] += share;
        }
        continue;
      }
      for (var i = 0; i < lines.length; i++) {
        totals[i] += charge.amount * weights[i] / weightTotal;
      }
    }

    final rounded = totals.map(_round).toList();
    final chargeTotal = _round(
      charges.fold(0.0, (acc, c) => acc + c.amount),
    );
    final allocated = _round(rounded.fold(0.0, (acc, v) => acc + v));
    final residue = _round(chargeTotal - allocated);
    if (residue != 0) {
      rounded[_largestLineIndex(lines)] = _round(
        rounded[_largestLineIndex(lines)] + residue,
      );
    }

    return [
      for (var i = 0; i < lines.length; i++)
        lines[i].copyWith(allocatedAmount: rounded[i]),
    ];
  }

  static List<double> _weightsFor(
    List<LandedCostLine> lines,
    AllocationBasis basis,
  ) {
    switch (basis) {
      case AllocationBasis.value:
        return [
          for (final l in lines) l.baseValue > 0 ? l.baseValue : 0.0,
        ];
      case AllocationBasis.quantity:
        return [
          for (final l in lines) l.quantity > 0 ? l.quantity.toDouble() : 0.0,
        ];
      case AllocationBasis.equal:
        return [for (final _ in lines) 1.0];
    }
  }

  /// The line the rounding residue is parked on: the largest by value, falling
  /// back to the first. Putting it on the biggest line makes it the smallest
  /// relative distortion available.
  static int _largestLineIndex(List<LandedCostLine> lines) {
    var best = 0;
    var bestValue = double.negativeInfinity;
    for (var i = 0; i < lines.length; i++) {
      final value = lines[i].baseValue;
      if (value > bestValue) {
        bestValue = value;
        best = i;
      }
    }
    return best;
  }

  /// One cost price per product, weighted by units received.
  ///
  /// A receipt may carry the same product on more than one line — a purchase
  /// order legitimately can — and each line has its own landed cost. Writing
  /// them one after another would leave whichever happened to be last as the
  /// product's cost price, which is arbitrary. The units-weighted average is
  /// the cost the receipt actually landed the product at.
  static List<ProductCostChange> aggregateByProduct(
    List<LandedCostLine> lines,
  ) {
    final order = <String>[];
    final grouped = <String, List<LandedCostLine>>{};
    for (final line in lines) {
      if (line.productId.isEmpty) continue;
      if (grouped.putIfAbsent(line.productId, () => []).isEmpty) {
        order.add(line.productId);
      }
      grouped[line.productId]!.add(line);
    }

    return [
      for (final productId in order)
        _changeFor(productId, grouped[productId]!),
    ];
  }

  static ProductCostChange _changeFor(
    String productId,
    List<LandedCostLine> lines,
  ) {
    var units = 0;
    var weighted = 0.0;
    for (final line in lines) {
      final quantity = line.quantity > 0 ? line.quantity : 0;
      units += quantity;
      weighted += line.landedUnitCost * quantity;
    }

    // A zero-quantity receipt has no weights to average by. Falling back to the
    // plain mean keeps a cost of the right magnitude rather than dividing by
    // zero and wiping the product's cost to nothing.
    final landed = units == 0
        ? lines.fold(0.0, (acc, l) => acc + l.landedUnitCost) / lines.length
        : weighted / units;

    return ProductCostChange(
      productId: productId,
      productName: lines.first.productName,
      quantity: units,
      landedUnitCost: _round(landed),
      // Every line of a product shares the cost it had before the sheet was
      // applied, so a reversal restores the same number whichever is read.
      previousUnitCost: lines.first.previousUnitCost,
    );
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}

/// What one product's cost price becomes when a sheet is applied, and what it
/// goes back to when the sheet is reversed.
class ProductCostChange {
  const ProductCostChange({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.landedUnitCost,
    required this.previousUnitCost,
  });

  final String productId;
  final String productName;

  /// Units of this product across the whole receipt.
  final int quantity;

  final double landedUnitCost;
  final double previousUnitCost;
}
