/// A single financial transaction (expense or income).
class Transaction {
  final int id;
  final double amount;
  final String currency;
  final String type; // 'expense' or 'income'
  final String status; // 'needs_review', 'confirmed', 'archived'
  final String? merchant;
  final String? description;
  final String? occurredAt;
  final String transactionDate;
  final String? cardLast4;
  final String? bankReference;
  final int? receiptId;
  final int sourceId;
  final String sourceName;
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;

  Transaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.type,
    required this.status,
    this.merchant,
    this.description,
    this.occurredAt,
    required this.transactionDate,
    this.cardLast4,
    this.bankReference,
    this.receiptId,
    required this.sourceId,
    required this.sourceName,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as int,
      amount: double.parse(json['amount'].toString()),
      currency: json['currency'] as String? ?? 'PKR',
      type: json['type'] as String? ?? 'expense',
      status: json['status'] as String? ?? 'confirmed',
      merchant: json['merchant'] as String?,
      description: json['description'] as String?,
      occurredAt: json['occurredAt'] as String?,
      transactionDate: json['transactionDate'] as String,
      cardLast4: json['cardLast4'] as String?,
      bankReference: json['bankReference'] as String?,
      receiptId: json['receiptId'] as int?,
      sourceId: json['sourceId'] as int,
      sourceName: json['sourceName'] as String? ?? 'Unknown',
      categoryId: json['categoryId'] as int?,
      categoryName: json['categoryName'] as String?,
      categoryIcon: json['categoryIcon'] as String?,
      categoryColor: json['categoryColor'] as String?,
    );
  }

  bool get isExpense => type == 'expense';
  bool get isIncome => type == 'income';
  bool get needsReview => status == 'needs_review';
}

/// Pagination metadata returned by the list endpoint.
class Pagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final bool hasNext;
  final bool hasPrev;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrev,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    final page = json['page'] as int;
    final limit = json['limit'] as int;
    final total = json['total'] as int;
    final totalPages = json['totalPages'] as int;
    return Pagination(
      page: page,
      limit: limit,
      total: total,
      totalPages: totalPages,
      hasNext: json['hasNext'] as bool? ?? page * limit < total,
      hasPrev: json['hasPrev'] as bool? ?? page > 1,
    );
  }
}

/// Active filter state for the transaction list.
class TransactionFilters {
  final String? month;
  final int? source;
  final int? category;
  final String? type;
  final String? status;
  final String? search;
  final String sort;
  final String order;

  TransactionFilters({
    this.month,
    this.source,
    this.category,
    this.type,
    this.status,
    this.search,
    this.sort = 'date',
    this.order = 'desc',
  });

  TransactionFilters copyWith({
    String? month,
    int? source,
    int? category,
    String? type,
    String? status,
    String? search,
    String? sort,
    String? order,
  }) {
    return TransactionFilters(
      month: month ?? this.month,
      source: source ?? this.source,
      category: category ?? this.category,
      type: type ?? this.type,
      status: status ?? this.status,
      search: search ?? this.search,
      sort: sort ?? this.sort,
      order: order ?? this.order,
    );
  }

  bool get hasActiveFilters =>
      month != null ||
      source != null ||
      category != null ||
      type != null ||
      status != null ||
      (search != null && search!.isNotEmpty);

  Map<String, dynamic> toQueryMap() {
    final params = <String, dynamic>{'sort': sort, 'order': order};
    if (month != null) params['month'] = month;
    if (source != null) params['source'] = source;
    if (category != null) params['category'] = category;
    if (type != null) params['type'] = type;
    if (status != null) params['status'] = status;
    if (search != null && search!.isNotEmpty) params['search'] = search;
    return params;
  }
}
