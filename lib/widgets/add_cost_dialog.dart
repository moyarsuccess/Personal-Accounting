import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:personal_accounting/models/category.dart';
import 'package:personal_accounting/models/cost.dart';
import 'package:personal_accounting/models/merchant.dart';
import 'package:personal_accounting/services/database_service.dart';
import 'package:personal_accounting/services/supabase_service.dart';
import 'package:uuid/uuid.dart';

class AddCostDialog extends ConsumerStatefulWidget {
  final Cost? existingCost;
  const AddCostDialog({super.key, this.existingCost});

  @override
  ConsumerState<AddCostDialog> createState() => _AddCostDialogState();
}

class _AddCostDialogState extends ConsumerState<AddCostDialog> {
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Category? _selectedCategory;
  Merchant? _selectedMerchant;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.existingCost != null) {
      _amountController.text = widget.existingCost!.amount.toString();
      _selectedCategory = widget.existingCost!.category;
      _selectedMerchant = widget.existingCost!.merchant;
      _selectedDate = widget.existingCost!.date;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }
    if (_selectedMerchant == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a merchant')));
      return;
    }

    final double amount = double.parse(_amountController.text);

    final db = ref.read(supabaseServiceProvider);

    final newCost = Cost(
      id: widget.existingCost?.id ?? const Uuid().v4(),
      amount: amount,
      date: _selectedDate,
      category: _selectedCategory!,
      merchant: _selectedMerchant!,
    );

    if (widget.existingCost != null) {
      await db.updateCost(newCost);
    } else {
      await db.insertCost(newCost);
    }
    ref.invalidate(costsProvider);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _showAddMerchantDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Merchant'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: 'Merchant Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      final db = ref.read(supabaseServiceProvider);
      // Check if it already exists to avoid duplicates
      Merchant? existingMerchant = await db.getMerchantByName(result);
      if (existingMerchant == null) {
        final newMerchant = Merchant(id: const Uuid().v4(), name: result);
        await db.insertMerchant(newMerchant);
        ref.invalidate(merchantsProvider);
        setState(() {
          _selectedMerchant = newMerchant;
        });
      } else {
        setState(() {
          _selectedMerchant = existingMerchant;
        });
      }
    }
  }

  Future<void> _showEditMerchantDialog() async {
    if (_selectedMerchant == null) return;
    final textController = TextEditingController(text: _selectedMerchant!.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Merchant'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: 'Merchant Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null &&
        result.isNotEmpty &&
        result != _selectedMerchant!.name) {
      final db = ref.read(supabaseServiceProvider);
      Merchant? existingMerchant = await db.getMerchantByName(result);
      if (existingMerchant == null) {
        final updatedMerchant = Merchant(
          id: _selectedMerchant!.id,
          name: result,
        );
        await db.updateMerchant(updatedMerchant);
        ref.invalidate(merchantsProvider);
        ref.invalidate(costsProvider);
        setState(() {
          _selectedMerchant = updatedMerchant;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Merchant name already exists')),
          );
        }
      }
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Category'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: 'Category Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      final db = ref.read(supabaseServiceProvider);
      final newCategory = Category(
        id: const Uuid().v4(),
        name: result,
        iconCode: 'shopping_bag', // use a default icon
        colorCode: 0xFF9E9E9E, // neutral grey default
      );
      await db.insertCategory(newCategory);
      ref.invalidate(categoriesProvider);
      setState(() {
        _selectedCategory = newCategory;
      });
    }
  }

  Future<void> _showEditCategoryDialog() async {
    if (_selectedCategory == null) return;
    final textController = TextEditingController(text: _selectedCategory!.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Category'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(hintText: 'Category Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(textController.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result != null &&
        result.isNotEmpty &&
        result != _selectedCategory!.name) {
      final db = ref.read(supabaseServiceProvider);
      final updatedCategory = Category(
        id: _selectedCategory!.id,
        name: result,
        iconCode: _selectedCategory!.iconCode,
        colorCode: _selectedCategory!.colorCode,
      );
      await db.updateCategory(updatedCategory);
      ref.invalidate(categoriesProvider);
      ref.invalidate(costsProvider);
      setState(() {
        _selectedCategory = updatedCategory;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final merchantsAsync = ref.watch(merchantsProvider);
    final dateFormat = DateFormat.yMMMd();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existingCost != null ? 'Edit Cost' : 'Add New Cost',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // Amount Field
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Enter an amount';
                    if (double.tryParse(value) == null)
                      return 'Enter a valid number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Merchant Row
                merchantsAsync.when(
                  data: (merchants) {
                    // Update selected merchant if it was re-fetched but lost reference
                    if (_selectedMerchant != null &&
                        !merchants.contains(_selectedMerchant)) {
                      try {
                        _selectedMerchant = merchants.firstWhere(
                          (m) => m.id == _selectedMerchant!.id,
                        );
                      } catch (e) {
                        _selectedMerchant = null;
                      }
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Merchant>(
                            initialValue: _selectedMerchant,
                            decoration: const InputDecoration(
                              labelText: 'Merchant',
                              prefixIcon: Icon(Icons.store),
                            ),
                            items: merchants.map((merch) {
                              return DropdownMenuItem(
                                value: merch,
                                child: Text(merch.name),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedMerchant = val;
                              });
                            },
                            validator: (val) {
                              if (val == null) return 'Select a merchant';
                              return null;
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: _showAddMerchantDialog,
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.blue,
                          ),
                          tooltip: 'Add Merchant',
                        ),
                        if (_selectedMerchant != null)
                          IconButton(
                            onPressed: _showEditMerchantDialog,
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            tooltip: 'Edit Merchant',
                          ),
                      ],
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (err, stack) => Text('Error loading merchants: $err'),
                ),
                const SizedBox(height: 16),

                // Category Row
                categoriesAsync.when(
                  data: (categories) {
                    // Update selected category if it was re-fetched but lost reference
                    if (_selectedCategory != null &&
                        !categories.contains(_selectedCategory)) {
                      try {
                        _selectedCategory = categories.firstWhere(
                          (c) => c.id == _selectedCategory!.id,
                        );
                      } catch (e) {
                        _selectedCategory = null;
                      }
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Category>(
                            initialValue: _selectedCategory,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                              prefixIcon: Icon(Icons.category),
                            ),
                            items: categories.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat.name),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedCategory = val;
                              });
                            },
                            validator: (val) {
                              if (val == null) return 'Select a category';
                              return null;
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: _showAddCategoryDialog,
                          icon: const Icon(
                            Icons.add_circle,
                            color: Colors.blue,
                          ),
                          tooltip: 'Add Category',
                        ),
                        if (_selectedCategory != null)
                          IconButton(
                            onPressed: _showEditCategoryDialog,
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            tooltip: 'Edit Category',
                          ),
                      ],
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (err, stack) => Text('Error loading categories: $err'),
                ),

                const SizedBox(height: 16),
                // Date Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date: ${dateFormat.format(_selectedDate)}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _selectDate(context),
                      child: const Text('Change Date'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submit,
                  child: Text(
                    widget.existingCost != null ? 'Save Changes' : 'Save Cost',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
