import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:personal_accounting/models/category.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/models/merchant.dart';
import 'package:personal_accounting/services/supabase_service.dart';

/// JSON-based backup / restore. Format version 1.
///
/// Schema:
/// {
///   "version": 1,
///   "exportedAt": "<ISO8601>",
///   "categories": [ {id, name, iconCode, colorCode}, ... ],
///   "merchants":  [ {id, name}, ... ],
///   "costs":      [ {id, amount, date, categoryId, merchantId}, ... ]
/// }
///
/// Backs up the user's CLOUD data (Supabase) — the local SQLite store is
/// effectively dead after the migration, so a local backup would just write
/// stale data. The on-disk format is identical to v1 so the JSON file you
/// already downloaded (pre-migration) is still restorable: Restore will
/// upsert each row by id and the RLS-enforced user_id column gets populated
/// server-side via `default auth.uid()`.
class BackupService {
  static const int currentVersion = 1;

  final SupabaseService _db;

  BackupService(this._db);

  /// Returns a JSON string with every row in the local database.
  Future<String> buildBackupJson() async {
    final categories = await _db.getCategories();
    final merchants = await _db.getMerchants();
    final costs = await _db.getCosts();

    final payload = {
      'version': currentVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'categories': categories.map((c) => c.toMap()).toList(),
      'merchants': merchants.map((m) => m.toMap()).toList(),
      'costs': costs.map((c) => c.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Writes a timestamped backup file into [directory]. Returns the file path.
  Future<String> exportToDirectory(String directory) async {
    final json = await buildBackupJson();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final filename = 'personal_accounting_backup_$stamp.json';
    final outPath = p.join(directory, filename);
    final file = File(outPath);
    await file.writeAsString(json);
    return outPath;
  }

  /// Reads a JSON backup file and merges every row into the local database.
  /// Conflict policy: replace by id (so editing a backup file and re-importing
  /// overwrites existing rows with matching ids).
  ///
  /// Returns counts: {categories, merchants, costs}.
  Future<Map<String, int>> importFromFile(String path) async {
    final file = File(path);
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Backup file is not a JSON object.');
    }
    final version = decoded['version'];
    if (version is! int || version > currentVersion) {
      throw FormatException(
        'Unsupported backup version: $version (this app understands up to '
        'v$currentVersion).',
      );
    }

    final catsRaw = (decoded['categories'] as List?) ?? const [];
    final merchRaw = (decoded['merchants'] as List?) ?? const [];
    final costsRaw = (decoded['costs'] as List?) ?? const [];

    final categories = catsRaw
        .cast<Map>()
        .map((m) => Category.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    final merchants = merchRaw
        .cast<Map>()
        .map((m) => Merchant.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    // Costs need their referenced category + merchant objects to construct.
    // Index for O(1) lookup.
    final catById = {for (final c in categories) c.id: c};
    final merchById = {for (final m in merchants) m.id: m};

    final costs = <Cost>[];
    for (final raw in costsRaw.cast<Map>()) {
      final map = Map<String, dynamic>.from(raw);
      final cat = catById[map['categoryId']];
      final merch = merchById[map['merchantId']];
      if (cat == null || merch == null) {
        // Skip orphan costs rather than crash the whole restore.
        continue;
      }
      costs.add(Cost.fromMap(map, cat, merch));
    }

    // Order matters: parents before children (FK on costs).
    await _db.insertCategoriesBatch(categories);
    await _db.insertMerchantsBatch(merchants);
    await _db.insertCostsBatch(costs);

    return {
      'categories': categories.length,
      'merchants': merchants.length,
      'costs': costs.length,
    };
  }
}

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(supabaseServiceProvider));
});
