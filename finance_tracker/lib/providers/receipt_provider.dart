import 'package:flutter/foundation.dart';

import '../models/receipt.dart';
import '../models/transaction.dart' show Pagination;
import '../services/api_client.dart';
import '../services/receipt_service.dart';

/// Manages the receipt scan history list.
class ReceiptProvider extends ChangeNotifier {
  final ReceiptService _receiptService;

  ReceiptProvider({required ApiClient apiClient})
    : _receiptService = ReceiptService(apiClient: apiClient);

  List<Receipt> _receipts = [];
  Pagination? _pagination;
  bool _isLoading = false;
  String? _error;

  List<Receipt> get receipts => _receipts;
  Pagination? get pagination => _pagination;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load receipts if not already loaded. Pass [force] to always refresh.
  Future<void> loadReceipts({bool force = false}) async {
    if (!force && _receipts.isNotEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    await _fetchReceipts();

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh the list after a new scan completes.
  ///
  /// Delegates to the same fetch as [loadReceipts] but, unlike it, does not
  /// toggle [isLoading] or notify before the fetch.
  Future<void> refresh() async {
    await _fetchReceipts();
    notifyListeners();
  }

  Future<void> _fetchReceipts() async {
    try {
      final result = await _receiptService.list();
      _receipts = result.receipts;
      _pagination = result.pagination;
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
  }

  /// Clear all cached state — called on login/register/logout.
  void reset() {
    _receipts = [];
    _pagination = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
