import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_accounting/services/database_service.dart';
import 'package:personal_accounting/services/supabase_service.dart';

/// One-time helper: reads the local SQLite database and pushes every row
/// up to Supabase under the signed-in user_id.
///
/// Conflict policy is upsert-by-id, so it's safe to re-run if the first
/// attempt fails partway through.
class MigrationService {
  final DatabaseService _local;
  final SupabaseService _cloud;

  MigrationService(this._local, this._cloud);

  Future<Map<String, int>> migrate() async {
    final categories = await _local.getCategories();
    final merchants = await _local.getMerchants();
    final costs = await _local.getCosts();

    // Order matters — Postgres enforces the FK from costs → categories/merchants.
    await _cloud.insertCategoriesBatch(categories);
    await _cloud.insertMerchantsBatch(merchants);
    await _cloud.insertCostsBatch(costs);

    return {
      'categories': categories.length,
      'merchants': merchants.length,
      'costs': costs.length,
    };
  }
}

final migrationServiceProvider = Provider<MigrationService>((ref) {
  return MigrationService(
    ref.watch(databaseServiceProvider),
    ref.watch(supabaseServiceProvider),
  );
});
