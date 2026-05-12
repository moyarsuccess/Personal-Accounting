import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_accounting/screens/costs_tab.dart';
import 'package:personal_accounting/services/database_service.dart';

/// Shows every transaction for a single category within a single month.
/// Reuses [CostItem] from costs_tab.dart so the view/edit/delete flow stays
/// identical to the main Costs tab.
class CategoryTransactionsScreen extends ConsumerWidget {
  final String categoryName;
  final String categoryId;
  final DateTime month;

  const CategoryTransactionsScreen({
    super.key,
    required this.categoryName,
    required this.categoryId,
    required this.month,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costsAsync = ref.watch(costsProvider);
    final monthLabel = DateFormat.yMMMM().format(month);
    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              monthLabel,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
          ),
        ),
      ),
      body: costsAsync.when(
        data: (costs) {
          final filtered = costs
              .where(
                (c) =>
                    c.category.id == categoryId &&
                    c.date.year == month.year &&
                    c.date.month == month.month,
              )
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          if (filtered.isEmpty) {
            return const Center(
              child: Text('No transactions in this category for this month.'),
            );
          }

          final total = filtered.fold<double>(0, (sum, c) => sum + c.amount);

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withAlpha(64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${filtered.length} transaction${filtered.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total: ${currencyFormatter.format(total)}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      CostItem(cost: filtered[index]),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
