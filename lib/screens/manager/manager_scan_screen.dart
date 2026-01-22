import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerScanScreen extends StatefulWidget {
  const ManagerScanScreen({super.key});

  @override
  State<ManagerScanScreen> createState() => _ManagerScanScreenState();
}

class _ManagerScanScreenState extends State<ManagerScanScreen> {
  final _supabase = Supabase.instance.client;
  bool _isScanning = true;
  bool _loading = true;
  
  List<Map<String, dynamic>> _allBranches = [];
  Map<String, dynamic>? _branch;
  Map<String, dynamic>? _company;
  int _discountPercent = 0;
  int _selectedBranchIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadBranchInfo();
  }

  Future<void> _loadBranchInfo() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Получаем ВСЕ филиалы менеджера (через таблицу branch_managers)
      final branchesData = await _supabase
          .rpc('get_manager_branches', params: {'p_manager_id': userId});

      List<Map<String, dynamic>> branches = [];
      
      if (branchesData != null && (branchesData as List).isNotEmpty) {
        branches = List<Map<String, dynamic>>.from(branchesData);
      } else {
        // Fallback: пробуем старый способ (через manager_id)
        final fallbackData = await _supabase
            .from('company_branches')
            .select('*, companies(*)')
            .eq('manager_id', userId);
        
        if (fallbackData != null) {
          branches = List<Map<String, dynamic>>.from(fallbackData);
        }
      }
      
      _allBranches = branches;
      
      if (branches.isNotEmpty && mounted) {
        _selectBranch(0);
        setState(() => _loading = false);
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectBranch(int index) {
    if (index < 0 || index >= _allBranches.length) return;
    
    _selectedBranchIndex = index;
    final branchData = _allBranches[index];
    
    // RPC возвращает companies как JSON
    final companiesData = branchData['companies'];
    final company = companiesData is Map<String, dynamic> 
        ? companiesData 
        : null;
    
    setState(() {
      _branch = branchData;
      _company = company;
      _discountPercent = company?['discount_percentage'] ?? 0;
    });
  }

  void _onQRDetected(String customerId) {
    setState(() => _isScanning = false);
    _showAmountDialog(customerId);
  }

  Future<void> _showAmountDialog(String customerId) async {
    // First, get customer info
    Map<String, dynamic>? customer;
    try {
      customer = await _supabase
          .from('profiles')
          .select('full_name, email')
          .eq('id', customerId)
          .maybeSingle();
    } catch (e) {
      // Customer not found
    }

    if (!mounted) return;

    final amountController = TextEditingController();
    
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AmountInputSheet(
        customer: customer,
        customerId: customerId,
        discountPercent: _discountPercent,
        companyName: _company?['name'] ?? 'Магазин',
        amountController: amountController,
      ),
    );

    if (result != null && result > 0) {
      await _processTransaction(customerId, result);
    }

    // Resume scanning
    if (mounted) {
      setState(() => _isScanning = true);
    }
  }

  Future<void> _processTransaction(String customerId, double originalAmount) async {
    try {
      final discountAmount = originalAmount * _discountPercent / 100;
      final finalAmount = originalAmount - discountAmount;

      await _supabase.from('transactions').insert({
        'customer_id': customerId,
        'branch_id': _branch!['id'],
        'company_id': _company!['id'],
        'manager_id': _supabase.auth.currentUser!.id,
        'original_amount': originalAmount,
        'discount_percent': _discountPercent,
        'discount_amount': discountAmount,
        'final_amount': finalAmount,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Транзакция успешна! Итого: ${finalAmount.toStringAsFixed(0)} ₽',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_branch == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Сканер')),
        body: const Center(
          child: Text('Филиал не назначен'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканировать QR'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.discount, size: 18, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  '-$_discountPercent%',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Branch selector (если несколько филиалов)
          if (_allBranches.length > 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.primaryContainer,
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _selectedBranchIndex,
                        isExpanded: true,
                        isDense: true,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontSize: 14,
                        ),
                        items: _allBranches.asMap().entries.map((entry) {
                          final index = entry.key;
                          final branch = entry.value;
                          final company = branch['companies'] as Map<String, dynamic>?;
                          return DropdownMenuItem<int>(
                            value: index,
                            child: Text(
                              '${company?['name'] ?? ''} - ${branch['name'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (index) {
                          if (index != null) _selectBranch(index);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Company info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                // Logo
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _company?['logo_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _company!['logo_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.store,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : Icon(Icons.store, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _company?['name'] ?? 'Магазин',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _branch?['name'] ?? 'Филиал',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Discount badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '-$_discountPercent%',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Scanner
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    if (!_isScanning) return;
                    
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        _onQRDetected(barcode.rawValue!);
                        break;
                      }
                    }
                  },
                ),
                // Overlay
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isScanning ? Colors.green : Colors.grey,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                // Instructions
                Positioned(
                  bottom: 50,
                  left: 0,
                  right: 0,
                  child: Text(
                    _isScanning 
                        ? 'Наведите камеру на QR-код клиента'
                        : 'Обработка...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          blurRadius: 10,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Amount input bottom sheet
class _AmountInputSheet extends StatefulWidget {
  final Map<String, dynamic>? customer;
  final String customerId;
  final int discountPercent;
  final String companyName;
  final TextEditingController amountController;

  const _AmountInputSheet({
    required this.customer,
    required this.customerId,
    required this.discountPercent,
    required this.companyName,
    required this.amountController,
  });

  @override
  State<_AmountInputSheet> createState() => _AmountInputSheetState();
}

class _AmountInputSheetState extends State<_AmountInputSheet> {
  double _originalAmount = 0;
  double _discountAmount = 0;
  double _finalAmount = 0;

  void _updateAmounts(String value) {
    final amount = double.tryParse(value) ?? 0;
    setState(() {
      _originalAmount = amount;
      _discountAmount = amount * widget.discountPercent / 100;
      _finalAmount = amount - _discountAmount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customerName = widget.customer?['full_name'] ?? 
                         widget.customer?['email'] ?? 
                         'Клиент';

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            
            // Customer info
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        widget.companyName,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '-${widget.discountPercent}%',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Amount input
            TextField(
              controller: widget.amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                hintText: '0',
                suffixText: '₽',
                suffixStyle: const TextStyle(fontSize: 24),
                labelText: 'Сумма чека',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _updateAmounts,
            ),
            const SizedBox(height: 24),
            
            // Calculation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildCalcRow('Сумма чека', '${_originalAmount.toStringAsFixed(0)} ₽'),
                  const SizedBox(height: 8),
                  _buildCalcRow(
                    'Скидка ${widget.discountPercent}%',
                    '-${_discountAmount.toStringAsFixed(0)} ₽',
                    valueColor: Colors.green,
                  ),
                  const Divider(height: 24),
                  _buildCalcRow(
                    'К оплате',
                    '${_finalAmount.toStringAsFixed(0)} ₽',
                    isBold: true,
                    valueColor: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _originalAmount > 0
                        ? () => Navigator.pop(context, _originalAmount)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Подтвердить',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalcRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 18 : 14,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 18 : 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
