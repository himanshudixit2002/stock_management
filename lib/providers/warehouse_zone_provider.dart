import 'dart:async';
import 'package:flutter/material.dart';
import '../models/warehouse_zone_model.dart';
import '../services/database_service.dart';
import '../utils/error_helpers.dart';

class WarehouseZoneProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<WarehouseZoneModel> _zones = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _zonesSubscription;

  List<WarehouseZoneModel> get zones => _zones;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<WarehouseZoneModel> getZonesByLocation(String locationName) {
    return _zones
        .where(
          (z) => z.locationName.toLowerCase() == locationName.toLowerCase(),
        )
        .toList();
  }

  void reset() {
    _zonesSubscription?.cancel();
    _zonesSubscription = null;
    _zones = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _zonesSubscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _zonesSubscription = _databaseService.getWarehouseZones().listen(
      (zones) {
        _zones = zones;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load warehouse zones.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<WarehouseZoneModel?> addZone(WarehouseZoneModel zone) async {
    if (_isLoading) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final newId = await _databaseService.addWarehouseZone(zone);
      _isLoading = false;
      notifyListeners();
      return zone.copyWith(id: newId);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to add zone.');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateZone(WarehouseZoneModel zone) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateWarehouseZone(zone);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update zone.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteZone(String zoneId) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.deleteWarehouseZone(zoneId);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete zone.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _zonesSubscription?.cancel();
    super.dispose();
  }
}
