import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/screens/category_transactions_screen.dart';
import 'package:personal_accounting/services/database_service.dart';

// Helper provider for selected month
class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void setMonth(DateTime month) {
    state = month;
  }
}

final selectedMonthProvider = NotifierProvider<SelectedMonthNotifier, DateTime>(
  () {
    return SelectedMonthNotifier();
  },
);

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final costsAsync = ref.watch(costsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Overview')),
      body: Column(
        children: [
          _buildMonthSelector(context, ref, selectedMonth),
          Expanded(
            child: costsAsync.when(
              data: (costs) {
                // Filter costs by selected month
                final filteredCosts = costs
                    .where(
                      (c) =>
                          c.date.year == selectedMonth.year &&
                          c.date.month == selectedMonth.month,
                    )
                    .toList();

                if (filteredCosts.isEmpty) {
                  return const Center(child: Text('No costs for this month.'));
                }

                return _buildChartAndList(context, filteredCosts, selectedMonth);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(
    BuildContext context,
    WidgetRef ref,
    DateTime currentMonth,
  ) {
    final dateFormat = DateFormat.yMMMM();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref
                  .read(selectedMonthProvider.notifier)
                  .setMonth(
                    DateTime(currentMonth.year, currentMonth.month - 1),
                  );
            },
          ),
          Text(
            dateFormat.format(currentMonth),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              ref
                  .read(selectedMonthProvider.notifier)
                  .setMonth(
                    DateTime(currentMonth.year, currentMonth.month + 1),
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChartAndList(
    BuildContext context,
    List<Cost> costs,
    DateTime selectedMonth,
  ) {
    // Aggregate by category. Keep one Cost per category so we can look up the
    // canonical Category (id + colorCode) when the user taps a row — avoids
    // a separate provider read in the drill-in screen.
    final Map<String, double> categoryTotals = {};
    final Map<String, Color> categoryColors = {};
    final Map<String, String> categoryIds = {};
    double totalMonthCost = 0;

    for (var cost in costs) {
      final catName = cost.category.name;
      categoryTotals[catName] = (categoryTotals[catName] ?? 0) + cost.amount;
      categoryColors[catName] = Color(cost.category.colorCode);
      categoryIds[catName] = cost.category.id;
      totalMonthCost += cost.amount;
    }

    // Sort descending by amount so both the pie chart and the list lead with
    // the largest spend.
    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final currencyFormatter = NumberFormat.currency(symbol: '\$');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Total: ${currencyFormatter.format(totalMonthCost)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 250,
          child: PieChart(
            PieChartData(
              sections: sortedEntries.map((e) {
                final percentage = (e.value / totalMonthCost) * 100;
                return PieChartSectionData(
                  color: categoryColors[e.key],
                  value: e.value,
                  title: '${percentage.toStringAsFixed(1)}%',
                  radius: 80,
                  titleStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: sortedEntries.length,
            itemBuilder: (context, index) {
              final entry = sortedEntries[index];
              return ListTile(
                leading: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: categoryColors[entry.key],
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(entry.key),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currencyFormatter.format(entry.value),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CategoryTransactionsScreen(
                        categoryName: entry.key,
                        categoryId: categoryIds[entry.key]!,
                        month: selectedMonth,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
