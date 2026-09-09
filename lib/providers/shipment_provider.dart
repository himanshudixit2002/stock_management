import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/shipment_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

/// Pick lists, packages and dispatches.
class ShipmentProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<ShipmentModel> _shipments = [];
  bool _isLoading = false;
  bool _isBusy = false;
  String? _errorMessage;
  StreamSubscription? _subscription;

  List<ShipmentModel> get shipments => _shipments;

  bool get isLoading => _isLoading;

  bool get isBusy => _isBusy;

  String? get errorMessage => _errorMessage;

  /// Anything still being worked on: on a trolley, in a box, or on a van.
  List<ShipmentModel> get open => _shipments
      .where(
        (s) =>
            s.status != ShipmentStatus.delivered &&
            s.status != ShipmentStatus.cancelled,
      )
      .toList(growable: false);

  List<ShipmentModel> get toPick => _shipments
      .where(
        (s) =>
            s.status == ShipmentStatus.draft ||
            s.status == ShipmentStatus.picking,
      )
      .toList(growable: false);

  List<ShipmentModel> get readyToDispatch => _shipments
      .where((s) => s.status == ShipmentStatus.packed)
      .toList(growable: false);

  List<ShipmentModel> get inTransit => _shipments
      .where((s) => s.status == ShipmentStatus.dispatched)
      .toList(growable: false);

  /// Every shipment raised against one sales order, newest first.
  List<ShipmentModel> forOrder(String salesOrderId) => _shipments
      .where((s) => s.salesOrderId == salesOrderId)
      .toList(growable: false);

  /// Units already committed to shipments for a line on [salesOrderId], so a
  /// second shipment cannot pick the same units twice.
  int committedForOrderLine(String salesOrderId, int orderItemIndex) {
    var total = 0;
    for (final shipment in forOrder(salesOrderId)) {
      if (shipment.status == ShipmentStatus.cancelled) continue;
      for (final line in shipment.lines) {
        if (line.orderItemIndex == orderItemIndex) {
          total += line.orderedQuantity;
        }
      }
    }
    return total;
  }

  ShipmentModel? byId(String id) {
    final idx = _shipments.indexWhere((s) => s.id == id);
    return idx == -1 ? null : _shipments[idx];
  }

  void reset() {
    _subscription?.cancel();
    _subscription = null;
    _shipments = [];
    _isLoading = false;
    _isBusy = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _subscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _subscription = _databaseService.getShipments().listen(
      (shipments) {
        _shipments = shipments;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load shipments.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<String?> addShipment(ShipmentModel shipment) async {
    final result = await _run(
      () => _databaseService.addShipment(shipment),
      'Failed to save the shipment.',
    );
    return result is String ? result : null;
  }

  Future<bool> updateShipment(ShipmentModel shipment) async {
    final result = await _run(
      () => _databaseService.updateShipment(shipment),
      'Failed to update the shipment.',
    );
    return result != null;
  }

  Future<bool> deleteShipment(String id) async {
    final result = await _run(
      () => _databaseService.deleteShipment(id),
      'Failed to delete the shipment.',
    );
    return result != null;
  }

  /// Stamps a shipment dispatched. The stock itself is moved by the sales order
  /// path before this is called — see [DatabaseService.markShipmentDispatched].
  Future<bool> markDispatched({
    required ShipmentModel shipment,
    required String userId,
    required String userName,
  }) async {
    final result = await _run(
      () => _databaseService.markShipmentDispatched(
        shipment: shipment,
        userId: userId,
        userName: userName,
      ),
      'Could not mark the shipment dispatched.',
    );
    return result != null;
  }

  Future<Object?> _run(
    Future<Object?> Function() action,
    String fallback,
  ) async {
    if (_isBusy) return null;
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await action() ?? true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: fallback);
      return null;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
