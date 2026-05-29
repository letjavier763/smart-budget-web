import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// ignore_for_file: unused_element_parameter

import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../models/group.dart';
import '../widgets/group_avatar.dart';
import '../models/group_invitation.dart';
import '../models/payment_request.dart';
import '../services/firestore_service.dart';
import '../theme/translations.dart';
import '../utils/print_utility.dart';


class Settlement {
  final String debtor;
  final String creditor;
  final double amount;
  Settlement(this.debtor, this.creditor, this.amount);
}

class GroupDetailScreen extends StatefulWidget {
  final GroupModel group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  // Helper fields
  String currentUserEmail = '';
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final memberController = TextEditingController();
  final firestoreService = FirestoreService();

  Map<String, String> _memberNames = {};
  late final Stream<GroupModel?> _groupStream;
  late final Stream<List<Expense>> _expensesStream;
  late final Stream<List<PaymentRequest>> _requestsStream;

  @override
  void initState() {
    super.initState();
    currentUserEmail =
        FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';
    _groupStream = firestoreService.groupStream(widget.group.id);
    _expensesStream = firestoreService.expensesForGroup(widget.group.id);
    _requestsStream = firestoreService.pendingRequestsForGroup(widget.group.id);
    _loadMemberNames();
  }

  Future<void> _loadMemberNames() async {
    final names = <String, String>{};
    for (final email in widget.group.members) {
      final snap = await firestoreService.getUserProfileByEmail(email);
      final data = snap?.data() as Map<String, dynamic>?;
      if (data != null &&
          data['displayName'] != null &&
          data['displayName'].toString().trim().isNotEmpty) {
        names[email] = data['displayName'] as String;
      }
    }
    if (mounted) {
      setState(() {
        _memberNames = names;
      });
    }
  }

  String _getMemberName(String email) {
    if (_memberNames.containsKey(email)) {
      return _memberNames[email]!;
    }
    return email;
  }

