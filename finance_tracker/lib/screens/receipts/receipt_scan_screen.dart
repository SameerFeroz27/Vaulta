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
import '../../utils/errors.dart';
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
  // 'auto' lets the AI decide the direction; 'expense'/'income' override it.
  String _typeChoice = 'auto';
  bool _showInstructions = true;

  XFile? _selectedImage;
  Uint8List? _imageBytes;
  final _messageController = TextEditingController();

  int? _receiptId;
  ReceiptDetail? _detail;
  String? _errorMessage;
  Timer? _pollTimer;
  bool _resolving = false;

  /// True when the parse succeeded but the direction was left for the user to settle.
  /// A parse *failure* also yields a needs_review receipt, but has no transaction.
  bool get _isDirectionPending =>
      _detail?.receipt.status == 'needs_review' && _detail?.transaction != null;

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
        // Null means "no override — let the AI decide".
        transactionType: _typeChoice == 'auto' ? null : _typeChoice,
      );
      if (!mounted) return;
      _handleScanResult(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.done;
          _errorMessage = errorMessage(e);
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
          _errorMessage = errorMessage(e);
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
          _errorMessage = errorMessage(e);
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
          _errorMessage = errorMessage(e);
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
      _typeChoice = 'auto';
      _resolving = false;
    });
  }

  /// Resolve the direction without leaving this screen. Confirming the AI's guess and
  /// flipping it are both one tap, so a held-back receipt never becomes a detour into
  /// the Transactions tab.
  Future<void> _resolveDirection(String? newType) async {
    final txn = _detail?.transaction;
    final receiptId = _receiptId;
    if (txn == null || receiptId == null || _resolving) return;

    setState(() => _resolving = true);

    final provider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final ok = newType == null
        ? await provider.confirmTransaction(txn.id)
        : await provider.updateTransaction(txn.id, {
            'type': newType,
            'status': 'confirmed',
          });

    if (!mounted) return;

    if (!ok) {
      setState(() => _resolving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update the transaction.')),
      );
      return;
    }

    // Re-read the receipt so the header reflects the resolved state.
    try {
      final detail = await _receiptService.get(receiptId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _resolving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolving = false);
    }
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
            ButtonSegment(value: _Mode.image, label: Text('Cash')),
            ButtonSegment(value: _Mode.online, label: Text('Online')),
            ButtonSegment(
              value: _Mode.bankMessage,
              label: Text('Bank SMS'),
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
              ButtonSegment(
                value: 'auto',
                label: Text('Auto'),
                icon: Icon(Icons.auto_awesome, size: 18),
              ),
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
            ],
            selected: {_typeChoice},
            onSelectionChanged: (set) =>
                setState(() => _typeChoice = set.first),
          ),
          const SizedBox(height: 6),
          Text(
            _typeChoice == 'auto'
                ? 'The AI will work out whether this is income or expense. '
                    'Anything it is unsure about is held for a one-tap review.'
                : 'Overriding the AI — this will be filed as '
                    '${_typeChoice == 'income' ? 'income' : 'expense'}.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
        if (transaction != null && _isDirectionPending) ...[
          _buildReviewActions(transaction),
          const SizedBox(height: 16),
        ],
        if (_errorMessage != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
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

  Widget _buildReviewActions(ReceiptTransaction txn) {
    final isExpense = txn.type == 'expense';

    return Card(
      color: Colors.orange.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and buttons only. The direction and its consequences are already
            // stated by the result header above, so a body sentence here would just
            // repeat it.
            const Text(
              'Confirm the direction',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _resolving ? null : () => _resolveDirection(null),
                    child: _resolving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _resolving
                        ? null
                        : () =>
                              _resolveDirection(isExpense ? 'income' : 'expense'),
                    child: Text('Change to ${isExpense ? 'Income' : 'Expense'}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
        bold: true,
        // needs_review covers two cases: parsing failed outright (no transaction),
        // or the parse succeeded but the direction was uncertain (transaction exists).
        // The second case keeps only the fact the user cannot see elsewhere: this is
        // held back from their totals.
        subtitle: _detail?.transaction == null
            ? 'The receipt could not be read. Try scanning it again.'
            : 'Not in your totals until you confirm the direction below.',
      ),
      'failed' => _resultIcon(
        icon: Icons.error_outline,
        color: const Color(0xFFE53935),
        title: 'Scan Failed',
        bold: true,
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
    // Warning and error states are emphasised like the inline notices; the
    // success and duplicate states stay in the quieter body weight.
    bool bold = false,
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
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(ReceiptTransaction txn) {
    final isExpense = txn.type == 'expense';
    final confidence = txn.typeConfidence;
    final evidence = _detail?.receipt.directionEvidence;
    final wasAutoDecided = txn.typeSource == 'ai_auto';
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
            if (wasAutoDecided && confidence != null)
              _detailRow('AI confidence', '${(confidence * 100).round()}%'),
            if (wasAutoDecided && evidence != null && evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Decided from: $evidence',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
          Flexible(
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
