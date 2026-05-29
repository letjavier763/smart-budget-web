import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/payment_request.dart';
import '../services/firestore_service.dart';
import '../theme/translations.dart';

class _GroupedPayment {
  final GroupModel group;
  final List<Expense> expenses;
  const _GroupedPayment({required this.group, required this.expenses});
}

class PaymentsScreen extends StatefulWidget {
  final int initialIndex;
  const PaymentsScreen({super.key, this.initialIndex = 0});

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final service = FirestoreService();

  // One future per tab — initialized in initState so they never reset on rebuild
  Future<List<_GroupedPayment>>? _paymentsFuture;
  Future<List<PaymentRequest>>? _requestsFuture;
  late final Stream<List<PaymentRequest>> _pendingPaymentsStream;
  late final Stream<List<PaymentRequest>> _requestsStream;
  late final Stream<List<MapEntry<GroupModel, Expense>>> _historyStream;

  final Map<String, String> _groupIdToName = {};
  late final String _email;

  @override
  void initState() {
    super.initState();
    _email = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialIndex);
    _paymentsFuture = _initPayments();
    _requestsFuture = _initRequests();
    _pendingPaymentsStream = service.activePaymentRequestsForUser(_email);
    _requestsStream = service.activePaymentRequestsForUser(_email);
    _historyStream = service.userExpensesStream(_email);
  }

  Future<List<_GroupedPayment>> _initPayments() async {
    final groups = await service.getGroupsForUser(_email);
    for (final g in groups) {
      _groupIdToName[g.id] = g.name;
    }
    return _loadPayments(_email, groups, service);
  }

  Future<List<PaymentRequest>> _initRequests() async {
    final groups = await service.getGroupsForUser(_email);
    for (final g in groups) {
      _groupIdToName[g.id] = g.name;
    }
    return _loadAllRequests(_email, groups, service);
  }

  void _refreshData() {
    setState(() {
      _paymentsFuture = _initPayments();
      _requestsFuture = _initRequests();
    });
  }

  void _showReceiptDialog(String base64Image) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(base64Image),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        title: Text(tr('Estado de Cuenta', 'Account Balance'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: colorScheme.primary,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.6),
          tabs: [
            Tab(icon: const Icon(Icons.receipt_long_outlined), text: tr('Historial', 'History')),
            StreamBuilder<List<PaymentRequest>>(
              stream: _pendingPaymentsStream,
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                return Tab(
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count', style: const TextStyle(color: Colors.white)),
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.send_outlined),
                  ),
                  text: tr('Solicitudes y Pagos', 'Requests & Payments'),
                );
              },
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ─── TAB 1: Historial de gastos pagados ───
          _buildHistoryTab(colorScheme, textTheme),
          // ─── TAB 2: Solicitudes enviadas / recibidas ───
          _buildRequestsTab(colorScheme, textTheme),
        ],
      ),
    );
  }

  // ────────────────────────── Historial ──────────────────────────

  Widget _buildHistoryTab(ColorScheme colorScheme, TextTheme textTheme) {
    return StreamBuilder<List<MapEntry<GroupModel, Expense>>>(
      stream: _historyStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorState(colorScheme, '${tr('Error al cargar historial', 'Error loading history')}: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allPayments = snap.data ?? [];
        if (allPayments.isEmpty) {
          return _emptyState(colorScheme, tr('Aún no tienes gastos registrados.', 'You don\'t have any registered expenses yet.'), Icons.receipt_outlined);
        }

        final total = allPayments.fold<double>(0, (s, e) => s + e.value.amount);
        final groupCount = allPayments.map((e) => e.key.id).toSet().length;

        return Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.tertiary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Total pagado', 'Total paid'), style: TextStyle(color: colorScheme.onTertiary.withAlpha(200), fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Q${total.toStringAsFixed(2)}', style: TextStyle(color: colorScheme.onTertiary, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(tr('${allPayments.length} pago(s) en $groupCount grupo(s)', '${allPayments.length} payment(s) in $groupCount group(s)'), style: TextStyle(color: colorScheme.onTertiary.withAlpha(180), fontSize: 12)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: allPayments.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final group = allPayments[i].key;
                  final expense = allPayments[i].value;
                  final date = expense.createdAt;
                  final isPayment = expense.type == 'payment';
                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isPayment ? colorScheme.primary.withValues(alpha: 0.15) : colorScheme.tertiaryContainer.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isPayment ? Icons.check_circle_outline : _categoryIcon(expense.category),
                              color: isPayment ? colorScheme.primary : colorScheme.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(expense.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    _statusBadge(
                                      isPayment
                                          ? '${tr('PAGO', 'PAYMENT')}: ${translateCategory(expense.category).toUpperCase()}'
                                          : translateCategory(expense.category).toUpperCase(),
                                      colorScheme,
                                      isPayment: isPayment,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(group.name, style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${date.day}/${date.month}/${date.year}', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (expense.imageUrl != null && expense.imageUrl!.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _showReceiptDialog(expense.imageUrl!),
                              child: Container(
                                width: 36,
                                height: 36,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.5),
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: Image.memory(
                                          base64Decode(expense.imageUrl!),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 1,
                                        right: 1,
                                        child: Container(
                                          padding: const EdgeInsets.all(1),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.zoom_in,
                                            size: 8,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          Text(
                            'Q${expense.amount.toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: isPayment ? colorScheme.primary : colorScheme.tertiary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ────────────────────────── Solicitudes ──────────────────────────

  Widget _buildRequestsTab(ColorScheme colorScheme, TextTheme textTheme) {
    return StreamBuilder<List<PaymentRequest>>(
      stream: _requestsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorState(colorScheme, '${tr('Error al cargar solicitudes', 'Error loading requests')}: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allReqs = snap.data ?? [];
        if (allReqs.isEmpty) {
          return _emptyState(colorScheme, tr('No tienes solicitudes de pago todavía.', 'You don\'t have any payment requests yet.'), Icons.send_outlined);
        }

        final all = <MapEntry<String, PaymentRequest>>[];
        for (final r in allReqs) {
          if (r.status == 'confirmado') continue;
          final to = r.toEmail.trim().toLowerCase();
          final from = r.fromEmail.trim().toLowerCase();
          if (to == _email) {
            all.add(MapEntry('incoming', r));
          } else if (from == _email) {
            all.add(MapEntry('sent', r));
          }
        }
        all.sort((a, b) => b.value.createdAt.compareTo(a.value.createdAt));

        if (all.isEmpty) {
          return _emptyState(colorScheme, tr('No tienes solicitudes de pago todavía.', 'You don\'t have any payment requests yet.'), Icons.send_outlined);
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: all.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final type = all[i].key;
            final req = all[i].value;
            return _requestCard(req, type, _email, colorScheme, textTheme, context, index: i + 1);
          },
        );
      },
    );
  }

  Widget _requestCard(PaymentRequest req, String type, String email, ColorScheme colorScheme, TextTheme textTheme, BuildContext context, {required int index}) {
    final isIncoming = req.toEmail.trim().toLowerCase() == email.trim().toLowerCase();
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (req.status) {
      case 'confirmado':
        statusColor = colorScheme.primary;
        statusLabel = tr('Cancelado', 'Cancelled');
        statusIcon = Icons.check_circle_outline;
        break;
      case 'rechazado':
        statusColor = colorScheme.error;
        statusLabel = tr('Rechazado', 'Rejected');
        statusIcon = Icons.cancel_outlined;
        break;
      case 'pendiente_boleta':
        statusColor = colorScheme.secondary;
        statusLabel = isIncoming ? tr('Esperando boleta', 'Awaiting receipt') : tr('Por pagar', 'To pay');
        statusIcon = Icons.hourglass_top_rounded;
        break;
      default:
        statusColor = colorScheme.tertiary;
        statusLabel = tr('Revisión', 'Review');
        statusIcon = Icons.hourglass_top_rounded;
    }

    final otherPerson = isIncoming ? req.fromEmail.split('@')[0] : req.toEmail.split('@')[0];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withAlpha(60)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  child: Text('$index', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                Icon(isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded, size: 16, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  isIncoming ? tr('De $otherPerson', 'From $otherPerson') : tr('A $otherPerson', 'To $otherPerson'),
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withAlpha(25), borderRadius: BorderRadius.circular(99)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(statusLabel, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Q${req.amount.toStringAsFixed(2)}', style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                if (req.imageUrl != null && req.imageUrl!.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showReceiptDialog(req.imageUrl!),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: statusColor.withAlpha(120),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.memory(
                                base64Decode(req.imageUrl!),
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              bottom: 1,
                              right: 1,
                              child: Container(
                                padding: const EdgeInsets.all(1),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.zoom_in,
                                  size: 8,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withAlpha(80),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_outlined, size: 12, color: colorScheme.onSecondaryContainer),
                      const SizedBox(width: 4),
                      Text(
                        _groupIdToName[req.groupId] ?? tr('Grupo', 'Group'),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withAlpha(80),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getRubroIcon(req.rubro), size: 12, color: colorScheme.onPrimaryContainer),
                      const SizedBox(width: 4),
                      Text(
                        translateCategory(req.rubro),
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.brightness == Brightness.light ? Colors.white : colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (req.reference != null && req.reference!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.reference!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 11, color: colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  tr('Fecha de pago: ${req.date.day}/${req.date.month}/${req.date.year}', 'Payment date: ${req.date.day}/${req.date.month}/${req.date.year}'),
                  style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                ),
              ],
            ),
            if (isIncoming && req.status == 'pendiente') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: Text(tr('Rechazar', 'Reject')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        side: BorderSide(color: colorScheme.error),
                        minimumSize: const Size(0, 36),
                      ),
                      onPressed: () async {
                        await service.rejectPaymentRequest(groupId: req.groupId, requestId: req.id, request: req);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Solicitud rechazada.', 'Request rejected.'))));
                          _refreshData();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(tr('Confirmar', 'Confirm')),
                      style: FilledButton.styleFrom(backgroundColor: colorScheme.primary, minimumSize: const Size(0, 36)),
                      onPressed: () async {
                        await service.confirmPaymentRequest(groupId: req.groupId, requestId: req.id, request: req);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Pago confirmado.', 'Payment confirmed.')), backgroundColor: colorScheme.primary));
                          _refreshData();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ] else if (!isIncoming && (req.status == 'pendiente_boleta' || req.status == 'rechazado')) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.payment, size: 16),
                  label: Text(tr('Pagar', 'Pay')),
                  style: FilledButton.styleFrom(backgroundColor: colorScheme.primary, minimumSize: const Size(0, 36)),
                  onPressed: () => _showPayRequestDialog(context, req),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ────────────────────────── Helpers ──────────────────────────

  Future<void> _showPayRequestDialog(BuildContext context, PaymentRequest req) async {
    final amountController = TextEditingController(text: req.amount.toStringAsFixed(2));
    final referenceController = TextEditingController(text: req.reference ?? '');
    String selectedMethod = req.method.isNotEmpty ? req.method : 'Boleta';
    final validRubros = ['Comida', 'Alquiler', 'Servicios', 'Actividades', 'Transporte', 'Otros'];
    String selectedRubro = validRubros.contains(req.rubro) ? req.rubro : 'Otros';
    DateTime selectedDate = req.date;
    String? selectedImageBase64;
    bool isUploadingImage = false;

    Future<void> pickImage(StateSetter setSheetState) async {
      final picker = ImagePicker();
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx2) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(tr('Tomar foto con Cámara', 'Take photo with Camera')),
                onTap: () => Navigator.pop(ctx2, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(tr('Elegir de Galería', 'Choose from Gallery')),
                onTap: () => Navigator.pop(ctx2, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      setSheetState(() => isUploadingImage = true);
      try {
        final pickedFile = await picker.pickImage(
          source: source,
          imageQuality: 50,
          maxWidth: 500,
          maxHeight: 500,
        );
        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          setSheetState(() {
            selectedImageBase64 = base64Encode(bytes);
          });
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Error al cargar imagen', 'Error loading image')}: $e')),
          );
        }
      } finally {
        setSheetState(() => isUploadingImage = false);
      }
    }

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.payment_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Realizar pago a', 'Make payment to'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            req.toEmail.split('@')[0],
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  tr('Monto a pagar', 'Amount to pay'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    prefixText: 'Q ',
                    helperText: tr('Monto solicitado: Q${req.amount.toStringAsFixed(2)}', 'Requested amount: Q${req.amount.toStringAsFixed(2)}'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('Rubro del pago', 'Payment category'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedRubro,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: ['Comida', 'Alquiler', 'Servicios', 'Actividades', 'Transporte', 'Otros']
                      .map((r) => DropdownMenuItem(value: r, child: Text(translateCategory(r))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setSheetState(() => selectedRubro = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  tr('Fecha de pago', 'Payment date'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          tr('Cambiar', 'Change'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('Imagen de la boleta / recibo (obligatorio)', 'Image of receipt / bill (required)'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                if (isUploadingImage)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (selectedImageBase64 != null)
                  Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.memory(
                              base64Decode(selectedImageBase64!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: CircleAvatar(
                            backgroundColor: Colors.black.withAlpha(180),
                            radius: 16,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, size: 16, color: Colors.white),
                              onPressed: () => setSheetState(() => selectedImageBase64 = null),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => pickImage(setSheetState),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(tr('Subir Foto de Boleta', 'Upload Receipt Photo')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  tr('Referencia (opcional)', 'Reference (optional)'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: referenceController,
                  decoration: InputDecoration(
                    hintText: tr('Ej: No. operación, nota...', 'E.g. Operation No., note...'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.send),
                    label: Text(tr('Completar Pago', 'Complete Payment')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final amount = double.tryParse(amountController.text.trim().replaceAll(',', '.'));
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('Ingresa un monto válido.', 'Enter a valid amount.'))),
                        );
                        return;
                      }
                      if (selectedImageBase64 == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('Por favor, sube la imagen de la boleta de pago.', 'Please upload the image of the payment receipt.'))),
                        );
                        return;
                      }

                      // Mostrar cargando
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx3) => const PopScope(
                          canPop: false,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );

                      try {
                        await service.submitBoletaForPaymentRequest(
                          groupId: req.groupId,
                          requestId: req.id,
                          imageUrl: selectedImageBase64!,
                          request: req,
                          method: selectedMethod,
                          reference: referenceController.text.trim().isEmpty ? null : referenceController.text.trim(),
                          amount: amount,
                          rubro: selectedRubro,
                          date: selectedDate,
                        );

                        // Cerrar diálogo de cargando y modal sheet
                        if (context.mounted) {
                          Navigator.pop(context); // Cierra cargando
                          Navigator.pop(context); // Cierra bottom sheet
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(tr('Pago completado con éxito.', 'Payment completed successfully.')),
                              backgroundColor: Theme.of(context).colorScheme.primary,
                            ),
                          );
                          _refreshData();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // Cierra cargando
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${tr('Error al procesar pago', 'Error processing payment')}: $e'),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String label, ColorScheme colorScheme, {bool isPayment = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isPayment ? colorScheme.primary.withValues(alpha: 0.15) : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isPayment ? colorScheme.primary : colorScheme.onSurfaceVariant),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Servicio': return Icons.build_outlined;
      case 'Actividad': return Icons.local_activity_outlined;
      default: return Icons.shopping_bag_outlined;
    }
  }

  IconData _getRubroIcon(String rubro) {
    switch (rubro.toLowerCase()) {
      case 'comida':
        return Icons.restaurant_outlined;
      case 'alquiler':
        return Icons.home_outlined;
      case 'servicios':
        return Icons.power_outlined;
      case 'actividades':
        return Icons.local_activity_outlined;
      case 'transporte':
        return Icons.directions_car_outlined;
      default:
        return Icons.local_offer_outlined;
    }
  }

  Future<List<_GroupedPayment>> _loadPayments(String email, List<GroupModel> groups, FirestoreService service) async {
    final results = await Future.wait(
      groups.map((group) async {
        try {
          final all = await service.getExpensesForGroup(group.id);
          return MapEntry(group, all);
        } catch (e) {
          debugPrint('Error loading expenses for group ${group.id}: $e');
          return MapEntry(group, <Expense>[]);
        }
      }),
    );

    final result = <_GroupedPayment>[];
    for (final entry in results) {
      final group = entry.key;
      final allExpenses = entry.value;
      final mine = allExpenses
          .where((e) =>
              e.paidBy.trim().toLowerCase() == email ||
              (e.type == 'payment' && e.paidTo?.trim().toLowerCase() == email))
          .toList();
      if (mine.isNotEmpty) {
        result.add(_GroupedPayment(group: group, expenses: mine));
      }
    }
    return result;
  }

  Future<List<PaymentRequest>> _loadAllRequests(String email, List<GroupModel> groups, FirestoreService service) async {
    final results = await Future.wait(
      groups.map((group) async {
        try {
          final reqs = await service.getPaymentRequestsForGroup(group.id);
          return reqs;
        } catch (e) {
          debugPrint('Error loading requests for group ${group.id}: $e');
          return <PaymentRequest>[];
        }
      }),
    );
    final all = <PaymentRequest>[];
    for (final reqs in results) {
      all.addAll(reqs);
    }
    return all;
  }

  Widget _emptyState(ColorScheme colorScheme, String msg, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _errorState(ColorScheme colorScheme, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error, fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
              label: Text(tr('Reintentar', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}
