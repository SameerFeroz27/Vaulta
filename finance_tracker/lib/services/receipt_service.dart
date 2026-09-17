import 'dart:typed_data';

import '../models/receipt.dart';
import '../models/transaction.dart' show Pagination;
import 'api_client.dart';

/// Handles receipt scanning and bank message API calls.
class ReceiptService {
  final ApiClient apiClient;

  ReceiptService({required this.apiClient});

  /// Upload a receipt image for AI scanning.
  ///
  /// [fileBytes] is the raw image content and [filename] is the file name.
  /// Returns a [ScanResult] with the receipt ID and initial status.
  Future<ScanResult> scanImage(
    Uint8List fileBytes, {
    required String filename,
    String? mimeType,
    String inputType = 'image',
    String? transactionType,
  }) async {
    final fields = <String, String>{'inputType': inputType};
    if (transactionType != null) fields['transactionType'] = transactionType;

    final data = await apiClient.multipartPost(
      '/receipts/scan',
      fieldName: 'receipt',
      fileBytes: fileBytes,
      filename: filename,
      contentType: mimeType,
      fields: fields,
    );
    return ScanResult.fromJson(data as Map<String, dynamic>);
  }

  /// Submit a bank SMS/message for AI parsing.
  Future<ScanResult> bankMessage(String message) async {
    final data = await apiClient.post(
      '/receipts/bank-message',
      body: {'message': message},
    );
    return ScanResult.fromJson(data as Map<String, dynamic>);
  }

  /// Get a single receipt's status and linked transaction.
  /// Used for polling after upload.
  Future<ReceiptDetail> get(int id) async {
    final data = await apiClient.get('/receipts/$id');
    return ReceiptDetail.fromJson(data as Map<String, dynamic>);
  }

  /// List scan history with pagination.
  Future<({List<Receipt> receipts, Pagination pagination})> list({
    int page = 1,
    int limit = 20,
  }) async {
    final data = await apiClient.get(
      '/receipts',
      query: {'page': page.toString(), 'limit': limit.toString()},
    );
    final receipts = (data['receipts'] as List<dynamic>)
        .map((json) => Receipt.fromJson(json as Map<String, dynamic>))
        .toList();
    final pagination = Pagination.fromJson(
      data['pagination'] as Map<String, dynamic>,
    );
    return (receipts: receipts, pagination: pagination);
  }

  /// Requeue a failed or needs-review receipt for reprocessing.
  Future<ScanResult> reprocess(int id) async {
    final data = await apiClient.post('/receipts/$id/reprocess');
    return ScanResult.fromJson(data as Map<String, dynamic>);
  }
}
