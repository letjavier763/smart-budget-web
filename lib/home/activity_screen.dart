import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../services/firestore_service.dart';
import '../theme/translations.dart';

class _ActivityItem {
  final GroupModel group;
  final Expense expense;
  const _ActivityItem({required this.group, required this.expense});
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final Stream<List<GroupModel>> _groupsStream;

  @override
  void initState() {
    super.initState();
    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
    final service = FirestoreService();
    _groupsStream = service.groupsForUser(email);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim().toLowerCase();
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Historial de Actividad', 'Activity History'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: StreamBuilder<List<GroupModel>>(
        stream: _groupsStream,
        builder: (context, groupSnap) {
          if (groupSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (groupSnap.hasError) {
            return Center(child: Text('${tr('Error al cargar', 'Error loading')}: ${groupSnap.error}'));
          }

          final groups = groupSnap.data ?? [];

          if (groups.isEmpty) {
            return _emptyState(colorScheme, tr('No hay actividad reciente.', 'No recent activity.'));
          }

          return FutureBuilder<List<_ActivityItem>>(
            future: _loadActivity(groups, service),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final items = snap.data ?? [];

              if (items.isEmpty) {
                return _emptyState(colorScheme, tr('No hay gastos registrados en tus grupos.', 'No expenses registered in your groups.'));
              }

              // Group items by date header
              final now = DateTime.now();
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final date = item.expense.createdAt;
                  final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
                  final isYesterday = date.year == now.year && date.month == now.month && date.day == now.day - 1;
                  final dateLabel = isToday ? tr('Hoy', 'Today') : isYesterday ? tr('Ayer', 'Yesterday') : '${date.day}/${date.month}/${date.year}';

                  // Show date header if different from previous item
                  final showHeader = i == 0 ||
                      items[i - 1].expense.createdAt.day != date.day ||
                      items[i - 1].expense.createdAt.month != date.month;

                  final isPaidByMe = item.expense.paidBy.trim().toLowerCase() == email;
                  final expenseColor = isPaidByMe ? colorScheme.tertiary : colorScheme.error;
                  final expenseIcon = isPaidByMe ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader) ...[
                        if (i != 0) const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
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
                                  color: expenseColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(expenseIcon, color: expenseColor, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.expense.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(Icons.group_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            item.group.name,
                                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      isPaidByMe ? tr('Pagado por ti', 'Paid by you') : tr('Pagado por ${item.expense.paidBy.split('@')[0]}', 'Paid by ${item.expense.paidBy.split('@')[0]}'),
                                      style: TextStyle(fontSize: 12, color: expenseColor, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Q${item.expense.amount.toStringAsFixed(2)}',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: expenseColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_ActivityItem>> _loadActivity(
    List<GroupModel> groups,
    FirestoreService service,
  ) async {
    final items = <_ActivityItem>[];
    for (final group in groups) {
      final expenses = await service.getExpensesForGroup(group.id);
      for (final e in expenses) {
        items.add(_ActivityItem(group: group, expense: e));
      }
    }
    items.sort((a, b) => b.expense.createdAt.compareTo(a.expense.createdAt));
    return items;
  }

  Widget _emptyState(ColorScheme colorScheme, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 72, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 15)),
        ],
      ),
    );
  }
}