  Future<void> _showAddExpenseDialog(GroupModel group) async {
    titleController.clear();
    amountController.clear();
    String selectedCategory = 'Otros';
    Set<String> selectedMembers = {...group.members};
    DateTime? selectedDueDate;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(tr('Nuevo Gasto', 'New Expense')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Descripción del gasto',
                          'Expense description',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: tr('Monto', 'Amount'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        labelText: tr('Categoría', 'Category'),
                      ),
                      items:
                          [
                                'Comida',
                                'Alquiler',
                                'Servicios',
                                'Actividades',
                                'Transporte',
                                'Otros',
                              ]
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(translateCategory(c)),
                                ),
                              )
                              .toList(),
                      onChanged: (c) =>
                          setDialogState(() => selectedCategory = c!),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        selectedDueDate == null
                            ? tr(
                                'Sin fecha límite de pago',
                                'No payment deadline',
                              )
                            : '${tr('Límite', 'Deadline')}: ${selectedDueDate!.day}/${selectedDueDate!.month}/${selectedDueDate!.year}',
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(
                            const Duration(days: 1),
                          ),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setDialogState(() => selectedDueDate = date);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('Involucrados:', 'Involved:'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ...group.members.map(
                      (m) => CheckboxListTile(
                        title: Text(m),
                        value: selectedMembers.contains(m),
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedMembers.add(m);
                            } else {
                              selectedMembers.remove(m);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Cancelar', 'Cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    final amount = double.tryParse(
                      amountController.text.trim().replaceAll(',', '.'),
                    );
                    if (title.isEmpty ||
                        amount == null ||
                        amount <= 0 ||
                        selectedMembers.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            tr(
                              'Ingresa título, monto y al menos 1 involucrado.',
                              'Enter title, amount, and at least 1 member.',
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    FocusScope.of(context).unfocus();
                    final paidBy =
                        FirebaseAuth.instance.currentUser?.email ??
                        group.createdBy;
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    try {
                      await firestoreService.createExpense(
                        groupId: group.id,
                        title: title,
                        amount: amount,
                        paidBy: paidBy,
                        involvedMembers: selectedMembers.toList(),
                        category: selectedCategory,
                        dueDate: selectedDueDate,
                      );
                      navigator.pop();
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: Text(tr('Guardar', 'Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickAndSubmitBoleta(PaymentRequest req) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx2) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(
                tr('Tomar foto con Cámara', 'Take photo with Camera'),
              ),
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

    if (!mounted) return;

    BuildContext? dialogCtx;
    try {
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 50,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (pickedFile == null) return;

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogCtx = ctx;
          return const PopScope(
            canPop: false,
            child: Center(child: CircularProgressIndicator()),
          );
        },
      );

      final bytes = await pickedFile.readAsBytes();
      final base64Str = base64Encode(bytes);

      await firestoreService.submitBoletaForPaymentRequest(
        groupId: widget.group.id,
        requestId: req.id,
        request: req,
        imageUrl: base64Str,
      );

      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.pop(dialogCtx!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Boleta subida exitosamente.',
                'Receipt uploaded successfully.',
              ),
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (dialogCtx != null && dialogCtx!.mounted) {
        Navigator.pop(dialogCtx!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${tr('Error al subir boleta', 'Error uploading receipt')}: $e',
            ),
          ),
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _showPaymentRequestDialog(Settlement s) async {
    amountController.text = s.amount.toStringAsFixed(2);
    final referenceController = TextEditingController();
    String selectedMethod = 'Boleta';
    String selectedRubro = 'Otros';
    DateTime selectedDate = DateTime.now();
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
                title: Text(
                  tr('Tomar foto con Cámara', 'Take photo with Camera'),
                ),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${tr('Error al cargar imagen', 'Error loading image')}: $e',
              ),
            ),
          );
        }
      } finally {
        setSheetState(() => isUploadingImage = false);
      }
    }

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
                      Icons.send_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Enviar pago a', 'Send payment to'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            s.creditor.split('@')[0],
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Balances UI removed as redundant
                const SizedBox(height: 6),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    prefixText: 'Q ',
                    helperText:
                        '${tr('Deuda total', 'Total debt')}: Q${s.amount.toStringAsFixed(2)} — ${tr('puedes pagar menos (pago parcial)', 'you can pay less (partial payment)')}',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('Rubro del pago', 'Payment item'),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items:
                      [
                            'Comida',
                            'Alquiler',
                            'Servicios',
                            'Actividades',
                            'Transporte',
                            'Otros',
                          ]
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(translateCategory(r)),
                            ),
                          )
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
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setSheetState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
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
                  tr(
                    'Imagen de la boleta / recibo (obligatorio)',
                    'Receipt image (required)',
                  ),
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
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
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
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                              onPressed: () => setSheetState(
                                () => selectedImageBase64 = null,
                              ),
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
                    label: Text(
                      tr('Subir Foto de Boleta', 'Upload Receipt Photo'),
                    ),
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
                    hintText: tr(
                      'Ej: No. operación, nota...',
                      'e.g. Operation No., note...',
                    ),
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
                    label: Text(
                      tr('Enviar solicitud de pago', 'Send payment request'),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final amount = double.tryParse(
                        amountController.text.trim().replaceAll(',', '.'),
                      );
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(
                                'Ingresa un monto válido.',
                                'Enter a valid amount.',
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      if (amount > s.amount + 0.01) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${tr('El monto no puede superar la deuda', 'The amount cannot exceed the debt')} (Q${s.amount.toStringAsFixed(2)}).',
                            ),
                          ),
                        );
                        return;
                      }
                      if (selectedImageBase64 == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(
                                'Por favor, sube la imagen de la boleta de pago.',
                                'Please upload the image of the payment receipt.',
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      try {
                        await firestoreService.createPaymentRequest(
                          groupId: widget.group.id,
                          fromEmail: s.debtor,
                          toEmail: s.creditor,
                          amount: amount,
                          method: selectedMethod,
                          rubro: selectedRubro,
                          date: selectedDate,
                          imageUrl: selectedImageBase64,
                          reference: referenceController.text.trim().isEmpty
                              ? null
                              : referenceController.text.trim(),
                        );
                        if (context.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr(
                                  'Solicitud enviada. Esperando confirmación.',
                                  'Request sent. Awaiting confirmation.',
                                ),
                              ),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${tr('Error al enviar solicitud', 'Error sending request')}: $e',
                              ),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
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
    referenceController.dispose();
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

  void _showMemberProfile(
    String email,
    GroupModel group,
    bool currentUserIsAdmin,
  ) async {
    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<DocumentSnapshot?>(
          future: firestoreService.getUserProfileByEmail(email),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data?.data() as Map<String, dynamic>?;
            final photoUrl = data?['photoUrl'] as String?;
            final hasName =
                data != null &&
                data['displayName'] != null &&
                data['displayName'].toString().trim().isNotEmpty;
            final nameToShow = hasName ? data['displayName'] as String : email;

            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: photoUrl != null
                        ? MemoryImage(base64Decode(photoUrl))
                        : null,
                    child: photoUrl == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    nameToShow,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Cerrar', 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> showEditExpenseDialog(Expense expense) async {
    titleController.text = expense.title;
    amountController.text = expense.amount.toStringAsFixed(2);
    final validCategories = [
      'Comida',
      'Alquiler',
      'Servicios',
      'Actividades',
      'Transporte',
      'Otros',
    ];
    String selectedCategory = validCategories.contains(expense.category)
        ? expense.category
        : 'Otros';

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(tr('Editar gasto', 'Edit expense')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: tr('Descripción', 'Description'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: tr('Monto', 'Amount')),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setState) {
                  return DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: InputDecoration(
                      labelText: tr('Categoría', 'Category'),
                    ),
                    items:
                        [
                              'Comida',
                              'Alquiler',
                              'Servicios',
                              'Actividades',
                              'Transporte',
                              'Otros',
                            ]
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(translateCategory(c)),
                              ),
                            )
                            .toList(),
                    onChanged: (c) {
                      if (c != null) {
                        setState(() {
                          selectedCategory = c;
                        });
                      }
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancelar', 'Cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final amount = double.tryParse(
                  amountController.text.trim().replaceAll(',', '.'),
                );
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                if (title.isEmpty || amount == null || amount <= 0) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        tr(
                          'Ingresa un título y un monto válido.',
                          'Enter a valid title and amount.',
                        ),
                      ),
                    ),
                  );
                  return;
                }

                FocusScope.of(context).unfocus();

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('¿Modificar gasto?', 'Modify expense?')),
                    content: Text(tr(
                      'Este es un gasto general. Al modificarlo, se recalculará la división del gasto y se actualizarán automáticamente las solicitudes de pago pendientes de todos los miembros involucrados. ¿Deseas continuar?',
                      'This is a general expense. Modifying it will recalculate the split and automatically update the pending payment requests for all involved members. Do you want to continue?',
                    )),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('No', 'No')),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('Sí, modificar', 'Yes, modify')),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                try {
                  await firestoreService.updateExpense(
                    groupId: widget.group.id,
                    expenseId: expense.id,
                    title: title,
                    amount: amount,
                    category: selectedCategory,
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '${tr('Error al editar gasto', 'Error editing expense')}: $e',
                      ),
                    ),
                  );
                  return;
                }

                if (!mounted) return;
                navigator.pop();
                titleController.clear();
                amountController.clear();
              },
              child: Text(tr('Guardar', 'Save')),
            ),
          ],
        );
      },
    );
  }

  void _showExpenseCommentsSheet(Expense expense) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final textController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${tr('Pagado por', 'Paid by')} ${_getMemberName(expense.paidBy)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: firestoreService.commentsStream(
                    widget.group.id,
                    expense.id,
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final comments = snap.data ?? [];
                    if (comments.isEmpty) {
                      return Center(
                        child: Text(
                          tr(
                            'No hay comentarios. ¡Sé el primero en comentar!',
                            'No comments yet. Be the first to comment!',
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      reverse: true,
                      itemCount: comments.length,
                      itemBuilder: (context, i) {
                        final comment = comments[i];
                        final isMe = comment['userEmail'] == currentUserEmail;
                        final dt =
                            (comment['createdAt'] as Timestamp?)?.toDate() ??
                            DateTime.now();

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Text(
                                    _getMemberName(comment['userEmail']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                Text(comment['text'] ?? ''),
                                const SizedBox(height: 4),
                                Text(
                                  '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      decoration: InputDecoration(
                        hintText: tr(
                          'Escribe un comentario...',
                          'Write a comment...',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: () async {
                      if (textController.text.trim().isEmpty) return;
                      final txt = textController.text.trim();
                      textController.clear();
                      await firestoreService.addComment(
                        groupId: widget.group.id,
                        expenseId: expense.id,
                        text: txt,
                        userEmail: currentUserEmail,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditGroupDialog(GroupModel group) async {
    titleController.text = group.name;
    String? currentImageBase64 = group.imageUrl;
    String currentName = group.name;
    final maxMembersCtrl = TextEditingController(text: group.maxMembers?.toString() ?? '');
    final budgetCtrl = TextEditingController(text: group.initialBudget?.toString() ?? '');
    DateTime? selectedActiveUntil = group.activeUntil;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final previewGroup = GroupModel(
              id: group.id,
              name: currentName,
              code: group.code,
              members: group.members,
              createdBy: group.createdBy,
              admins: group.admins,
              createdAt: group.createdAt,
              imageUrl: currentImageBase64,
              maxMembers: int.tryParse(maxMembersCtrl.text),
              initialBudget: double.tryParse(budgetCtrl.text),
              activeUntil: selectedActiveUntil,
            );

            Future<void> pickImage() async {
              final picker = ImagePicker();
              final source = await showModalBottomSheet<ImageSource>(
                context: context,
                builder: (ctx2) => SafeArea(
                  child: Wrap(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.camera_alt_outlined),
                        title: Text(
                          tr('Tomar foto con Cámara', 'Take photo with Camera'),
                        ),
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

              try {
                final pickedFile = await picker.pickImage(
                  source: source,
                  imageQuality: 50,
                  maxWidth: 500,
                  maxHeight: 500,
                );
                if (pickedFile != null) {
                  final bytes = await pickedFile.readAsBytes();
                  setDialogState(() {
                    currentImageBase64 = base64Encode(bytes);
                  });
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${tr('Error al cargar imagen', 'Error loading image')}: $e',
                      ),
                    ),
                  );
                }
              }
            }

            return AlertDialog(
              title: Text(tr('Editar grupo', 'Edit group')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          GroupAvatar(group: previewGroup, size: 80),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              backgroundColor: theme.colorScheme.primary,
                              radius: 16,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                onPressed: pickImage,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (currentImageBase64 != null && currentImageBase64!.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: Text(
                          tr('Quitar imagen', 'Remove image'),
                          style: const TextStyle(color: Colors.red),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            currentImageBase64 = null;
                          });
                        },
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: tr('Nombre del grupo', 'Group name'),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          currentName = value.trim();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxMembersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('Capacidad máxima de miembros (opcional)', 'Max member capacity (optional)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: budgetCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: tr('Presupuesto inicial (opcional)', 'Initial budget (optional)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(
                        selectedActiveUntil == null
                            ? tr('Tiempo de actividad (opcional)', 'Activity duration (optional)')
                            : '${tr('Activo hasta', 'Active until')}: ${selectedActiveUntil!.day}/${selectedActiveUntil!.month}/${selectedActiveUntil!.year}',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedActiveUntil ?? DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 3650)),
                          );
                          if (date != null) {
                            setDialogState(() {
                              selectedActiveUntil = date;
                            });
                          }
                        },
                        child: Text(tr('Seleccionar', 'Select')),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(tr('Cancelar', 'Cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = titleController.text.trim();
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    if (name.isEmpty) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            tr('Ingresa un nombre válido.', 'Enter a valid name.'),
                          ),
                        ),
                      );
                      return;
                    }

                    FocusScope.of(context).unfocus();

                    try {
                      await firestoreService.updateGroup(
                        groupId: group.id,
                        name: name,
                        imageUrl: currentImageBase64,
                        maxMembers: int.tryParse(maxMembersCtrl.text.trim()),
                        initialBudget: double.tryParse(budgetCtrl.text.trim().replaceAll(',', '.')),
                        activeUntil: selectedActiveUntil,
                      );
                      navigator.pop();
                      titleController.clear();
                    } catch (e) {
                      if (context.mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  child: Text(tr('Guardar', 'Save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteGroup(GroupModel group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminar grupo', 'Delete group')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(ctx).colorScheme.error,
              size: 48,
            ),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: Theme.of(ctx).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: tr(
                      '¿Estás seguro de que quieres eliminar el grupo ',
                      'Are you sure you want to delete the group ',
                    ),
                  ),
                  TextSpan(
                    text: '"${group.name}"',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: '?\n\n'),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                tr(
                  'Esta acción es irreversible. Se eliminarán todos los gastos, pagos y datos del grupo permanentemente.',
                  'This action is irreversible. All expenses, payments, and group data will be deleted permanently.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Sí, eliminar', 'Yes, delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await firestoreService.deleteGroup(groupId: group.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('El grupo', 'The group')} "${group.name}" ${tr('fue eliminado.', 'was deleted.')}',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('Error al eliminar el grupo', 'Error deleting group')}: $e',
          ),
        ),
      );
    }
  }

  Future<void> _confirmLeaveGroup(GroupModel group) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Salir del Grupo', 'Leave Group')),
        content: Text(tr(
          '¿Estás seguro de que deseas salir de este grupo?',
          'Are you sure you want to leave this group?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Salir', 'Leave'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await firestoreService.removeMemberFromGroup(
          groupId: group.id,
          memberEmail: currentUserEmail,
        );
        if (!mounted) return;
        Navigator.of(context).pop(); // Go back to groups screen
        messenger.showSnackBar(
          SnackBar(content: Text(tr('Saliste del grupo.', 'Left the group.'))),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('${tr('Error al salir', 'Error leaving')}: $e')),
        );
      }
    }
  }

  Future<void> addMember(GroupModel group) async {
    final email = memberController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Ingresa un correo para añadir.', 'Enter an email to add.'),
          ),
        ),
      );
      return;
    }

    if (group.members.contains(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'El miembro ya está en el grupo.',
              'The member is already in the group.',
            ),
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    try {
      final currentUserEmail =
          FirebaseAuth.instance.currentUser?.email ?? group.createdBy;
      await firestoreService.sendGroupInvitation(
        groupId: widget.group.id,
        fromEmail: currentUserEmail,
        toEmail: email,
        groupName: group.name,
      );
      if (!mounted) return;
      memberController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Invitación enviada exitosamente.',
              'Invitation sent successfully.',
            ),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr('Error al invitar', 'Error inviting')}: $e'),
        ),
      );
    }
  }

  Future<void> removeMember(String email, GroupModel group) async {
    if (group.members.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'El grupo debe tener al menos un miembro.',
              'The group must have at least one member.',
            ),
          ),
        ),
      );
      return;
    }

    try {
      await firestoreService.removeMemberFromGroup(
        groupId: widget.group.id,
        memberEmail: email,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('Error al eliminar miembro', 'Error removing member')}: $e',
          ),
        ),
      );
    }
  }

  Map<String, double> calculateBalances(
    List<Expense> expenses,
    List<String> members,
  ) {
    final normalizedMembers = members
        .map((m) => m.trim().toLowerCase())
        .toList();
    final allInvolved = <String>{...normalizedMembers};
    for (final e in expenses) {
      allInvolved.add(e.paidBy.trim().toLowerCase());
      if (e.paidTo != null) allInvolved.add(e.paidTo!.trim().toLowerCase());
      allInvolved.addAll(e.involvedMembers.map((m) => m.trim().toLowerCase()));
    }

    final totals = {for (var person in allInvolved) person: 0.0};

    for (final expense in expenses) {
      final pBy = expense.paidBy.trim().toLowerCase();
      final pTo = expense.paidTo?.trim().toLowerCase();
      if (expense.type == 'payment') {
        totals[pBy] = (totals[pBy] ?? 0.0) + expense.amount;
        if (pTo != null) {
          totals[pTo] = (totals[pTo] ?? 0.0) - expense.amount;
        }
      } else {
        totals[pBy] = (totals[pBy] ?? 0.0) + expense.amount;
        final involved = expense.involvedMembers.isNotEmpty
            ? expense.involvedMembers
                  .map((m) => m.trim().toLowerCase())
                  .toList()
            : normalizedMembers;
        if (involved.isNotEmpty) {
          final share = expense.amount / involved.length;
          for (final person in involved) {
            totals[person] = (totals[person] ?? 0.0) - share;
          }
        }
      }
    }

    return totals;
  }

  List<Settlement> buildSettlements(Map<String, double> balances) {
    final debtors = <MapEntry<String, double>>[];
    final creditors = <MapEntry<String, double>>[];

    for (final entry in balances.entries) {
      if (entry.value < -0.01) {
        debtors.add(MapEntry(entry.key, -entry.value));
      } else if (entry.value > 0.01) {
        creditors.add(MapEntry(entry.key, entry.value));
      }
    }

    final settlements = <Settlement>[];
    var i = 0;
    var j = 0;

    while (i < debtors.length && j < creditors.length) {
      final debtor = debtors[i];
      final creditor = creditors[j];
      final amount = debtor.value < creditor.value
          ? debtor.value
          : creditor.value;

      settlements.add(Settlement(debtor.key, creditor.key, amount));

      debtors[i] = MapEntry(debtor.key, debtor.value - amount);
      creditors[j] = MapEntry(creditor.key, creditor.value - amount);

      if (debtors[i].value <= 0.01) {
        i++;
      }
      if (creditors[j].value <= 0.01) {
        j++;
      }
    }

    return settlements;
  }

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();
    memberController.dispose();
    super.dispose();
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Servicio':
        return Icons.build_outlined;
      case 'Actividad':
        return Icons.local_activity_outlined;
      default:
        return Icons.shopping_bag_outlined;
    }
  }

  void _showManageMembersSheet(BuildContext context, GroupModel initialGroup) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StreamBuilder<GroupModel?>(
          stream: _groupStream,
          builder: (context, groupSnap) {
            final group = groupSnap.data ?? initialGroup;
            final isAdmin = group.admins.any(
              (admin) => admin.trim().toLowerCase() == currentUserEmail.trim().toLowerCase(),
            );

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Gestionar Miembros', 'Manage Members'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${tr('Código', 'Code')}: ${group.code}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: group.code));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(tr('Código copiado.', 'Code copied.')),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton.filled(
                        icon: const Icon(Icons.share),
                        onPressed: () {
                          final link = 'smartbudget://join?code=${group.code}';
                          Share.share(
                            '${tr('¡Únete a mi grupo', 'Join my group')} "${group.name}" ${tr('en Smart Budget!\n👉 Ingresa directo con este enlace:\n', 'on Smart Budget!\n👉 Enter directly with this link:\n')}$link\n\n'
                            '${tr('O usa el código de invitación: ', 'Or use the invitation code: ')}${group.code}',
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    tr('Lista de Miembros', 'Members List'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.35,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: group.members.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (ctx, index) {
                        final m = group.members[index];
                        final isMemberAdmin = group.admins.any(
                          (admin) => admin.trim().toLowerCase() == m.trim().toLowerCase(),
                        );
                        final isCreator = m.trim().toLowerCase() == group.createdBy.trim().toLowerCase();
                        final isCurrentUserCreator = group.createdBy.trim().toLowerCase() == currentUserEmail.trim().toLowerCase();

                        return FutureBuilder<DocumentSnapshot?>(
                          future: firestoreService.getUserProfileByEmail(m),
                          builder: (context, userSnap) {
                            final userData = userSnap.data?.data() as Map<String, dynamic>?;
                            final photoUrl = userData?['photoUrl'] as String?;
                            final name = _getMemberName(m);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 20,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                backgroundImage: photoUrl != null
                                    ? MemoryImage(base64Decode(photoUrl))
                                    : null,
                                child: photoUrl == null
                                    ? Text(
                                        name.substring(0, 1).toUpperCase(),
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                isCreator
                                    ? tr('Creador', 'Creator')
                                    : isMemberAdmin
                                        ? tr('Administrador', 'Administrator')
                                        : tr('Miembro', 'Member'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isCreator
                                      ? Colors.purple
                                      : isMemberAdmin
                                          ? Colors.orange.shade800
                                          : Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isAdmin && !isCreator) ...[
                                    Switch(
                                      value: isMemberAdmin,
                                      activeThumbColor: Colors.orange,
                                      activeTrackColor: Colors.orange.shade800.withAlpha(120),
                                      onChanged: isCurrentUserCreator
                                          ? (val) async {
                                              await firestoreService.toggleAdminStatus(
                                                groupId: group.id,
                                                memberEmail: m,
                                                makeAdmin: val,
                                              );
                                            }
                                          : null,
                                    ),
                                    const SizedBox(width: 4),
                                    if (isCurrentUserCreator || !isMemberAdmin)
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete_outline,
                                          color: Theme.of(context).colorScheme.error,
                                        ),
                                        onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (confirmCtx) => AlertDialog(
                                            title: Text(tr('Eliminar Miembro', 'Remove Member')),
                                            content: Text(
                                              '${tr('¿Estás seguro de que deseas eliminar a', 'Are you sure you want to remove')} $name ${tr('del grupo?', 'from the group?')}',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(confirmCtx, false),
                                                child: Text(tr('Cancelar', 'Cancel')),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Theme.of(context).colorScheme.error,
                                                ),
                                                onPressed: () => Navigator.pop(confirmCtx, true),
                                                child: Text(
                                                  tr('Eliminar', 'Remove'),
                                                  style: const TextStyle(color: Colors.white),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true) {
                                          await removeMember(m, group);
                                        }
                                      },
                                    ),
                                  ] else if (isCreator) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(right: 12.0),
                                      child: Icon(Icons.star, color: Colors.purple.shade400, size: 20),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: memberController,
                    decoration: InputDecoration(
                      labelText: tr('Invitar por correo', 'Invite by email'),
                      prefixIcon: const Icon(Icons.person_add_outlined),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () {
                          addMember(group);
                          Navigator.pop(ctx);
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showExportOptionsDialog(GroupModel group, List<Expense> expenses, List<PaymentRequest> requests) {
    bool includeGeneral = true;
    bool includeBalances = true;
    bool includePaid = true;
    bool includeUnpaid = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('Exportar Reporte PDF', 'Export PDF Report')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(
                    'Selecciona las secciones que deseas incluir en el reporte:',
                    'Select the sections you want to include in the report:',
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: includeGeneral,
                  title: Text(tr('Balance General', 'General Balance')),
                  subtitle: Text(tr('Resumen total, presupuesto y deudas globales.', 'Total summary, budget and global debts.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeGeneral = val);
                  },
                ),
                CheckboxListTile(
                  value: includeBalances,
                  title: Text(tr('Saldos e Integrantes', 'Balances & Members')),
                  subtitle: Text(tr('Balances netos de cada persona y liquidaciones sugeridas.', 'Net balances of each person and suggested settlements.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeBalances = val);
                  },
                ),
                CheckboxListTile(
                  value: includePaid,
                  title: Text(tr('Personas que ya pagaron', 'People who have paid')),
                  subtitle: Text(tr('Listado de pagos reales y confirmaciones registradas.', 'List of actual payments and registered confirmations.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includePaid = val);
                  },
                ),
                CheckboxListTile(
                  value: includeUnpaid,
                  title: Text(tr('Personas con pagos pendientes', 'People with pending payments')),
                  subtitle: Text(tr('Listado de solicitudes de cobro aún no confirmadas.', 'List of collection requests not yet confirmed.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeUnpaid = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancelar', 'Cancel')),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(tr('Generar PDF', 'Generate PDF')),
              onPressed: () {
                Navigator.pop(ctx);
                _generateGroupHtmlReport(
                  group: group,
                  expenses: expenses,
                  requests: requests,
                  includeGeneral: includeGeneral,
                  includeBalances: includeBalances,
                  includePaid: includePaid,
                  includeUnpaid: includeUnpaid,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _generateGroupHtmlReport({
    required GroupModel group,
    required List<Expense> expenses,
    required List<PaymentRequest> requests,
    required bool includeGeneral,
    required bool includeBalances,
    required bool includePaid,
    required bool includeUnpaid,
  }) {
    final buffer = StringBuffer();
    final timeStr = DateTime.now().toLocal().toString().split('.')[0];
    final groupName = group.name;

    buffer.write('<html><head><meta charset="UTF-8"><title>Reporte - $groupName</title>');
    buffer.write('<style>');
    buffer.write('body { font-family: system-ui, -apple-system, sans-serif; padding: 40px; color: #1e293b; background-color: #ffffff; line-height: 1.5; }');
    buffer.write('.header { border-bottom: 3px solid #003289; padding-bottom: 20px; margin-bottom: 30px; }');
    buffer.write('h1 { color: #003289; margin: 0 0 10px 0; font-size: 28px; font-weight: 800; }');
    buffer.write('h2 { color: #0f172a; border-bottom: 1.5px solid #cbd5e1; padding-bottom: 6px; margin: 30px 0 15px 0; font-size: 20px; }');
    buffer.write('.meta { color: #64748b; font-size: 14px; margin-bottom: 5px; }');
    buffer.write('table { width: 100%; border-collapse: collapse; margin-top: 15px; margin-bottom: 25px; }');
    buffer.write('th, td { border: 1px solid #e2e8f0; padding: 12px 16px; text-align: left; font-size: 14px; }');
    buffer.write('th { background-color: #003289; color: #ffffff; font-weight: 600; }');
    buffer.write('tr:nth-child(even) { background-color: #f8fafc; }');
    buffer.write('.badge { display: inline-block; padding: 2px 8px; font-size: 12px; font-weight: 600; border-radius: 4px; }');
    buffer.write('.badge-success { background-color: #dcfce7; color: #15803d; }');
    buffer.write('.badge-warning { background-color: #fef9c3; color: #a16207; }');
    buffer.write('.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 25px; }');
    buffer.write('.card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; background-color: #f8fafc; }');
    buffer.write('.card-title { font-weight: 600; color: #475569; font-size: 12px; text-transform: uppercase; margin-bottom: 6px; }');
    buffer.write('.card-value { font-size: 20px; font-weight: 700; color: #003289; }');
    buffer.write('</style></head><body>');

    // Header
    buffer.write('<div class="header">');
    buffer.write('<h1>SmartBudget - Reporte de Grupo</h1>');
    buffer.write('<div class="meta"><strong>Grupo:</strong> $groupName</div>');
    buffer.write('<div class="meta"><strong>Código:</strong> ${group.code}</div>');
    buffer.write('<div class="meta"><strong>Fecha de reporte:</strong> $timeStr</div>');
    buffer.write('</div>');

    // General Balance
    if (includeGeneral) {
      final totalG = expenses.where((e) => e.type != 'payment').fold<double>(0, (s, e) => s + e.amount);
      final budget = group.initialBudget ?? 0.0;
      final remaining = budget - totalG;

      buffer.write('<h2>Balance General</h2>');
      buffer.write('<div class="grid">');
      buffer.write('<div class="card"><div class="card-title">Gasto Total</div><div class="card-value">Q${totalG.toStringAsFixed(2)}</div></div>');
      if (budget > 0) {
        buffer.write('<div class="card"><div class="card-title">Presupuesto Inicial</div><div class="card-value">Q${budget.toStringAsFixed(2)}</div></div>');
        buffer.write('<div class="card"><div class="card-title">Presupuesto Restante</div><div class="card-value">Q${remaining.toStringAsFixed(2)}</div></div>');
      }
      buffer.write('<div class="card"><div class="card-title">Miembros Activos</div><div class="card-value">${group.members.length}</div></div>');
      buffer.write('</div>');
    }

    // Saldos y Balances
    if (includeBalances) {
      buffer.write('<h2>Saldos y Cuentas de Integrantes</h2>');
      buffer.write('<table><thead><tr><th>Miembro</th><th>Balance Neto</th><th>Estado</th></tr></thead><tbody>');
      final balances = calculateBalances(expenses, group.members);
      for (final member in group.members) {
        final name = _getMemberName(member);
        final bal = balances[member.trim().toLowerCase()] ?? 0.0;
        String statusText;
        String badgeClass;
        if (bal > 0.01) {
          statusText = 'A favor: +Q${bal.toStringAsFixed(2)}';
          badgeClass = 'badge badge-success';
        } else if (bal < -0.01) {
          statusText = 'Debe: Q${(-bal).toStringAsFixed(2)}';
          badgeClass = 'badge badge-warning';
        } else {
          statusText = 'Al día (Q0.00)';
          badgeClass = 'badge';
        }
        buffer.write('<tr><td><strong>$name</strong> ($member)</td><td>Q${bal.toStringAsFixed(2)}</td><td><span class="$badgeClass">$statusText</span></td></tr>');
      }
      buffer.write('</tbody></table>');

      // Suggested Liquidations
      final settlements = buildSettlements(balances);
      buffer.write('<h3>Liquidaciones Sugeridas</h3>');
      if (settlements.isEmpty) {
        buffer.write('<p><em>No hay liquidaciones pendientes. Todas las cuentas están saldadas.</em></p>');
      } else {
        buffer.write('<table><thead><tr><th>Deudor</th><th>Paga a</th><th>Monto</th></tr></thead><tbody>');
        for (final s in settlements) {
          final debtorName = _getMemberName(s.debtor);
          final creditorName = _getMemberName(s.creditor);
          buffer.write('<tr><td>$debtorName</td><td>$creditorName</td><td><strong>Q${s.amount.toStringAsFixed(2)}</strong></td></tr>');
        }
        buffer.write('</tbody></table>');
      }
    }

    // People who have paid (payments already confirmed)
    if (includePaid) {
      buffer.write('<h2>Integrantes que han Pagado (Pagos Confirmados)</h2>');
      final paidExpenses = expenses.where((e) => e.type == 'payment').toList();
      if (paidExpenses.isEmpty) {
        buffer.write('<p><em>No se han registrado pagos confirmados todavía.</em></p>');
      } else {
        buffer.write('<table><thead><tr><th>Quién Pagó</th><th>A Quién</th><th>Monto</th><th>Categoría</th><th>Fecha</th></tr></thead><tbody>');
        for (final p in paidExpenses) {
          final payerName = _getMemberName(p.paidBy);
          final receiverName = _getMemberName(p.paidTo ?? '');
          final dateStr = '${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}';
          buffer.write('<tr><td>$payerName</td><td>$receiverName</td><td><strong>Q${p.amount.toStringAsFixed(2)}</strong></td><td>${translateCategory(p.category)}</td><td>$dateStr</td></tr>');
        }
        buffer.write('</tbody></table>');
      }
    }

    // People who haven't paid (pending payment requests)
    if (includeUnpaid) {
      buffer.write('<h2>Integrantes con Pagos Pendientes (Solicitudes Activas)</h2>');
      final pendingReqs = requests.where((r) => r.status == 'pendiente' || r.status == 'pendiente_boleta').toList();
      if (pendingReqs.isEmpty) {
        buffer.write('<p><em>No hay solicitudes de pago pendientes en este grupo.</em></p>');
      } else {
        buffer.write('<table><thead><tr><th>Deudor</th><th>Cobrador</th><th>Monto</th><th>Concepto</th><th>Fecha Límite/Creación</th><th>Estado</th></tr></thead><tbody>');
        for (final r in pendingReqs) {
          final debtorName = _getMemberName(r.fromEmail);
          final creditorName = _getMemberName(r.toEmail);
          final dateStr = '${r.date.day}/${r.date.month}/${r.date.year}';
          final concept = r.reference ?? 'Gasto general';
          final statusLabel = r.status == 'pendiente_boleta' ? 'Pendiente boleta' : 'En revisión';
          buffer.write('<tr><td>$debtorName</td><td>$creditorName</td><td><strong>Q${r.amount.toStringAsFixed(2)}</strong></td><td>$concept</td><td>$dateStr</td><td><span class="badge badge-warning">$statusLabel</span></td></tr>');
        }
        buffer.write('</tbody></table>');
      }
    }

    buffer.write('<script>window.onload = function() { window.print(); }</script>');
    buffer.write('</body></html>');

    printHtmlReport(
      title: 'Reporte_Grupo_${groupName.replaceAll(' ', '_')}',
      htmlContent: buffer.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    return DefaultTabController(
      length: 3,
      child: StreamBuilder<GroupModel?>(
        stream: _groupStream,
        builder: (context, groupSnapshot) {
          final group = groupSnapshot.data ?? widget.group;
          final isAdmin = group.admins.any(
            (admin) =>
                admin.trim().toLowerCase() ==
                currentUserEmail.trim().toLowerCase(),
          );

          return StreamBuilder<List<Expense>>(
            stream: _expensesStream,
            builder: (context, expenseSnapshot) {
              final expenses = expenseSnapshot.data ?? [];
              final total = expenses
                  .where((e) => e.type != 'payment')
                  .fold<double>(0, (s, e) => s + e.amount);
              final balances = calculateBalances(expenses, group.members);
              final settlements = buildSettlements(balances);

              return StreamBuilder<List<PaymentRequest>>(
                stream: _requestsStream,
                builder: (context, reqSnap) {
                  final requests = reqSnap.data ?? [];

                  return Scaffold(
                    backgroundColor: colorScheme.surface,
                    appBar: AppBar(
                      backgroundColor: colorScheme.surface,
                      surfaceTintColor: colorScheme.surface,
                      iconTheme: IconThemeData(color: colorScheme.onSurface),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      title: Row(
                        children: [
                          GroupAvatar(group: group, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                group.name,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        if (isAdmin)
                          IconButton(
                            icon: const Icon(Icons.download_outlined),
                            tooltip: tr('Exportar Reporte', 'Export Report'),
                            onPressed: () => _showExportOptionsDialog(group, expenses, requests),
                          ),
                        IconButton(
                          icon: const Icon(Icons.group_outlined),
                          tooltip: tr('Miembros', 'Members'),
                          onPressed: () =>
                              _showManageMembersSheet(context, group),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditGroupDialog(group);
                            } else if (value == 'copy') {
                              Clipboard.setData(ClipboardData(text: group.code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(tr('Código copiado.', 'Code copied.'))),
                              );
                            } else if (value == 'leave') {
                              _confirmLeaveGroup(group);
                            } else if (value == 'delete') {
                              _confirmDeleteGroup(group);
                            }
                          },
                          itemBuilder: (ctx) {
                            final isCreator = currentUserEmail.trim().toLowerCase() == group.createdBy.trim().toLowerCase();
                            return [
                              if (isAdmin)
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_outlined),
                                      const SizedBox(width: 12),
                                      Text(tr('Editar grupo', 'Edit group')),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'copy',
                                child: Row(
                                  children: [
                                    const Icon(Icons.copy),
                                    const SizedBox(width: 12),
                                    Text(tr('Copiar código', 'Copy code')),
                                  ],
                                ),
                              ),
                              if (!isCreator)
                                PopupMenuItem(
                                  value: 'leave',
                                  child: Row(
                                    children: [
                                      Icon(Icons.exit_to_app, color: Theme.of(context).colorScheme.error),
                                      const SizedBox(width: 12),
                                      Text(
                                        tr('Salir del grupo', 'Leave group'),
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isCreator)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_forever_outlined,
                                        color: Theme.of(context).colorScheme.error,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        tr('Eliminar grupo', 'Delete group'),
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                    ],
                                  ),
                                ),
                            ];
                          },
                        ),
                      ],
                      bottom: TabBar(
                        tabs: [
                          Tab(text: tr('Resumen', 'Summary')),
                          Tab(text: tr('Historial', 'History')),
                          Tab(text: tr('Estadísticas', 'Statistics')),
                        ],
                      ),
                    ),
                    body: TabBarView(
                      children: [
                        // Tab 1: Resumen
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isAdmin)
                                _PendingJoinRequestsList(
                                  service: firestoreService,
                                  groupId: group.id,
                                  groupName: group.name,
                                  currentEmail: currentUserEmail,
                                ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.primary.withAlpha(40),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          group.name,
                                          style: textTheme.headlineSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    tr(
                                                      'Gasto Total del Grupo',
                                                      'Total Group Expense',
                                                    ),
                                                    style: textTheme.bodyMedium?.copyWith(
                                                      color: colorScheme
                                                          .onPrimaryContainer
                                                          .withAlpha(180),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Q${total.toStringAsFixed(2)}',
                                                    style: textTheme.titleLarge?.copyWith(
                                                      color: colorScheme.onPrimaryContainer,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (group.initialBudget != null) ...[
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      tr(
                                                        'Presupuesto Restante',
                                                        'Remaining Budget',
                                                      ),
                                                      style: textTheme.bodyMedium?.copyWith(
                                                        color: colorScheme
                                                            .onPrimaryContainer
                                                            .withAlpha(180),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'Q${(group.initialBudget! - total).toStringAsFixed(2)}',
                                                      style: textTheme.titleLarge?.copyWith(
                                                        color: (group.initialBudget! - total) < 0
                                                            ? Colors.redAccent.shade100
                                                            : colorScheme.onPrimaryContainer,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${tr('Límite', 'Limit')}: Q${group.initialBudget!.toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: colorScheme.onPrimaryContainer.withAlpha(140),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '${tr('Creado por', 'Created by')} ${_getMemberName(group.createdBy)}',
                                          style: textTheme.bodySmall?.copyWith(
                                            color: colorScheme
                                                .onPrimaryContainer
                                                .withAlpha(160),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Positioned(
                                      right: -20,
                                      top: -20,
                                      child: Container(
                                        width: 120,
                                        height: 120,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: colorScheme.primary.withAlpha(
                                            30,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    tr('Miembros y Balances', 'Members and Balances'),
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    '${group.members.length} ${tr('miembros', 'members')}',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Group balance visual summary (Mini Card representing the general balance distribution)
                              Builder(
                                builder: (context) {
                                  // Calculate how many members are positive, negative, balanced
                                  int inFavorCount = 0;
                                  int owesCount = 0;
                                  double totalPositive = 0.0;
                                  double totalNegative = 0.0;

                                  for (final m in group.members) {
                                    final bal = balances[m.trim().toLowerCase()] ?? 0.0;
                                    if (bal > 0.01) {
                                      inFavorCount++;
                                      totalPositive += bal;
                                    } else if (bal < -0.01) {
                                      owesCount++;
                                      totalNegative += bal.abs();
                                    }
                                  }

                                  final totalBalanceSum = totalPositive + totalNegative;
                                  final inFavorPct = totalBalanceSum > 0 ? (totalPositive / totalBalanceSum) : 0.5;

                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest.withAlpha(50),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            Column(
                                              children: [
                                                Text(
                                                  tr('A favor', 'Lent'),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.green.shade700,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Q${totalPositive.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green.shade700,
                                                  ),
                                                ),
                                                Text(
                                                  '($inFavorCount ${tr('miem.', 'memb.')})',
                                                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                                                ),
                                              ],
                                            ),
                                            // Mini circular indicator
                                            Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                SizedBox(
                                                  width: 54,
                                                  height: 54,
                                                  child: CircularProgressIndicator(
                                                    value: inFavorPct,
                                                    strokeWidth: 6,
                                                    backgroundColor: colorScheme.error.withAlpha(50),
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.pie_chart_outline,
                                                  color: colorScheme.onSurfaceVariant,
                                                  size: 20,
                                                ),
                                              ],
                                            ),
                                            Column(
                                              children: [
                                                Text(
                                                  tr('Deben', 'Owe'),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: colorScheme.error,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Q${totalNegative.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.error,
                                                  ),
                                                ),
                                                Text(
                                                  '($owesCount ${tr('miem.', 'memb.')})',
                                                  style: TextStyle(fontSize: 10, color: colorScheme.outline),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),

                              // Improved members list mimicking Friends Screen list with balance details
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: group.members.length,
                                separatorBuilder: (_, index) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final member = group.members[index];
                                  final isCurrentUser = member.trim().toLowerCase() == currentUserEmail.trim().toLowerCase();
                                  final name = _getMemberName(member);
                                  
                                  final bal = balances[member.trim().toLowerCase()] ?? 0.0;
                                  final iOwe = bal < -0.01;
                                  final theyOwe = bal > 0.01;

                                  final statusColor = iOwe
                                      ? colorScheme.error
                                      : theyOwe
                                          ? Colors.green.shade700
                                          : colorScheme.outline;

                                  final s = settlements.firstWhere(
                                    (s) =>
                                        s.creditor.trim().toLowerCase() ==
                                            currentUserEmail.trim().toLowerCase() &&
                                        s.debtor.trim().toLowerCase() ==
                                            member.trim().toLowerCase(),
                                    orElse: () => Settlement('', '', 0),
                                  );

                                  return FutureBuilder<DocumentSnapshot?>(
                                    future: firestoreService.getUserProfileByEmail(member),
                                    builder: (context, userSnap) {
                                      final userData = userSnap.data?.data() as Map<String, dynamic>?;
                                      final photoUrl = userData?['photoUrl'] as String?;

                                      return Card(
                                        elevation: 0,
                                        margin: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                          side: BorderSide(
                                            color: colorScheme.outlineVariant.withAlpha(100),
                                          ),
                                        ),
                                        child: ListTile(
                                          onTap: () => _showMemberProfile(
                                            member,
                                            group,
                                            isAdmin,
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          leading: CircleAvatar(
                                            radius: 24,
                                            backgroundColor: colorScheme.primaryContainer,
                                            backgroundImage: photoUrl != null
                                                ? MemoryImage(base64Decode(photoUrl))
                                                : null,
                                            child: photoUrl == null
                                                ? Text(
                                                    name.substring(0, 1).toUpperCase(),
                                                    style: TextStyle(
                                                      color: colorScheme.onPrimaryContainer,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                          title: Text(
                                            '$name${isCurrentUser ? ' (Tú)' : ''}',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          subtitle: Text(
                                            member,
                                            style: textTheme.bodySmall?.copyWith(
                                              color: colorScheme.outline,
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    iOwe
                                                        ? tr('Debe', 'Owes')
                                                        : theyOwe
                                                            ? tr('A favor', 'Lent')
                                                            : tr('Equilibrado', 'Balanced'),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w500,
                                                      color: colorScheme.outline,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Q${bal.abs().toStringAsFixed(2)}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: statusColor,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (s.amount > 0 && !isCurrentUser) ...[
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.notifications_active_outlined,
                                                    color: colorScheme.primary,
                                                    size: 20,
                                                  ),
                                                  onPressed: () async {
                                                    await firestoreService.sendPaymentReminder(
                                                      groupId: group.id,
                                                      fromEmail: member,
                                                      toEmail: currentUserEmail,
                                                      amount: s.amount,
                                                    );
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            '${tr('Recordatorio enviado a', 'Reminder sent to')} $name',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              if (requests.isNotEmpty) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.hourglass_top_rounded,
                                          size: 18,
                                          color: Colors.orange.shade700,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          tr(
                                            'Solicitudes Pendientes',
                                            'Pending Requests',
                                          ),
                                          style: textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange.shade700,
                                              ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade700,
                                            borderRadius: BorderRadius.circular(
                                              99,
                                            ),
                                          ),
                                          child: Text(
                                            '${requests.length}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    ...requests.map((req) {
                                      final isIncoming =
                                          req.toEmail.trim().toLowerCase() ==
                                          currentUserEmail.trim().toLowerCase();
                                      final isOutgoing =
                                          req.fromEmail.trim().toLowerCase() ==
                                          currentUserEmail.trim().toLowerCase();
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withAlpha(15),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.withAlpha(80),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Icon(
                                                            Icons.send_outlined,
                                                            size: 16,
                                                            color: Colors
                                                                .orange
                                                                .shade700,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              req.status ==
                                                                      'pendiente_boleta'
                                                                  ? (isIncoming
                                                                        ? '${_getMemberName(req.fromEmail)} ${tr('debe pagarte', 'owes you')} Q${req.amount.toStringAsFixed(2)}'
                                                                        : '${tr('Debes pagar', 'You must pay')} Q${req.amount.toStringAsFixed(2)} ${tr('a', 'to')} ${_getMemberName(req.toEmail)}')
                                                                  : (isIncoming
                                                                        ? '${_getMemberName(req.fromEmail)} ${tr('quiere pagarte', 'wants to pay you')} Q${req.amount.toStringAsFixed(2)}'
                                                                        : '${tr('Enviaste', 'You sent')} Q${req.amount.toStringAsFixed(2)} ${tr('a', 'to')} ${_getMemberName(req.toEmail)}'),
                                                              style: textTheme
                                                                  .bodyMedium
                                                                  ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 4,
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: colorScheme
                                                                  .primaryContainer
                                                                  .withAlpha(
                                                                    80,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    8,
                                                                  ),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Icon(
                                                                  _getRubroIcon(
                                                                    req.rubro,
                                                                  ),
                                                                  size: 12,
                                                                  color: colorScheme
                                                                      .onPrimaryContainer,
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  translateCategory(
                                                                    req.rubro,
                                                                  ),
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: colorScheme
                                                                        .onPrimaryContainer,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (req.reference !=
                                                              null &&
                                                          req
                                                              .reference!
                                                              .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 8,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: colorScheme
                                                                .surfaceContainerLow,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .description_outlined,
                                                                size: 14,
                                                                color: colorScheme
                                                                    .onSurfaceVariant,
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  req.reference!,
                                                                  style: textTheme
                                                                      .bodyMedium
                                                                      ?.copyWith(
                                                                        color: colorScheme
                                                                            .onSurfaceVariant,
                                                                        fontWeight:
                                                                            FontWeight.w500,
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
                                                          Icon(
                                                            Icons
                                                                .calendar_today_outlined,
                                                            size: 11,
                                                            color: colorScheme
                                                                .outline,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '${tr('Fecha de pago', 'Payment date')}: ${req.date.day}/${req.date.month}/${req.date.year}',
                                                            style: textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                  color: colorScheme
                                                                      .outline,
                                                                  fontSize: 11,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (req.imageUrl != null &&
                                                    req
                                                        .imageUrl!
                                                        .isNotEmpty) ...[
                                                  const SizedBox(width: 12),
                                                  GestureDetector(
                                                    onTap: () =>
                                                        _showReceiptDialog(
                                                          req.imageUrl!,
                                                        ),
                                                    child: Container(
                                                      width: 50,
                                                      height: 50,
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.orange
                                                              .withAlpha(120),
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        child: Stack(
                                                          children: [
                                                            Positioned.fill(
                                                              child: Image.memory(
                                                                base64Decode(
                                                                  req.imageUrl!,
                                                                ),
                                                                fit: BoxFit
                                                                    .cover,
                                                              ),
                                                            ),
                                                            Positioned(
                                                              bottom: 2,
                                                              right: 2,
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.all(
                                                                      2,
                                                                    ),
                                                                decoration: const BoxDecoration(
                                                                  color: Colors
                                                                      .black54,
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                                child: const Icon(
                                                                  Icons.zoom_in,
                                                                  size: 10,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            if (isIncoming) ...[
                                              if (req.status ==
                                                  'pendiente_boleta') ...[
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                  child: Text(
                                                    '${tr('Esperando que', 'Waiting for')} ${_getMemberName(req.fromEmail)} ${tr('suba la boleta', 'to upload the receipt')}',
                                                    style: textTheme.bodySmall
                                                        ?.copyWith(
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                  ),
                                                ),
                                              ] else ...[
                                                const SizedBox(height: 10),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: OutlinedButton.icon(
                                                        icon: const Icon(
                                                          Icons.close,
                                                          size: 16,
                                                        ),
                                                        label: Text(
                                                          tr(
                                                            'Rechazar',
                                                            'Reject',
                                                          ),
                                                        ),
                                                        style:
                                                            OutlinedButton.styleFrom(
                                                              foregroundColor:
                                                                  colorScheme
                                                                      .error,
                                                              side: BorderSide(
                                                                color:
                                                                    colorScheme
                                                                        .error,
                                                              ),
                                                              minimumSize:
                                                                  const Size(
                                                                    0,
                                                                    36,
                                                                  ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                        onPressed: () async {
                                                          await firestoreService
                                                              .rejectPaymentRequest(
                                                                groupId: widget
                                                                    .group
                                                                    .id,
                                                                requestId:
                                                                    req.id,
                                                                request: req,
                                                              );
                                                        },
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: FilledButton.icon(
                                                        icon: const Icon(
                                                          Icons.check,
                                                          size: 16,
                                                        ),
                                                        label: Text(
                                                          tr(
                                                            'Confirmar',
                                                            'Confirm',
                                                          ),
                                                        ),
                                                        style:
                                                            FilledButton.styleFrom(
                                                              backgroundColor:
                                                                  Colors
                                                                      .green
                                                                      .shade600,
                                                              minimumSize:
                                                                  const Size(
                                                                    0,
                                                                    36,
                                                                  ),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                        onPressed: () async {
                                                          final messenger =
                                                              ScaffoldMessenger.of(
                                                                context,
                                                              );
                                                          await firestoreService
                                                              .confirmPaymentRequest(
                                                                groupId: widget
                                                                    .group
                                                                    .id,
                                                                requestId:
                                                                    req.id,
                                                                request: req,
                                                              );
                                                          messenger.showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                tr(
                                                                  'Pago confirmado y balance actualizado.',
                                                                  'Payment confirmed and balance updated.',
                                                                ),
                                                              ),
                                                              backgroundColor:
                                                                  Colors.green,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ] else if (isOutgoing) ...[
                                              if (req.status ==
                                                  'pendiente_boleta') ...[
                                                const SizedBox(height: 10),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: FilledButton.icon(
                                                    icon: const Icon(
                                                      Icons.upload_file,
                                                      size: 16,
                                                    ),
                                                    label: Text(
                                                      tr(
                                                        'Subir Boleta de Pago',
                                                        'Upload Payment Receipt',
                                                      ),
                                                    ),
                                                    style:
                                                        FilledButton.styleFrom(
                                                          backgroundColor:
                                                              colorScheme
                                                                  .primary,
                                                          minimumSize:
                                                              const Size(0, 36),
                                                          padding:
                                                              EdgeInsets.zero,
                                                        ),
                                                    onPressed: () =>
                                                        _pickAndSubmitBoleta(
                                                          req,
                                                        ),
                                                  ),
                                                ),
                                              ] else ...[
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                  child: Text(
                                                    '${tr('Esperando confirmación de', 'Waiting for confirmation from')} ${_getMemberName(req.toEmail)}',
                                                    style: textTheme.bodySmall
                                                        ?.copyWith(
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ],
                                        ),
                                      );
                                    }),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ],

                            ],
                          ),
                        ),

                        // Tab 2: Historial
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    tr('Gastos Recientes', 'Recent Expenses'),
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (expenseSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  expenses.isEmpty)
                                const Center(child: CircularProgressIndicator())
                              else if (expenses.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.receipt_long_outlined,
                                        size: 48,
                                        color: colorScheme.outline,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        tr(
                                          'No hay gastos aún',
                                          'No expenses yet',
                                        ),
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...expenses.map((expense) {
                                  final date = expense.createdAt;
                                  final isPayment = expense.type == 'payment';
                                  final iconColor = isPayment
                                      ? Colors.green.shade600
                                      : colorScheme.primary;
                                  final bgColor = isPayment
                                      ? Colors.green.withAlpha(20)
                                      : colorScheme.primaryContainer.withAlpha(
                                          80,
                                        );

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(6),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () =>
                                          _showExpenseCommentsSheet(expense),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                        leading: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            isPayment
                                                ? Icons.swap_horiz_rounded
                                                : _categoryIcon(
                                                    expense.category,
                                                  ),
                                            color: iconColor,
                                            size: 22,
                                          ),
                                        ),
                                        title: Text(
                                          expense.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isPayment
                                                  ? '${_getMemberName(expense.paidBy)} → ${_getMemberName(expense.paidTo ?? "")}'
                                                  : '${tr('Pagado por', 'Paid by')} ${_getMemberName(expense.paidBy)}',
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 1,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: colorScheme
                                                        .surfaceContainerHighest,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    translateCategory(
                                                      expense.category,
                                                    ).toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${date.day}/${date.month}/${date.year}',
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            colorScheme.outline,
                                                        fontSize: 10,
                                                      ),
                                                ),
                                                if (expense.dueDate !=
                                                    null) ...[
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    Icons.event,
                                                    size: 10,
                                                    color:
                                                        expense.dueDate!
                                                            .isBefore(
                                                              DateTime.now(),
                                                            )
                                                        ? Colors.red
                                                        : colorScheme.outline,
                                                  ),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${tr('Límite', 'Deadline')}: ${expense.dueDate!.day}/${expense.dueDate!.month}',
                                                    style: textTheme.bodySmall
                                                        ?.copyWith(
                                                          color:
                                                              expense.dueDate!
                                                                  .isBefore(
                                                                    DateTime.now(),
                                                                  )
                                                              ? Colors.red
                                                              : colorScheme
                                                                    .outline,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              expense.dueDate!
                                                                  .isBefore(
                                                                    DateTime.now(),
                                                                  )
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (expense.imageUrl != null &&
                                                expense
                                                    .imageUrl!
                                                    .isNotEmpty) ...[
                                              GestureDetector(
                                                onTap: () => _showReceiptDialog(
                                                  expense.imageUrl!,
                                                ),
                                                child: Container(
                                                  width: 36,
                                                  height: 36,
                                                  margin: const EdgeInsets.only(
                                                    right: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.green
                                                          .withAlpha(120),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          7,
                                                        ),
                                                    child: Stack(
                                                      children: [
                                                        Positioned.fill(
                                                          child: Image.memory(
                                                            base64Decode(
                                                              expense.imageUrl!,
                                                            ),
                                                            fit: BoxFit.cover,
                                                          ),
                                                        ),
                                                        Positioned(
                                                          bottom: 1,
                                                          right: 1,
                                                          child: Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  1,
                                                                ),
                                                            decoration:
                                                                const BoxDecoration(
                                                                  color: Colors
                                                                      .black54,
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                            child: const Icon(
                                                              Icons.zoom_in,
                                                              size: 8,
                                                              color:
                                                                  Colors.white,
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
                                              style: textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: isPayment
                                                        ? Colors.green.shade600
                                                        : colorScheme.primary,
                                                  ),
                                            ),
                                            if (!isPayment && isAdmin) ...[
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                onPressed: () =>
                                                    showEditExpenseDialog(
                                                      expense,
                                                    ),
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: colorScheme.error,
                                                ),
                                                onPressed: () async {
                                                  final confirm =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: Text(
                                                        tr('¿Eliminar gasto?',
                                                            'Delete expense?'),
                                                      ),
                                                      content: Text(
                                                        tr(
                                                          '¿Estás seguro de que deseas eliminar este gasto? Se eliminarán todas las solicitudes de pago asociadas que no hayan sido pagadas. Si algún miembro ya realizó su pago, se creará una devolución automática para ajustar su balance.',
                                                          'Are you sure you want to delete this expense? All associated unpaid payment requests will be deleted. If any member has already paid, an automatic refund will be created to adjust their balance.',
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                ctx,
                                                                false,
                                                              ),
                                                          child: Text(
                                                            tr('Cancelar',
                                                                'Cancel'),
                                                          ),
                                                        ),
                                                        ElevatedButton(
                                                          style:
                                                              ElevatedButton
                                                                  .styleFrom(
                                                            backgroundColor:
                                                                colorScheme
                                                                    .error,
                                                            foregroundColor:
                                                                colorScheme
                                                                    .onError,
                                                          ),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                ctx,
                                                                true,
                                                              ),
                                                          child: Text(
                                                            tr('Eliminar',
                                                                'Delete'),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (confirm == true) {
                                                    await firestoreService
                                                        .deleteExpense(
                                                      groupId: widget.group.id,
                                                      expenseId: expense.id,
                                                    );
                                                  }
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              const SizedBox(height: 96), // FAB space
                            ],
                          ),
                        ),

                        // Tab 3: Estadísticas
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Builder(builder: (context) {
                            final categoryTotals = <String, double>{};
                            double totalExpensesAmount = 0.0;
                            for (final e in expenses) {
                              if (e.type != 'payment') {
                                final category = e.category;
                                categoryTotals[category] = (categoryTotals[category] ?? 0.0) + e.amount;
                                totalExpensesAmount += e.amount;
                              }
                            }

                            final memberPaidTotals = <String, double>{};
                            for (final e in expenses) {
                              if (e.type != 'payment') {
                                final payer = e.paidBy.trim().toLowerCase();
                                memberPaidTotals[payer] = (memberPaidTotals[payer] ?? 0.0) + e.amount;
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Estadísticas del Grupo', 'Group Statistics'),
                                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 16),
                                
                                // Card 1: Gastos por Categoría
                                Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr('Gastos por Categoría', 'Expenses by Category'),
                                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 12),
                                        if (totalExpensesAmount == 0)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 24),
                                            child: Center(
                                              child: Text(
                                                tr('No hay gastos registrados aún.', 'No expenses registered yet.'),
                                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                                              ),
                                            ),
                                          )
                                        else
                                          ...['Comida', 'Alquiler', 'Servicios', 'Actividades', 'Transporte', 'Otros'].map((cat) {
                                            final catAmount = categoryTotals[cat] ?? 0.0;
                                            final pct = totalExpensesAmount > 0 ? (catAmount / totalExpensesAmount) : 0.0;
                                            if (catAmount == 0) return const SizedBox.shrink();
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Icon(_getRubroIcon(cat), size: 16, color: colorScheme.primary),
                                                          const SizedBox(width: 8),
                                                          Text(translateCategory(cat), style: const TextStyle(fontWeight: FontWeight.w600)),
                                                        ],
                                                      ),
                                                      Text(
                                                        'Q${catAmount.toStringAsFixed(2)} (${(pct * 100).toStringAsFixed(1)}%)',
                                                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: LinearProgressIndicator(
                                                      value: pct,
                                                      minHeight: 8,
                                                      backgroundColor: colorScheme.surfaceContainerHighest,
                                                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                      ],
                                    ),
                                  ),
                                ),
                                
                                const SizedBox(height: 16),
                                
                                // Card 2: Contribución por Integrante
                                Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: colorScheme.outlineVariant.withAlpha(80)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tr('Aportes por Integrante', 'Contributions by Member'),
                                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 12),
                                        if (totalExpensesAmount == 0)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 24),
                                            child: Center(
                                              child: Text(
                                                tr('No hay aportes registrados aún.', 'No contributions registered yet.'),
                                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                                              ),
                                            ),
                                          )
                                        else
                                          ...group.members.map((member) {
                                            final mEmail = member.trim().toLowerCase();
                                            final mAmount = memberPaidTotals[mEmail] ?? 0.0;
                                            final pct = totalExpensesAmount > 0 ? (mAmount / totalExpensesAmount) : 0.0;
                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(_getMemberName(member), style: const TextStyle(fontWeight: FontWeight.w600)),
                                                      Text(
                                                        'Q${mAmount.toStringAsFixed(2)} (${(pct * 100).toStringAsFixed(1)}%)',
                                                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: LinearProgressIndicator(
                                                      value: pct,
                                                      minHeight: 8,
                                                      backgroundColor: colorScheme.surfaceContainerHighest,
                                                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.secondary),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 96),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                    floatingActionButton: StreamBuilder<GroupModel?>(
                      stream: _groupStream,
                      builder: (ctx, snap) {
                        final group = snap.data ?? widget.group;
                        if (!group.admins.contains(currentUserEmail)) {
                          return const SizedBox.shrink();
                        }
                        return FloatingActionButton.extended(
                          heroTag: 'fab_group_detail',
                          onPressed: () => _showAddExpenseDialog(group),
                          icon: const Icon(Icons.add),
                          label: Text(tr('Añadir Gasto', 'Add Expense')),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
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
}

// ─── Balance Status ───
enum _BalanceStatus { owes, owed, balanced }

// ignore: unused_element
class _BalanceCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final _BalanceStatus status;
  final bool isCurrentUser;
  final VoidCallback? onSettle;
  final VoidCallback? onReminder;
  final bool isSettlePending;

  const _BalanceCard({
    required this.label,
    required this.subtitle,
    required this.status,
    required this.isCurrentUser,
    this.onSettle,
    this.onReminder,
    this.isSettlePending = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Color borderColor;
    Color subtitleColor;
    switch (status) {
      case _BalanceStatus.owes:
        borderColor = colorScheme.error;
        subtitleColor = colorScheme.error;
        break;
      case _BalanceStatus.owed:
        borderColor = Colors.green.shade400;
        subtitleColor = Colors.green.shade700;
        break;
      case _BalanceStatus.balanced:
        borderColor = colorScheme.outlineVariant;
        subtitleColor = colorScheme.outline;
        break;
    }

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Text(
              label.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$label${isCurrentUser ? ' (Tú)' : ''}',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onSettle != null || isSettlePending) ...[
            const SizedBox(width: 8),
            FilledButton(
              onPressed: isSettlePending ? null : onSettle,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                isSettlePending ? 'Pendiente' : 'Saldar',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          if (onReminder != null) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onReminder,
              icon: Icon(
                Icons.notifications_active_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );

    return isCurrentUser ? card : card;
  }
}

// =============================================================================
// Widget: Lista de solicitudes de unión pendientes (para admins)
// =============================================================================
class _PendingJoinRequestsList extends StatelessWidget {
  final FirestoreService service;
  final String groupId;
  final String groupName;
  final String currentEmail;

  const _PendingJoinRequestsList({
    required this.service,
    required this.groupId,
    required this.groupName,
    required this.currentEmail,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GroupInvitation>>(
      stream: service.pendingJoinRequestsStream(groupId),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final requests = snap.data!;

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha(20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add_alt_1,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${tr('Solicitudes para unirse', 'Join requests')} (${requests.length})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final req = requests[index];
                  final email = req.fromEmail;
                  return ListTile(
                    title: Text(
                      email,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      tr('Quiere unirse al grupo', 'Wants to join the group'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => service.respondGroupInvitation(
                            invitationId: req.id,
                            accept: false,
                            groupId: groupId,
                            targetEmail: email,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => service.respondGroupInvitation(
                            invitationId: req.id,
                            accept: true,
                            groupId: groupId,
                            targetEmail: email,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
