import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_accounting/models/cost.dart';
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

final selectedMonthProvider = NotifierProvider<SelectedMonthNotifier, DateTime>(() {
  return SelectedMonthNotifier();
});

class OverviewTab extends ConsumerWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final costsAsync = ref.watch(costsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
      ),
      body: Column(
        children: [
          _buildMonthSelector(context, ref, selectedMonth),
          Expanded(
            child: costsAsync.when(
              data: (costs) {
                // Filter costs by selected month
                final filteredCosts = costs.where((c) =>
                    c.date.year == selectedMonth.year &&
                    c.date.month == selectedMonth.month).toList();

                if (filteredCosts.isEmpty) {
                  return const Center(child: Text('No costs for this month.'));
                }

                return _buildChartAndList(context, filteredCosts);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(BuildContext context, WidgetRef ref, DateTime currentMonth) {
    final dateFormat = DateFormat.yMMMM();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).setMonth(DateTime(currentMonth.year, currentMonth.month - 1));
            },
          ),
          Text(
            dateFormat.format(currentMonth),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              ref.read(selectedMonthProvider.notifier).setMonth(DateTime(currentMonth.year, currentMonth.month + 1));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildChartAndList(BuildContext context, List<Cost> costs) {
    // Aggregate by category
    final Map<String, double> categoryTotals = {};
    final Map<String, Color> categoryColors = {};
    double totalMonthCost = 0;

    for (var cost in costs) {
      final catName = cost.category.name;
      categoryTotals[catName] = (categoryTotals[catName] ?? 0) + cost.amount;
      
      int colorIndex = catName.hashCode.abs() % Colors.primaries.length;
      categoryColors[catName] = Colors.primaries[colorIndex];
      
      totalMonthCost += cost.amount;
    }

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
              sections: categoryTotals.entries.map((e) {
                final percentage = (e.value / totalMonthCost) * 100;
                return PieChartSectionData(
                  color: categoryColors[e.key],
                  value: e.value,
                  title: '${percentage.toStringAsFixed(1)}%',
                  radius: 80,
                  titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
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
            itemCount: categoryTotals.length,
            itemBuilder: (context, index) {
              final entry = categoryTotals.entries.elementAt(index);
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
                trailing: Text(
                  currencyFormatter.format(entry.value),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
