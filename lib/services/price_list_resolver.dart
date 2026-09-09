import '../models/price_list_model.dart';
import '../models/product_model.dart';

/// Why a line ended up at the price it did.
enum PriceSource {
  /// The product's own selling price — no list applied.
  catalog,

  /// A per-product entry on the customer's price list.
  listEntry,

  /// The list's blanket discount, because the product had no entry.
  listDefault,
}

/// The price a customer pays for one product, and how it was arrived at.
class ResolvedPrice {
  const ResolvedPrice({
    required this.unitPrice,
    required this.source,
    required this.listId,
    required this.listName,
    required this.catalogPrice,
  });

  final double unitPrice;
  final PriceSource source;

  /// The list that produced this price, empty when [source] is
  /// [PriceSource.catalog].
  final String listId;
  final String listName;

  /// The product's undiscounted selling price, so the UI can show what was
  /// given away.
  final double catalogPrice;

  bool get isDiscounted => unitPrice < catalogPrice - 0.005;

  /// The amount off per unit. Zero when the list priced above catalog, which is
  /// legitimate for a margin-over-cost list on a loss-leading product.
  double get discountAmount {
    final diff = catalogPrice - unitPrice;
    return diff > 0 ? diff : 0;
  }

  double get discountPercent {
    if (catalogPrice <= 0) return 0;
    return discountAmount / catalogPrice * 100;
  }

  String get sourceLabel => switch (source) {
    PriceSource.catalog => 'Catalog price',
    PriceSource.listEntry => 'Price list',
    PriceSource.listDefault => 'List discount',
  };
}

/// Resolves what a given customer pays for a given product.
///
/// One shared implementation on purpose: invoicing and the POS both need this
/// answer, and two implementations of "what does this customer pay" is how a
/// quote and its invoice end up disagreeing.
///
/// Resolution order, first match wins:
///   1. a per-product entry on an applicable list (highest quantity slab),
///   2. that list's blanket discount,
///   3. the product's own selling price.
class PriceListResolver {
  const PriceListResolver(this.lists);

  /// Every price list in the workspace. Filtered per call rather than at
  /// construction so a list edited mid-session takes effect immediately.
  final List<PriceListModel> lists;

  /// The applicable list for [customerId], or null.
  ///
  /// When a customer is on more than one list — which the data model allows and
  /// people do by accident — the one giving the better headline discount wins.
  /// Picking arbitrarily would make the price depend on document order.
  PriceListModel? listFor(String customerId) {
    if (customerId.isEmpty) return null;
    PriceListModel? best;
    for (final list in lists) {
      if (!list.isApplicable || !list.appliesTo(customerId)) continue;
      if (best == null ||
          list.defaultDiscountPercent > best.defaultDiscountPercent) {
        best = list;
      }
    }
    return best;
  }

  /// What [customerId] pays for [product] at [quantity].
  ResolvedPrice resolve({
    required ProductModel product,
    required String customerId,
    int quantity = 1,
  }) {
    final catalog = product.sellingPrice;
    final list = listFor(customerId);
    if (list == null) {
      return ResolvedPrice(
        unitPrice: catalog,
        source: PriceSource.catalog,
        listId: '',
        listName: '',
        catalogPrice: catalog,
      );
    }

    final entry = list.entryFor(product.id, quantity: quantity);
    if (entry != null) {
      final priced = entry.priceFor(
        sellingPrice: catalog,
        costPrice: product.costPrice,
        quantity: quantity,
      );
      if (priced != null) {
        return ResolvedPrice(
          unitPrice: _round(priced),
          source: PriceSource.listEntry,
          listId: list.id,
          listName: list.name,
          catalogPrice: catalog,
        );
      }
    }

    if (list.defaultDiscountPercent > 0) {
      final discounted =
          catalog * (1 - list.defaultDiscountPercent.clamp(0, 100) / 100);
      return ResolvedPrice(
        unitPrice: _round(discounted < 0 ? 0 : discounted),
        source: PriceSource.listDefault,
        listId: list.id,
        listName: list.name,
        catalogPrice: catalog,
      );
    }

    return ResolvedPrice(
      unitPrice: catalog,
      source: PriceSource.catalog,
      listId: list.id,
      listName: list.name,
      catalogPrice: catalog,
    );
  }

  /// Rounded to the cent, the smallest unit anything here is billed in.
  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
