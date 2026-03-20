import 'package:personal_accounting/models/category.dart';
import 'package:personal_accounting/models/merchant.dart';

class Cost {
  final String id;
  final double amount;
  final DateTime date;
  final Category category;
  final Merchant merchant;

  Cost({
    required this.id,
    required this.amount,
    required this.date,
    required this.category,
    required this.merchant,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'date': date.toIso8601String(),
      'categoryId': category.id,
      'merchantId': merchant.id,
    };
  }

  // Cost fromMap will be handled in the database service by performing a JOIN
  // or by passing in the retrieved Category and Merchant objects.
  factory Cost.fromMap(Map<String, dynamic> map, Category category, Merchant merchant) {
    return Cost(
      id: map['id'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
      category: category,
      merchant: merchant,
    );
  }
}
