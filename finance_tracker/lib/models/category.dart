import 'package:flutter/material.dart';

/// A transaction category — either global (seeded) or user-created.
class Category {
  final int id;
  final String name;
  final String icon;
  final String color;
  final String transactionType; // 'expense', 'income', or 'both'
  final int? userId; // null for global categories
  final bool isGlobal;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.transactionType,
    this.userId,
    required this.isGlobal,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '📁',
      color: json['color'] as String? ?? '#BDC3C7',
      transactionType: json['transactionType'] as String? ?? 'expense',
      userId: json['userId'] as int?,
      isGlobal: json['isGlobal'] as bool? ?? false,
    );
  }

  /// Parse the hex color string (e.g. "#FF6B6B") to a Flutter Color.
  Color get colorValue {
    final hex = color.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  /// Whether this category can be used for the given transaction type.
  bool appliesTo(String type) {
    if (transactionType == 'both') return true;
    return transactionType == type;
  }
}
