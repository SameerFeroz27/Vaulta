/// Which way the money went. `lent` = they owe me, `borrowed` = I owe them.
class LoanDirection {
  LoanDirection._();

  static const String lent = 'lent';
  static const String borrowed = 'borrowed';
}

/// Derived by the backend from the repayment total, never stored.
class LoanState {
  LoanState._();

  static const String open = 'open';
  static const String settled = 'settled';
}

/// A loan to or from a friend or relative.
///
/// Every money field except [principal] and [paid] is derived — [outstanding] floors
/// at zero, and [surplus] carries anything repaid beyond the principal so the UI can
/// present it as a gift, tip or refund rather than a negative balance.
class Loan {
  final int id;
  final String counterparty;
  final String direction; // 'lent' or 'borrowed'
  final double principal;
  final String issueDate;
  final String? dueDate;
  final String? notes;
  final double paid;
  final double outstanding;
  final double surplus;
  final String state; // 'open' or 'settled'
  final bool overdue;
  final int? transactionId;
  final String? createdAt;
  final String? updatedAt;

  Loan({
    required this.id,
    required this.counterparty,
    required this.direction,
    required this.principal,
    required this.issueDate,
    this.dueDate,
    this.notes,
    required this.paid,
    required this.outstanding,
    this.surplus = 0,
    required this.state,
    this.overdue = false,
    this.transactionId,
    this.createdAt,
    this.updatedAt,
  });

  factory Loan.fromJson(Map<String, dynamic> json) {
    final principal = _toDouble(json['principal']);
    final paid = _toDouble(json['paid']);

    return Loan(
      id: json['id'] as int,
      counterparty: json['counterparty'] as String? ?? '',
      direction: json['direction'] as String? ?? LoanDirection.lent,
      principal: principal,
      issueDate: json['issueDate'] as String? ?? '',
      dueDate: json['dueDate'] as String?,
      notes: json['notes'] as String?,
      paid: paid,
      // Fall back to the local formula if the API omits the derived fields, so a
      // missing key cannot render a loan as fully outstanding.
      outstanding: json['outstanding'] == null
          ? _floorZero(principal - paid)
          : _toDouble(json['outstanding']),
      surplus: json['surplus'] == null
          ? _floorZero(paid - principal)
          : _toDouble(json['surplus']),
      state: json['state'] as String? ??
          (paid >= principal ? LoanState.settled : LoanState.open),
      overdue: json['overdue'] as bool? ?? false,
      transactionId: json['transactionId'] as int?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  bool get isLent => direction == LoanDirection.lent;
  bool get isBorrowed => direction == LoanDirection.borrowed;
  bool get isSettled => state == LoanState.settled;
  bool get isOpen => state == LoanState.open;

  /// "They owe you" / "You owe" — the label for a direction.
  String get directionLabel => isLent ? 'Owed to me' : 'I owe';

  /// How much of the principal has been repaid, clamped to 0..1 for a progress bar.
  double get progress {
    if (principal <= 0) return 0;
    return (paid / principal).clamp(0.0, 1.0).toDouble();
  }

  /// True when money changed hands beyond the principal (a gift, tip or refund).
  bool get hasSurplus => surplus > 0;
}

/// A single repayment against a loan.
class LoanPayment {
  final int id;
  final double amount;
  final String paymentDate;
  final int? transactionId;
  final String? note;
  final String? createdAt;

  LoanPayment({
    required this.id,
    required this.amount,
    required this.paymentDate,
    this.transactionId,
    this.note,
    this.createdAt,
  });

  factory LoanPayment.fromJson(Map<String, dynamic> json) {
    return LoanPayment(
      id: json['id'] as int,
      amount: _toDouble(json['amount']),
      paymentDate: json['paymentDate'] as String? ?? '',
      transactionId: json['transactionId'] as int?,
      note: json['note'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}

/// One row of the per-person summary from GET /api/loans/summary.
///
/// [theyOwe] and [iOwe] count active loans only, so they agree with the loan list.
/// [repaid] spans removed loans too, so deleting a loan never erases a repayment.
class LoanSummaryPerson {
  final String person;
  final double theyOwe;
  final double iOwe;
  final double repaid;

  /// Active loans for this person — 0 when every loan they had has been removed.
  final int loanCount;
  final double net; // positive = they owe me more than I owe them
  final String state;

  LoanSummaryPerson({
    required this.person,
    required this.theyOwe,
    required this.iOwe,
    required this.repaid,
    required this.loanCount,
    required this.net,
    required this.state,
  });

  factory LoanSummaryPerson.fromJson(Map<String, dynamic> json) {
    final theyOwe = _toDouble(json['theyOwe']);
    final iOwe = _toDouble(json['iOwe']);
    final repaid = _toDouble(json['repaid']);

    return LoanSummaryPerson(
      person: json['person'] as String? ?? '',
      theyOwe: theyOwe,
      iOwe: iOwe,
      repaid: repaid,
      loanCount: json['loanCount'] as int? ?? 0,
      net: json['net'] == null ? theyOwe - iOwe : _toDouble(json['net']),
      state: json['state'] as String? ??
          (theyOwe > 0 || iOwe > 0 ? LoanState.open : LoanState.settled),
    );
  }

  bool get isOpen => state == LoanState.open;
}

/// Active filter state for the loan list.
class LoanFilters {
  final String? direction;
  final String? state;
  final String? search;
  final String sort;
  final String order;

  LoanFilters({
    this.direction,
    this.state,
    this.search,
    this.sort = 'due_date',
    this.order = 'asc',
  });

  LoanFilters copyWith({
    String? direction,
    String? state,
    String? search,
    String? sort,
    String? order,
  }) {
    return LoanFilters(
      direction: direction ?? this.direction,
      state: state ?? this.state,
      search: search ?? this.search,
      sort: sort ?? this.sort,
      order: order ?? this.order,
    );
  }

  bool get hasActiveFilters =>
      direction != null ||
      state != null ||
      (search != null && search!.isNotEmpty);

  Map<String, dynamic> toQueryMap() {
    final params = <String, dynamic>{'sort': sort, 'order': order};
    if (direction != null) params['direction'] = direction;
    if (state != null) params['state'] = state;
    if (search != null && search!.isNotEmpty) params['search'] = search;
    return params;
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double _floorZero(double value) => value < 0 ? 0 : value;
