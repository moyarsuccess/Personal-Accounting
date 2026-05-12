import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/models/merchant.dart';
import 'package:personal_accounting/services/database_service.dart';
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
    final db = ref.read(databaseServiceProvider);

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
