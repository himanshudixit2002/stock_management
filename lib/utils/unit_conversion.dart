class UnitSplit {
  final int packs;
  final int pieces;

  const UnitSplit({required this.packs, required this.pieces});
}

int normalizeUnitsPerPack(int unitsPerPack) {
  return unitsPerPack <= 1 ? 1 : unitsPerPack;
}

int toBaseQuantity({
  required int packs,
  required int pieces,
  required int unitsPerPack,
}) {
  final normalized = normalizeUnitsPerPack(unitsPerPack);
  final safePacks = packs < 0 ? 0 : packs;
  final safePieces = pieces < 0 ? 0 : pieces;
  return (safePacks * normalized) + safePieces;
}

UnitSplit splitBaseQuantity({
  required int baseQuantity,
  required int unitsPerPack,
}) {
  final normalized = normalizeUnitsPerPack(unitsPerPack);
  final safeBase = baseQuantity < 0 ? 0 : baseQuantity;
  if (normalized <= 1) {
    return UnitSplit(packs: 0, pieces: safeBase);
  }
  return UnitSplit(
    packs: safeBase ~/ normalized,
    pieces: safeBase % normalized,
  );
}

String formatQuantityWithUnits({
  required int baseQuantity,
  required String baseUnit,
  required String packUnit,
  required int unitsPerPack,
}) {
  final normalized = normalizeUnitsPerPack(unitsPerPack);
  final safeBase = baseQuantity < 0 ? 0 : baseQuantity;
  if (normalized <= 1) return '$safeBase $baseUnit';
  final split = splitBaseQuantity(
    baseQuantity: safeBase,
    unitsPerPack: normalized,
  );
  if (split.packs == 0) return '${split.pieces} $baseUnit';
  if (split.pieces == 0) return '${split.packs} $packUnit';
  return '${split.packs} $packUnit ${split.pieces} $baseUnit';
}
