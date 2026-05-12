import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_accounting/models/category.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/models/merchant.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud equivalent of [DatabaseService] — same surface, talks to Supabase.
///
/// Every row carries a `user_id` column populated by `auth.uid()` on the
/// server (default value in the SQL migration). RLS policies guarantee a
/// user only sees their own rows, so we never have to filter by user_id
/// client-side.
class SupabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  // ─── Categories ────────────────────────────────────────────────────────────

  Future<List<Category>> getCategories() async {
    final rows = await _client
        .from('categories')
        .select()
        .order('name', ascending: true);
    return rows.map(_categoryFromRow).toList();
  }

  Future<void> insertCategory(Category category) async {
    await _client.from('categories').upsert(_categoryToRow(category));
  }

  Future<void> updateCategory(Category category) async {
    await _client
        .from('categories')
        .update(_categoryToRow(category))
        .eq('id', category.id);
  }

  Future<void> insertCategoriesBatch(List<Category> categories) async {
    if (categories.isEmpty) return;
    await _client
        .from('categories')
        .upsert(categories.map(_categoryToRow).toList());
  }

  // ─── Merchants ─────────────────────────────────────────────────────────────

  Future<List<Merchant>> getMerchants() async {
    final rows = await _client
        .from('merchants')
        .select()
        .order('name', ascending: true);
    return rows
        .map((r) => Merchant(id: r['id'] as String, name: r['name'] as String))
        .toList();
  }

  Future<void> insertMerchant(Merchant merchant) async {
    await _client.from('merchants').upsert({
      'id': merchant.id,
      'name': merchant.name,
    });
  }

  Future<void> updateMerchant(Merchant merchant) async {
    await _client
        .from('merchants')
        .update({'name': merchant.name})
        .eq('id', merchant.id);
  }

  Future<void> insertMerchantsBatch(List<Merchant> merchants) async {
    if (merchants.isEmpty) return;
    await _client.from('merchants').upsert(
      merchants.map((m) => {'id': m.id, 'name': m.name}).toList(),
    );
  }

  Future<Merchant?> getMerchantByName(String name) async {
    final rows = await _client
        .from('merchants')
        .select()
        .eq('name', name)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Merchant(id: r['id'] as String, name: r['name'] as String);
  }

  // ─── Costs ─────────────────────────────────────────────────────────────────

  Future<List<Cost>> getCosts() async {
    // PostgREST supports inline FK expansion; one round-trip vs three.
    final rows = await _client
        .from('costs')
        .select(
          'id, amount, date, category_id, merchant_id, '
          'categories!inner(id, name, icon_code, color_code), '
          'merchants!inner(id, name)',
        )
        .order('date', ascending: false);

    return rows.map((row) {
      final catRow = row['categories'] as Map<String, dynamic>;
      final merchRow = row['merchants'] as Map<String, dynamic>;
      return Cost(
        id: row['id'] as String,
        amount: (row['amount'] as num).toDouble(),
        date: DateTime.parse(row['date'] as String),
        category: _categoryFromRow(catRow),
        merchant: Merchant(
          id: merchRow['id'] as String,
          name: merchRow['name'] as String,
        ),
      );
    }).toList();
  }

  Future<void> insertCost(Cost cost) async {
    await _client.from('costs').upsert(_costToRow(cost));
  }

  Future<void> updateCost(Cost cost) async {
    await _client.from('costs').update(_costToRow(cost)).eq('id', cost.id);
  }

  Future<void> insertCostsBatch(List<Cost> costs) async {
    if (costs.isEmpty) return;
    // Postgres caps payload size; chunk to be safe on slow links.
    const chunk = 200;
    for (var i = 0; i < costs.length; i += chunk) {
      final end = (i + chunk < costs.length) ? i + chunk : costs.length;
      await _client
          .from('costs')
          .upsert(costs.sublist(i, end).map(_costToRow).toList());
    }
  }

  Future<void> deleteCost(String id) async {
    await _client.from('costs').delete().eq('id', id);
  }

  // ─── Row <-> Model converters ──────────────────────────────────────────────

  Map<String, dynamic> _categoryToRow(Category c) => {
    'id': c.id,
    'name': c.name,
    'icon_code': c.iconCode,
    'color_code': c.colorCode,
  };

  Category _categoryFromRow(Map<String, dynamic> r) => Category(
    id: r['id'] as String,
    name: r['name'] as String,
    iconCode: (r['icon_code'] as String?) ?? 'shopping_bag',
    colorCode: (r['color_code'] as num?)?.toInt() ?? 0xFF9E9E9E,
  );

  Map<String, dynamic> _costToRow(Cost c) => {
    'id': c.id,
    'amount': c.amount,
    'date': c.date.toIso8601String(),
    'category_id': c.category.id,
    'merchant_id': c.merchant.id,
  };
}

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

/// Cloud-backed providers. These replace the local-SQLite providers from
/// `database_service.dart` as the primary data source. The local
/// `databaseServiceProvider` still exists for the one-time migration flow.
final cloudCategoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(supabaseServiceProvider).getCategories();
});

final cloudMerchantsProvider = FutureProvider<List<Merchant>>((ref) {
  return ref.watch(supabaseServiceProvider).getMerchants();
});

final cloudCostsProvider = FutureProvider<List<Cost>>((ref) {
  return ref.watch(supabaseServiceProvider).getCosts();
});
