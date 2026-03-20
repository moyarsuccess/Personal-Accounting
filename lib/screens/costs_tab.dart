import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/services/database_service.dart';
import 'package:personal_accounting/widgets/add_cost_dialog.dart';

class CostsTab extends ConsumerWidget {
  const CostsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final costsAsync = ref.watch(costsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Costs'),
      ),
      body: costsAsync.when(
        data: (costs) {
          if (costs.isEmpty) {
            return const Center(child: Text('No costs added yet.'));
          }
          return ListView.builder(
            itemCount: costs.length,
            itemBuilder: (context, index) {
              final cost = costs[index];
              return CostItem(cost: cost);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class CostItem extends ConsumerWidget {
  final Cost cost;

  const CostItem({super.key, required this.cost});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Map iconcode back to IconData, for now just returning a default if not found
    IconData getIcon(String code) {
      switch (code) {
        case 'shopping_cart':
          return Icons.shopping_cart;
        case 'directions_car':
          return Icons.directions_car;
        case 'movie':
          return Icons.movie;
        case 'receipt':
          return Icons.receipt;
        default:
          return Icons.label;
      }
    }

    final currencyFormatter = NumberFormat.currency(symbol: '\$');
    final dateFormatter = DateFormat.yMMMd();

    return Dismissible(
      key: Key(cost.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) async {
        final db = ref.read(databaseServiceProvider);
        await db.deleteCost(cost.id);
        ref.invalidate(costsProvider);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AddCostDialog(existingCost: cost),
            );
          },
          contentPadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
          backgroundColor: Color(cost.category.colorCode),
          child: Icon(getIcon(cost.category.iconCode), color: Colors.white),
        ),
        title: Text(
          cost.merchant.name,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(cost.category.name),
            const SizedBox(height: 4),
            Text(dateFormatter.format(cost.date), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              currencyFormatter.format(cost.amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () async {
                final db = ref.read(databaseServiceProvider);
                await db.deleteCost(cost.id);
                ref.invalidate(costsProvider);
              },
            ),
          ],
        ),
      ),
    ));
  }
}
