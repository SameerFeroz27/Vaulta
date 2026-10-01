/// A receipt/scan job — tracks the processing of an uploaded receipt image
/// or bank message through the AI parsing pipeline.
class Receipt {
  final int id;
  final String inputType; // image, bank_message, virtual_receipt
  final String
  status; // queued, processing, success, needs_review, failed, duplicate
  final String? ocrProvider;
  final String? aiModel;
  final String? errorMessage;
  final int? transactionId;
  final int attempts;
  final String createdAt;
  final String? processedAt;
  final String? amount;
  final String? merchant;
  final String? transactionType;
  /// The words or feature the AI relied on to decide income vs expense, if it did.
  final String? directionEvidence;

  Receipt({
    required this.id,
    required this.inputType,
    required this.status,
    this.ocrProvider,
    this.aiModel,
    this.errorMessage,
    this.transactionId,
    this.attempts = 0,
    required this.createdAt,
    this.processedAt,
    this.amount,
    this.merchant,
    this.transactionType,
    this.directionEvidence,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'] as int,
      inputType: json['inputType'] as String? ?? 'image',
      status: json['status'] as String? ?? 'queued',
      ocrProvider: json['ocrProvider'] as String?,
      aiModel: json['aiModel'] as String?,
      errorMessage: json['errorMessage'] as String?,
      transactionId: json['transactionId'] as int?,
      attempts: json['attempts'] as int? ?? 0,
      createdAt: json['createdAt'] as String,
      processedAt: json['processedAt'] as String?,
      amount: json['amount']?.toString(),
      merchant: json['merchant'] as String?,
      transactionType: json['transactionType'] as String?,
      directionEvidence: json['directionEvidence'] as String?,
    );
  }

  /// Whether the scan has reached a terminal state (no more polling needed).
  bool get isFinal =>
      status == 'success' ||
      status == 'needs_review' ||
      status == 'failed' ||
      status == 'duplicate';

  /// Whether the scan is still in progress.
  bool get isProcessing => status == 'queued' || status == 'processing';
}

/// Response from uploading a receipt image or submitting a bank message.
class ScanResult {
  final int receiptId;
  final String status;
  final String message;
  final int? existingTransactionId;

  ScanResult({
    required this.receiptId,
    required this.status,
    required this.message,
    this.existingTransactionId,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      receiptId: json['receiptId'] as int,
      status: json['status'] as String,
      message: json['message'] as String,
      existingTransactionId: json['existingTransactionId'] as int?,
    );
  }

  bool get isDuplicate => status == 'duplicate';
}

/// Slim.json
/// A slim transaction summary returned when polling a receipt's status.
class ReceiptTransaction {
  final int id;
  final String amount;
  final String type;
  final double? typeConfidence;
  final String? typeSource;
  final String? merchant;
  final String status;
  final String? transactionDate;

  ReceiptTransaction({
    required this.id,
    required this.amount,
    required this.type,
    this.typeConfidence,
    this.typeSource,
    this.merchant,
    required this.status,
    this.transactionDate,
  });

  factory ReceiptTransaction.fromJson(Map<String, dynamic> json) {
    return ReceiptTransaction(
      id: json['id'] as int,
      amount: json['amount'] as String,
      type: json['type'] as String? ?? 'expense',
      typeConfidence: json['typeConfidence'] == null
          ? null
          : double.tryParse(json['typeConfidence'].toString()),
      typeSource: json['typeSource'] as String?,
      merchant: json['merchant'] as String?,
      status: json['status'] as String? ?? 'needs_review',
      transactionDate: json['transactionDate'] as String?,
    );
  }
}

/// Response from GET /api/receipts/:id — receipt metadata + linked transaction.
class ReceiptDetail {
  final Receipt receipt;
  final ReceiptTransaction? transaction;

  ReceiptDetail({required this.receipt, this.transaction});

  factory ReceiptDetail.fromJson(Map<String, dynamic> json) {
    return ReceiptDetail(
      receipt: Receipt.fromJson(json['receipt'] as Map<String, dynamic>),
      transaction: json['transaction'] != null
          ? ReceiptTransaction.fromJson(
              json['transaction'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}
