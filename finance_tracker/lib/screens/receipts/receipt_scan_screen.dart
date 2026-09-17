import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/receipt.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/receipt_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/api_client.dart';
import '../../services/receipt_service.dart';
import '../../utils/formatters.dart';

enum _Mode { image, online, bankMessage }

enum _Phase { idle, uploading, processing, done }

/// Screen for scanning a receipt image or submitting a bank message.
///
/// Uploads the input to the backend, then polls until the AI processing
/// completes, and displays the parsed transaction result.
class ReceiptScanScreen extends StatefulWidget {
  const ReceiptScanScreen({super.key});

  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  late final ReceiptService _receiptService;

  _Mode _mode = _Mode.image;
  _Phase _phase = _Phase.idle;
  String _transactionType = 'expense';
  bool _showInstructions = true;

  XFile? _selectedImage;
  Uint8List? _imageBytes;
  final _messageController = TextEditingController();

  int? _receiptId;
  ReceiptDetail? _detail;
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _receiptService = ReceiptService(apiClient: context.read<ApiClient>());
    _messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Infer MIME type from filename extension when XFile.mimeType is null.
  String _inferMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: source, imageQuality: 85);
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = xFile;
        _imageBytes = bytes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
      }
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _phase = _Phase.uploading;
      _errorMessage = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final result = await _receiptService.scanImage(
        bytes,
        filename: _selectedImage!.name,
        mimeType: _selectedImage!.mimeType ?? _inferMimeType(_selectedImage!.name),
        inputType: _mode == _Mode.online ? 'virtual_receipt' : 'image',
        transactionType: _transactionType,
      );
      if (!mounted) return;
      _handleScanResult(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _submitBankMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _phase = _Phase.uploading;
      _errorMessage = null;
    });

    try {
      final result = await _receiptService.bankMessage(message);
      if (!mounted) return;
      _handleScanResult(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _handleScanResult(ScanResult result) {
    if (result.isDuplicate) {
      setState(() {
        _phase = _Phase.done;
        _detail = ReceiptDetail(
          receipt: Receipt(
            id: result.receiptId,
            inputType: 'image',
            status: 'duplicate',
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
      });
      return;
    }

    setState(() {
      _phase = _Phase.processing;
      _receiptId = result.receiptId;
    });
    _startPolling(result.receiptId);
  }

  void _startPolling(int receiptId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final detail = await _receiptService.get(receiptId);
        if (!mounted) return;
        if (detail.receipt.isFinal) {
          timer.cancel();
          setState(() {
            _phase = _Phase.done;
            _detail = detail;
          });
          // A transaction may have been created — refresh dependent data.
          if (detail.receipt.status == 'success' ||
              detail.receipt.status == 'needs_review') {
            if (!mounted) return;
            context.read<TransactionProvider>().loadTransactions();
            context.read<DashboardProvider>().loadDashboard();
            context.read<BudgetProvider>().loadBudgets(force: true);
            context.read<ReceiptProvider>().loadReceipts(force: true);
          }
        } else {
          setState(() => _detail = detail);
        }
      } catch (e) {
        if (!mounted) return;
        timer.cancel();
        setState(() {
          _phase = _Phase.done;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    });
  }

  Future<void> _reprocess() async {
    if (_receiptId == null) return;
    final id = _receiptId!;

    setState(() {
      _phase = _Phase.processing;
      _errorMessage = null;
      _detail = null;
    });

    try {
      await _receiptService.reprocess(id);
      _startPolling(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _reset() {
    _pollTimer?.cancel();
    setState(() {
      _phase = _Phase.idle;
      _selectedImage = null;
      _imageBytes = null;
      _messageController.clear();
      _receiptId = null;
      _detail = null;
      _errorMessage = null;
      _transactionType = 'expense';
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: switch (_phase) {
        _Phase.idle => _buildIdle(),
        _Phase.uploading => _buildProgress('Uploading...'),
        _Phase.processing => _buildProcessing(),
        _Phase.done => _buildResult(),
      },
    );
  }

  Widget _buildIdle() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<_Mode>(
          segments: const [
            ButtonSegment(value: _Mode.image, label: Text('Cash Receipt')),
            ButtonSegment(value: _Mode.online, label: Text('Online Receipt')),
            ButtonSegment(
              value: _Mode.bankMessage,
              label: Text('Bank Message'),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (set) => setState(() => _mode = set.first),
        ),
        if (_showInstructions) ...[
          const SizedBox(height: 16),
          _buildInstructionsCard(),
        ],
        if (_mode == _Mode.image || _mode == _Mode.online) ...[
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
            ],
            selected: {_transactionType},
            onSelectionChanged: (set) =>
                setState(() => _transactionType = set.first),
          ),
        ],
        const SizedBox(height: 24),
        if (_mode == _Mode.image || _mode == _Mode.online)
          _buildImageMode()
        else
          _buildBankMessageMode(),
      ],
    );
  }

  Widget _buildInstructionsCard() {
    final (title, body, tips) = switch (_mode) {
      _Mode.image => (
        'Cash Receipt',
        'Take a clear photo of a paper receipt or upload one from your gallery. The AI will automatically extract the amount, merchant, date, and other details.',
        'For best results: good lighting, flat surface, all corners visible.',
      ),
      _Mode.online => (
        'Online Receipt',
        'Upload a screenshot of a digital receipt from apps like Daraz, Foodpanda, or your banking app. The AI will parse the transaction details from the image.',
        'For best results: capture the full receipt with all text readable.',
      ),
      _Mode.bankMessage => (
        'Bank Message',
        'Paste a bank SMS or transaction notification text. The AI will extract the amount, merchant, and date from the message without needing an image.',
        'Example: "Your card ending in 1234 has been charged PKR 1,500 at Naheed Superstore on 15-Sep-26".',
      ),
    };

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() => _showInstructions = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 8),
            Text(tips, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildImageMode() {
    if (_imageBytes == null) {
      return Column(
        children: [
          _pickOption(
            icon: Icons.camera_alt_outlined,
            label: 'Take Photo',
            onTap: () => _pickImage(ImageSource.camera),
          ),
          const SizedBox(height: 12),
          _pickOption(
            icon: Icons.photo_outlined,
            label: 'Choose from Gallery',
            onTap: () => _pickImage(ImageSource.gallery),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_imageBytes!, height: 300, fit: BoxFit.contain),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _uploadImage,
          child: const Text('Upload & Scan'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _selectedImage = null;
            _imageBytes = null;
          }),
          child: const Text('Change Image'),
        ),
      ],
    );
  }

  Widget _buildBankMessageMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _messageController,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Bank Message',
            hintText: 'Paste your bank SMS or transaction message here...',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _messageController.text.trim().isEmpty
              ? null
              : _submitBankMessage,
          child: const Text('Submit & Parse'),
        ),
      ],
    );
  }

  Widget _pickOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 28),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildProgress(String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    final status = _detail?.receipt.status ?? 'queued';
    final label = switch (status) {
      'processing' => 'AI is parsing your receipt...',
      'queued' => 'Queued for processing...',
      _ => 'Processing...',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          TextButton(onPressed: _reset, child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildResult() {
    final receipt = _detail?.receipt;
    final status = receipt?.status ?? 'failed';
    final transaction = _detail?.transaction;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildResultHeader(status),
        const SizedBox(height: 16),
        if (transaction != null) ...[
          _buildTransactionCard(transaction),
          const SizedBox(height: 16),
        ],
        if (_errorMessage != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[700]),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (status == 'failed') ...[
          FilledButton(onPressed: _reprocess, child: const Text('Try Again')),
          const SizedBox(height: 8),
        ],
        OutlinedButton(onPressed: _reset, child: const Text('Scan Another')),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildResultHeader(String status) {
    return switch (status) {
      'success' => _resultIcon(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF43A047),
        title: 'Transaction Created',
        subtitle: 'Your receipt has been processed successfully.',
      ),
      'needs_review' => _resultIcon(
        icon: Icons.pending_actions_outlined,
        color: const Color(0xFFFF9800),
        title: 'Needs Review',
        subtitle: 'Review and confirm the transaction in the Transactions tab.',
      ),
      'failed' => _resultIcon(
        icon: Icons.error_outline,
        color: const Color(0xFFE53935),
        title: 'Scan Failed',
        subtitle: 'The receipt could not be processed.',
      ),
      'duplicate' => _resultIcon(
        icon: Icons.content_copy_outlined,
        color: Colors.grey,
        title: 'Already Processed',
        subtitle: 'This receipt has already been uploaded.',
      ),
      _ => _resultIcon(
        icon: Icons.help_outline,
        color: Colors.grey,
        title: 'Unknown Status',
        subtitle: status,
      ),
    };
  }

  Widget _resultIcon({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(ReceiptTransaction txn) {
    final isExpense = txn.type == 'expense';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parsed Transaction',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _detailRow(
              'Amount',
              Formatters.currency(
                double.parse(txn.amount),
                code: context.read<AuthProvider>().user?.currency ??
                    'PKR',
              ),
            ),
            if (txn.merchant != null) _detailRow('Merchant', txn.merchant!),
            if (txn.transactionDate != null)
              _detailRow('Date', Formatters.date(txn.transactionDate!)),
            _detailRow('Type', isExpense ? 'Expense' : 'Income'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
