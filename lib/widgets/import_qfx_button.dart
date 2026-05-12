import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/models/merchant.dart';
import 'package:personal_accounting/services/backup_service.dart';
import 'package:personal_accounting/services/database_service.dart';
import 'package:personal_accounting/services/migration_service.dart';
import 'package:personal_accounting/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:personal_accounting/widgets/add_cost_dialog.dart';

class ImportQfxButton extends ConsumerStatefulWidget {
  const ImportQfxButton({super.key});

  @override
  ConsumerState<ImportQfxButton> createState() => _ImportQfxButtonState();
}

class _ImportQfxButtonState extends ConsumerState<ImportQfxButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: _isOpen ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeOutQuad,
      parent: _controller,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  Future<void> _importQfx(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['qfx', 'ofx', 'txt', 'xml'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final contents = await file.readAsString();

        await _parseAndInsertQfx(contents, ref);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully imported costs.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import QFX: $e')));
      }
    }
  }

  Future<int> _parseAndInsertQfx(String contents, WidgetRef ref) async {
    final db = ref.read(supabaseServiceProvider);

    // Simple QFX/OFX STMTTRN parser
    final trnRegex = RegExp(r'<STMTTRN>([\s\S]*?)</STMTTRN>');
    final amtRegex = RegExp(r'<TRNAMT>([^<]+)');
    final nameRegex = RegExp(r'<NAME>([^<]+)');
    final dateRegex = RegExp(r'<DTPOSTED>([^<]+)');

    final matches = trnRegex.allMatches(contents);

    final categories = await db.getCategories();
    final defaultCat = categories.firstWhere(
      (c) => c.name == 'Bills',
      orElse: () => categories.first,
    );
    final existingCosts = await db.getCosts();

    int count = 0;

    for (final match in matches) {
      final block = match.group(1) ?? '';
      final amtMatch = amtRegex.firstMatch(block);
      final nameMatch = nameRegex.firstMatch(block);
      final dateMatch = dateRegex.firstMatch(block);

      if (amtMatch != null && nameMatch != null) {
        final amountStr = amtMatch.group(1)?.trim();
        final nameStr = nameMatch.group(1)?.trim() ?? 'Unknown Merchant';
        final dateStr = dateMatch?.group(1)?.trim() ?? '';

        double amount = double.tryParse(amountStr ?? '0') ?? 0;

        // QFX expenses are negative. Ignore positive deposits.
        if (amount < 0) {
          amount = amount.abs();

          DateTime date = DateTime.now();
          if (dateStr.length >= 8) {
            final y = int.tryParse(dateStr.substring(0, 4)) ?? date.year;
            final m = int.tryParse(dateStr.substring(4, 6)) ?? date.month;
            final d = int.tryParse(dateStr.substring(6, 8)) ?? date.day;
            date = DateTime(y, m, d);
          }

          final isDuplicate = existingCosts.any(
            (c) =>
                c.amount == amount &&
                c.date.year == date.year &&
                c.date.month == date.month &&
                c.date.day == date.day &&
                c.merchant.name.toLowerCase() == nameStr.toLowerCase(),
          );

          if (!isDuplicate) {
            var merchant = await db.getMerchantByName(nameStr);
            if (merchant == null) {
              merchant = Merchant(id: const Uuid().v4(), name: nameStr);
              await db.insertMerchant(merchant);
            }

            final cost = Cost(
              id: const Uuid().v4(),
              amount: amount,
              date: date,
              category: defaultCat,
              merchant: merchant,
            );

            await db.insertCost(cost);
            existingCosts.add(cost);
            count++;
          }
        }
      }
    }

    ref.invalidate(costsProvider);
    ref.invalidate(merchantsProvider);
    return count;
  }

  Future<void> _setPassword(BuildContext context) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    bool obscure = true;
    String? errorText;

    final newPassword = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Set / change password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pick a password — at least 6 characters. After this you '
                    'can sign in with email + password instead of waiting for '
                    'a magic link.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setLocal(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: obscure,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final pw = controller.text;
                    if (pw.length < 6) {
                      setLocal(
                        () => errorText =
                            'Password must be at least 6 characters.',
                      );
                      return;
                    }
                    if (pw != confirmController.text) {
                      setLocal(() => errorText = 'Passwords don\'t match.');
                      return;
                    }
                    Navigator.of(context).pop(pw);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newPassword == null || !context.mounted) return;

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password set. You can now sign in with email + password.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to set password: $e')));
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You\'ll need to sign in again with your email magic link to see '
          'your data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await Supabase.instance.client.auth.signOut();
    // AuthGate listens to onAuthStateChange and pops to LoginScreen.
  }

  Future<void> _migrateToCloud(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrate local data to cloud?'),
        content: const Text(
          'This copies every row from your local SQLite database up to '
          'Supabase under your account. Existing rows with the same id are '
          'overwritten. Safe to re-run if it fails partway. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Migrate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final svc = ref.read(migrationServiceProvider);
      final counts = await svc.migrate();

      ref.invalidate(categoriesProvider);
      ref.invalidate(merchantsProvider);
      ref.invalidate(costsProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Migrated ${counts['costs']} costs, '
            '${counts['categories']} categories, '
            '${counts['merchants']} merchants to cloud.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Migration failed: $e')));
      }
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose backup folder',
      );
      if (dir == null) return; // user cancelled

      final svc = ref.read(backupServiceProvider);
      final outPath = await svc.exportToDirectory(dir);

      if (!context.mounted) return;
      // Show the path with a Copy action so the user can paste it elsewhere.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved: $outPath'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Copy path',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: outPath));
            },
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Choose backup file',
      );
      if (result == null || result.files.single.path == null) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore from backup?'),
          content: const Text(
            'This will merge the backup into your current data. Rows with the '
            'same id will be overwritten. New rows will be added. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final svc = ref.read(backupServiceProvider);
      final counts = await svc.importFromFile(result.files.single.path!);

      ref.invalidate(categoriesProvider);
      ref.invalidate(merchantsProvider);
      ref.invalidate(costsProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored ${counts['costs']} costs, '
            '${counts['categories']} categories, '
            '${counts['merchants']} merchants.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAction(
                'Migrate Local → Cloud',
                Icons.cloud_upload,
                'migrate',
                () => _migrateToCloud(context, ref),
              ),
              const SizedBox(height: 16),
              _buildAction(
                'Export Backup',
                Icons.save_alt,
                'export',
                () => _exportBackup(context, ref),
              ),
              const SizedBox(height: 16),
              _buildAction(
                'Restore Backup',
                Icons.settings_backup_restore,
                'restore',
                () => _importBackup(context, ref),
              ),
              const SizedBox(height: 16),
              _buildAction(
                'Import QFX',
                Icons.upload_file,
                'import',
                () => _importQfx(context, ref),
              ),
              const SizedBox(height: 16),
              _buildAction('Add Cost', Icons.add, 'add', () {
                showDialog(
                  context: context,
                  builder: (context) => const AddCostDialog(),
                );
              }),
              const SizedBox(height: 16),
              _buildAction(
                'Set password',
                Icons.password,
                'setpw',
                () => _setPassword(context),
              ),
              const SizedBox(height: 16),
              _buildAction(
                'Sign out',
                Icons.logout,
                'signout',
                () => _signOut(context),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        FloatingActionButton(
          heroTag: 'main_fab',
          onPressed: _toggle,
          child: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _expandAnimation,
          ),
        ),
      ],
    );
  }

  Widget _buildAction(
    String label,
    IconData icon,
    String tag,
    VoidCallback action,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Material(
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 4.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label),
          ),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          heroTag: 'sub_fab_$tag',
          mini: true,
          onPressed: () {
            _toggle();
            action();
          },
          child: Icon(icon),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
