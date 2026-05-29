import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/group.dart';
import '../models/payment_request.dart';
import '../services/firestore_service.dart';
import 'payments_screen.dart';
import 'package:proyecto_app/theme/translations.dart';


class _BalanceSummary {
  final double owedToUser;
  final double userOwes;

  const _BalanceSummary({required this.owedToUser, required this.userOwes});

  double get net => owedToUser - userOwes;
}

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSwitchToGroups;
  const HomeScreen({super.key, this.onSwitchToGroups});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  List<GroupModel> _cachedGroups = [];
  bool _hasCheckedReminders = false;
  late final Stream<List<GroupModel>> _groupsStream;
  late final Stream<List<PaymentRequest>> _activePaymentsStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _groupsStream = _firestoreService.groupsForUser(user?.email ?? '');
    _activePaymentsStream = _firestoreService.activePaymentRequestsForUser(user?.email ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _checkPendingReminders(String userEmail, List<GroupModel> groups) async {
    if (_hasCheckedReminders) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingCode = prefs.getString('pending_join_code');
      if (pendingCode != null && pendingCode.isNotEmpty) {
        // Posponer el recordatorio para no interferir con el diálogo de invitación
        return;
      }
    } catch (_) {}

    _hasCheckedReminders = true;
    
    try {
      bool hasOldReminders = false;
      for (final g in groups) {
        final reqsSnap = await _firestoreService.pendingRequestsForGroup(g.id).first;
        for (final req in reqsSnap) {
          if (req.toEmail == userEmail) {
            final daysOld = DateTime.now().difference(req.createdAt).inDays;
            if (daysOld >= 3) {
              hasOldReminders = true;
              break;
            }
          }
        }
        if (hasOldReminders) break;
      }

      if (hasOldReminders && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('¡Tienes recordatorios pendientes!', 'You have pending reminders!')),
            content: Text(tr('Hay solicitudes de pago hacia ti que llevan más de 3 días sin ser confirmadas o pagadas. Por favor, revisa tus pagos.', 'There are payment requests to you that have been unconfirmed or unpaid for more than 3 days. Please review your payments.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Entendido', 'Got it'))),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsScreen()));
                },
                child: Text(tr('Ver Pagos', 'View Payments')),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error comprobando recordatorios: $e');
    }
  }

  Future<_BalanceSummary> _calculateBalance(
    String userEmail,
    List<GroupModel> groups,
  ) async {
    double owedToUser = 0;
    double userOwes = 0;

    final allExpenses = await Future.wait(
      groups.map((group) => _firestoreService.getExpensesForGroup(group.id)),
    );

    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      final expenses = allExpenses[index];
      if (group.members.isEmpty) continue;
      
      double groupBalance = 0;

      for (final expense in expenses) {
        if (expense.type == 'payment') {
          if (expense.paidBy == userEmail) {
            groupBalance += expense.amount;
          }
          if (expense.paidTo == userEmail) {
            groupBalance -= expense.amount;
          }
        } else {
          if (expense.paidBy == userEmail) {
            groupBalance += expense.amount;
          }
          final involved = expense.involvedMembers.isNotEmpty 
              ? expense.involvedMembers 
              : group.members;
          if (involved.contains(userEmail)) {
            groupBalance -= (expense.amount / involved.length);
          }
        }
      }

      if (groupBalance > 0.01) {
        owedToUser += groupBalance;
      } else if (groupBalance < -0.01) {
        userOwes += -groupBalance;
      }
    }

    return _BalanceSummary(owedToUser: owedToUser, userOwes: userOwes);
  }

  Future<void> _showAddExpenseDialog(
    BuildContext context,
    String userEmail,
    List<GroupModel> groups,
  ) async {
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Primero crea o únete a un grupo.', 'First create or join a group.'))),
      );
      return;
    }

    GroupModel? selectedGroup = groups.first;
    String selectedCategory = 'Otros';
    _titleController.clear();
    _amountController.clear();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(tr('Nuevo Gasto', 'New Expense')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<GroupModel>(
                      initialValue: selectedGroup,
                      decoration: InputDecoration(labelText: tr('Grupo', 'Group')),
                      items: groups
                          .map((g) => DropdownMenuItem(value: g, child: Text(g.name)))
                          .toList(),
                      onChanged: (g) => setDialogState(() => selectedGroup = g),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(labelText: tr('Descripción', 'Description')),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: tr('Monto', 'Amount')),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(labelText: tr('Categoría', 'Category')),
                      items: ['Comida', 'Alquiler', 'Servicios', 'Actividades', 'Transporte', 'Otros']
                          .map((c) => DropdownMenuItem(value: c, child: Text(translateCategory(c))))
                          .toList(),
                      onChanged: (c) => setDialogState(() => selectedCategory = c!),
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
                    final title = _titleController.text.trim();
                    final amount = double.tryParse(
                      _amountController.text.trim().replaceAll(',', '.'),
                    );
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(ctx);
                    if (title.isEmpty || amount == null || amount <= 0 || selectedGroup == null) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(tr('Completa todos los campos correctamente.', 'Complete all fields correctly.'))),
                      );
                      return;
                    }
                    try {
                      await _firestoreService.createExpense(
                        groupId: selectedGroup!.id,
                        title: title,
                        amount: amount,
                        paidBy: userEmail,
                        involvedMembers: selectedGroup!.members,
                        category: selectedCategory,
                      );
                      navigator.pop();
                      messenger.showSnackBar(
                        SnackBar(content: Text(tr('¡Gasto agregado exitosamente!', 'Expense added successfully!'))),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('${tr('Error', 'Error')}: $e')),
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

  void _showNotificationsDialog(BuildContext context, String userEmail) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.notificationsForUser(userEmail),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(tr('No tienes notificaciones.', 'You have no notifications.'))),
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(tr('Notificaciones', 'Notifications'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (ctx, i) {
                      final doc = docs[i];
                      final data = doc.data() as Map<String, dynamic>;
                      final isRead = data['isRead'] == true;
                      final timestamp = data['createdAt'] as Timestamp?;
                      final dateStr = timestamp != null
                          ? '${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year} ${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
                          : '';

                      return ListTile(
                        tileColor: isRead ? null : Colors.blue.shade50,
                        leading: Icon(Icons.notifications, color: isRead ? Colors.grey : Colors.blue),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(data['title'] ?? '')),
                            if (dateStr.isNotEmpty)
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(180),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(data['body'] ?? ''),
                        onTap: () {
                          if (!isRead) {
                            _firestoreService.markNotificationAsRead(userEmail, doc.id);
                          }
                          if (data.containsKey('requestId')) {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PaymentsScreen(initialIndex: 1)),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (email.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Panel Principal', 'Main Panel'))),
        body: Center(
          child: Text(tr('Error: no se encontró el correo del usuario.', 'Error: user email not found.')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Inicio', 'Dashboard'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: _firestoreService.notificationsForUser(email),
            builder: (context, snapshot) {
              final notifs = snapshot.data?.docs ?? [];
              final unreadCount = notifs.where((d) => !(d.data() as Map<String, dynamic>)['isRead']).length;
              return IconButton(
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text('$unreadCount'),
                  child: const Icon(Icons.notifications_none),
                ),
                onPressed: () => _showNotificationsDialog(context, email),
              );
            }
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tr('Hola', 'Hello')}, ${user?.displayName ?? email.split('@')[0]}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('Aquí tienes un resumen de tus cuentas.', 'Here is a summary of your accounts.'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              StreamBuilder<List<GroupModel>>(
                stream: _groupsStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('${tr('Error al cargar datos', 'Error loading data')}: ${snapshot.error}'),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final groups = snapshot.data ?? [];
                  _cachedGroups = groups;

                  if (!_hasCheckedReminders && groups.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _checkPendingReminders(email, groups);
                    });
                  }

                  return FutureBuilder<_BalanceSummary>(
                    future: _calculateBalance(email, groups),
                    builder: (context, balanceSnapshot) {
                      final summary = balanceSnapshot.data ?? const _BalanceSummary(owedToUser: 0, userOwes: 0);

                      return Column(
                        children: [
                          // Bento Grid
                          Row(
                            children: [
                              // Balance Total (A favor)
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorScheme.primary.withValues(alpha: 0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.account_balance_wallet, color: colorScheme.onPrimary, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            tr('Balance a favor', 'Balance in favor'),
                                            style: TextStyle(color: colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Q${summary.owedToUser.toStringAsFixed(2)}',
                                        style: theme.textTheme.headlineMedium?.copyWith(
                                          color: colorScheme.onPrimary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Debes
                              Expanded(
                                flex: 1,
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.money_off, color: colorScheme.onErrorContainer, size: 20),
                                      const SizedBox(height: 12),
                                      Text(
                                        tr('Debes', 'You owe'),
                                        style: TextStyle(color: colorScheme.onErrorContainer.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Q${summary.userOwes.toStringAsFixed(0)}',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          color: colorScheme.onErrorContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Grupos Card
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: colorScheme.onSecondaryContainer.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.group, color: colorScheme.onSecondaryContainer, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tr('Grupos activos', 'Active groups'),
                                            style: TextStyle(color: colorScheme.onSecondaryContainer, fontSize: 12),
                                          ),
                                          Text(
                                            '${groups.length}',
                                            style: TextStyle(color: colorScheme.onSecondaryContainer, fontSize: 18, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                tr('Acciones Rápidas', 'Quick Actions'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Action Cards List
              StreamBuilder<List<PaymentRequest>>(
                stream: _activePaymentsStream,
                builder: (context, snap) {
                  final badgeCount = snap.data?.length ?? 0;
                  return _buildActionCard(
                    context: context,
                    icon: Icons.receipt_long,
                    title: tr('Estado de Cuenta', 'Account Balance'),
                    subtitle: tr('Revisa tus pagos y estados de deuda', 'Check your payments and debt status'),
                    color: colorScheme.secondary,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsScreen()));
                    },
                    badgeCount: badgeCount,
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildActionCard(
                context: context,
                icon: Icons.add_circle_outline,
                title: tr('Nuevo Gasto', 'New Expense'),
                subtitle: tr('Añade un gasto a un grupo existente', 'Add an expense to an existing group'),
                color: colorScheme.tertiary,
                onTap: () => _showAddExpenseDialog(context, email, _cachedGroups),
              ),
              const SizedBox(height: 12),
              _buildActionCard(
                context: context,
                icon: Icons.group_add_outlined,
                title: tr('Crear Grupo', 'Create Group'),
                subtitle: tr('Empieza a compartir gastos', 'Start sharing expenses'),
                color: colorScheme.primary,
                onTap: () {
                  if (widget.onSwitchToGroups != null) {
                    widget.onSwitchToGroups!();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('Ve a la pestaña de Grupos para crear uno.', 'Go to the Groups tab to create one.'))),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeCount > 0) ...[
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Icon(Icons.chevron_right, color: theme.colorScheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}
