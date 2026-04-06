import 'dart:async';
import 'package:flutter/material.dart';
import '../models/customer_model.dart';
import '../utils/error_helpers.dart';
import '../services/database_service.dart';

class CustomerProvider extends ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _customersSubscription;

  List<CustomerModel> get customers => _customers;
  List<CustomerModel> get activeCustomers =>
      _customers.where((c) => c.isActive).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  CustomerModel? getCustomerById(String id) {
    for (final c in _customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  void initialize({required String companyId}) {
    _databaseService.setCompanyId(companyId);
    _customersSubscription?.cancel();
    _isLoading = true;
    _customersSubscription = _databaseService.getCustomers().listen(
      (customers) {
        _customers = customers;
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = friendlyError(
          error,
          fallback: 'Could not load customers.',
        );
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  void reset() {
    _customersSubscription?.cancel();
    _customersSubscription = null;
    _customers = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<CustomerModel?> addCustomer(CustomerModel customer) async {
    if (_isLoading) return null;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final id = await _databaseService.addCustomer(customer);
      _isLoading = false;
      notifyListeners();
      return customer.copyWith(id: id);
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to add customer.');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateCustomer(CustomerModel customer) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.updateCustomer(customer);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to update customer.');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteCustomer(String id) async {
    if (_isLoading) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _databaseService.deleteCustomer(id);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = friendlyError(e, fallback: 'Failed to delete customer.');
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
    _customersSubscription?.cancel();
    super.dispose();
  }
}
