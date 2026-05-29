import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:proyecto_app/models/group.dart';
import 'package:proyecto_app/services/firestore_service.dart';
import 'package:proyecto_app/theme/translations.dart';
import 'package:proyecto_app/widgets/group_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:proyecto_app/main.dart';
import 'package:proyecto_app/utils/print_utility.dart';

class AdminDashboardScreen extends StatefulWidget {
  final VoidCallback onExitAdminMode;

  const AdminDashboardScreen({super.key, required this.onExitAdminMode});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  final String _currentEmail =
      FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';

  late final TabController _tabController;
  late final Stream<List<Map<String, dynamic>>> _usersStream;
  late final Stream<List<GroupModel>> _groupsStream;

  // Cache latest stream data so the AppBar export button can use it.
  // Updated via callbacks from child tab widgets.
  List<GroupModel> _latestGroups = [];
  List<Map<String, dynamic>> _latestUsers = [];

  @override
  void initState() {
    super.initState();
    _usersStream = _firestoreService.getAllUsersStream();
    _groupsStream = _firestoreService.getAllGroupsStream();
    // No addListener with setState here — that causes setState during
    // mouse-event processing → mouse_tracker assertion crash on Flutter web.
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── PDF EXPORT ────────────────────────────────────────────────────────────
  void _showAdminExportOptionsDialog() {
    bool includeStats = true;
    bool includeUsers = true;
    bool includeGroups = true;
    bool includeBudgets = true;
    bool includeSecurity = true;
    bool includeRanking = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('Exportar Reporte de Administración', 'Export Administration Report')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(
                    'Selecciona las secciones que deseas incluir en el reporte de administración central:',
                    'Select the sections you want to include in the central administration report:',
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: includeStats,
                  title: Text(tr('Estadísticas Generales', 'General Statistics')),
                  subtitle: Text(tr('Métricas de grupos, miembros totales y distribución.', 'Group metrics, total members, and distribution.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeStats = val);
                  },
                ),
                CheckboxListTile(
                  value: includeUsers,
                  title: Text(tr('Directorio de Usuarios', 'Users Directory')),
                  subtitle: Text(tr('Listado completo de usuarios registrados y sus roles.', 'Complete list of registered users and their roles.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeUsers = val);
                  },
                ),
                CheckboxListTile(
                  value: includeGroups,
                  title: Text(tr('Registro de Grupos', 'Groups Directory')),
                  subtitle: Text(tr('Listado completo de grupos, códigos de acceso y creadores.', 'Complete list of groups, access codes, and creators.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeGroups = val);
                  },
                ),
                CheckboxListTile(
                  value: includeBudgets,
                  title: Text(tr('Auditoría de Presupuestos', 'Budgets Audit')),
                  subtitle: Text(tr('Presupuesto vs. total gastado por cada grupo del sistema.', 'Budget vs. total spent for each group in the system.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeBudgets = val);
                  },
                ),
                CheckboxListTile(
                  value: includeSecurity,
                  title: Text(tr('Resumen de Seguridad', 'Security Summary')),
                  subtitle: Text(tr('Detalle de administradores activos y balance de permisos.', 'Detail of active administrators and permissions balance.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeSecurity = val);
                  },
                ),
                CheckboxListTile(
                  value: includeRanking,
                  title: Text(tr('Ranking de Creadores', 'Creators Ranking')),
                  subtitle: Text(tr('Clasificación de usuarios según cantidad de grupos creados.', 'Ranking of users based on the number of groups created.')),
                  onChanged: (val) {
                    if (val != null) setState(() => includeRanking = val);
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
              onPressed: () async {
                Navigator.pop(ctx);
                
                // Show a loading indicator dialog since we will query budgets
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (loadingCtx) => const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Generando Reporte...'),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                await _generateAdminHtmlReport(
                  includeStats: includeStats,
                  includeUsers: includeUsers,
                  includeGroups: includeGroups,
                  includeBudgets: includeBudgets,
                  includeSecurity: includeSecurity,
                  includeRanking: includeRanking,
                );

                if (mounted) {
                  Navigator.pop(context); // Close loading dialog
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateAdminHtmlReport({
    required bool includeStats,
    required bool includeUsers,
    required bool includeGroups,
    required bool includeBudgets,
    required bool includeSecurity,
    required bool includeRanking,
  }) async {
    final buffer = StringBuffer();
    final timeStr = DateTime.now().toLocal().toString().split('.')[0];

    buffer.write('<html><head><meta charset="UTF-8"><title>Reporte de Administración Central</title>');
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
    buffer.write('.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 25px; }');
    buffer.write('.card { border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; background-color: #f8fafc; }');
    buffer.write('.card-title { font-weight: 600; color: #475569; font-size: 12px; text-transform: uppercase; margin-bottom: 6px; }');
    buffer.write('.card-value { font-size: 20px; font-weight: 700; color: #003289; }');
    buffer.write('.badge { display: inline-block; padding: 2px 8px; font-size: 12px; font-weight: 600; border-radius: 4px; }');
    buffer.write('.badge-admin { background-color: #dcfce7; color: #15803d; }');
    buffer.write('.badge-user { background-color: #f1f5f9; color: #475569; }');
    buffer.write('.badge-danger { background-color: #fee2e2; color: #b91c1c; }');
    buffer.write('.badge-success { background-color: #dcfce7; color: #15803d; }');
    buffer.write('</style></head><body>');

    // Header
    buffer.write('<div class="header">');
    buffer.write('<h1>SmartBudget - Reporte de Administración Central</h1>');
    buffer.write('<div class="meta"><strong>Generado por:</strong> $_currentEmail</div>');
    buffer.write('<div class="meta"><strong>Fecha de reporte:</strong> $timeStr</div>');
    buffer.write('</div>');

    // Section 1: Stats
    if (includeStats && _latestGroups.isNotEmpty) {
      final int totalMembers = _latestGroups.fold<int>(0, (sum, g) => sum + g.members.length);
      final double avgMembers = _latestGroups.isNotEmpty ? totalMembers / _latestGroups.length : 0.0;
      int smallCount = 0, mediumCount = 0, largeCount = 0;
      for (var g in _latestGroups) {
        if (g.members.length <= 2) {
          smallCount++;
        } else if (g.members.length <= 5) {
          mediumCount++;
        } else {
          largeCount++;
        }
      }

      buffer.write('<h2>Estadísticas Generales</h2>');
      buffer.write('<div class="grid">');
      buffer.write('<div class="card"><div class="card-title">Total de Grupos</div><div class="card-value">${_latestGroups.length}</div></div>');
      buffer.write('<div class="card"><div class="card-title">Total de Miembros</div><div class="card-value">$totalMembers</div></div>');
      buffer.write('<div class="card"><div class="card-title">Promedio Miembros / Grupo</div><div class="card-value">${avgMembers.toStringAsFixed(1)}</div></div>');
      buffer.write('</div>');

      buffer.write('<h3>Distribución del Tamaño de Grupos</h3>');
      buffer.write('<table><thead><tr><th>Tamaño del Grupo</th><th>Cantidad</th></tr></thead><tbody>');
      buffer.write('<tr><td>Pequeños (1-2 miembros)</td><td><strong>$smallCount</strong></td></tr>');
      buffer.write('<tr><td>Medianos (3-5 miembros)</td><td><strong>$mediumCount</strong></td></tr>');
      buffer.write('<tr><td>Grandes (6+ miembros)</td><td><strong>$largeCount</strong></td></tr>');
      buffer.write('</tbody></table>');
    }

    // Section 2: Users List
    if (includeUsers && _latestUsers.isNotEmpty) {
      buffer.write('<h2>Directorio de Usuarios</h2>');
      buffer.write('<table><thead><tr><th>Nombre</th><th>Correo Electrónico</th><th>Rol</th></tr></thead><tbody>');
      for (var u in _latestUsers) {
        final email = u['email'] as String? ?? '';
        final name = u['displayName'] as String? ?? email.split('@')[0];
        final role = u['role'] as String? ?? 'user';
        final badgeClass = role.toLowerCase() == 'admin' ? 'badge badge-admin' : 'badge badge-user';
        buffer.write('<tr><td><strong>$name</strong></td><td>$email</td><td><span class="$badgeClass">${role.toUpperCase()}</span></td></tr>');
      }
      buffer.write('</tbody></table>');
    }

    // Section 3: Security & Roles Summary
    if (includeSecurity && _latestUsers.isNotEmpty) {
      final adminsCount = _latestUsers.where((u) => (u['role'] as String? ?? '').toLowerCase() == 'admin').length;
      final usersCount = _latestUsers.length - adminsCount;

      buffer.write('<h2>Resumen de Seguridad y Roles</h2>');
      buffer.write('<div class="grid">');
      buffer.write('<div class="card"><div class="card-title">Administradores del Sistema</div><div class="card-value">$adminsCount</div></div>');
      buffer.write('<div class="card"><div class="card-title">Usuarios Regulares</div><div class="card-value">$usersCount</div></div>');
      buffer.write('</div>');

      buffer.write('<h3>Administradores Activos con Acceso Total</h3>');
      buffer.write('<table><thead><tr><th>Nombre</th><th>Correo Electrónico</th><th>Rol de Acceso</th></tr></thead><tbody>');
      for (var u in _latestUsers) {
        final role = u['role'] as String? ?? 'user';
        if (role.toLowerCase() == 'admin') {
          final email = u['email'] as String? ?? '';
          final name = u['displayName'] as String? ?? email.split('@')[0];
          buffer.write('<tr><td><strong>$name</strong></td><td>$email</td><td><span class="badge badge-admin">SUPER ADMIN</span></td></tr>');
        }
      }
      buffer.write('</tbody></table>');
    }

    // Section 4: Ranking of Creators
    if (includeRanking && _latestGroups.isNotEmpty) {
      final Map<String, int> creatorCounts = {};
      for (final g in _latestGroups) {
        final creator = g.createdBy.trim().toLowerCase();
        creatorCounts[creator] = (creatorCounts[creator] ?? 0) + 1;
      }

      final sortedCreators = creatorCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      buffer.write('<h2>Ranking de Creadores de Grupos</h2>');
      buffer.write('<p>Usuarios que han configurado y creado más espacios de presupuesto colaborativo en el sistema:</p>');
      buffer.write('<table><thead><tr><th>Posición</th><th>Creador (Correo)</th><th>Grupos Creados</th></tr></thead><tbody>');
      int rank = 1;
      for (final entry in sortedCreators) {
        buffer.write('<tr><td><strong>#$rank</strong></td><td>${entry.key}</td><td><strong>${entry.value} grupo(s)</strong></td></tr>');
        rank++;
      }
      buffer.write('</tbody></table>');
    }

    // Section 5: Budgets Audit (Loads dynamically)
    if (includeBudgets && _latestGroups.isNotEmpty) {
      buffer.write('<h2>Auditoría de Presupuestos de Grupos</h2>');
      buffer.write('<p>Comparación en tiempo real del presupuesto inicial asignado frente al gasto total acumulado en cada grupo:</p>');
      buffer.write('<table><thead><tr><th>Nombre de Grupo</th><th>Presupuesto Inicial</th><th>Gasto Acumulado</th><th>Balance Restante</th><th>Estado</th></tr></thead><tbody>');

      for (final g in _latestGroups) {
        double budget = g.initialBudget ?? 0.0;
        double spent = 0.0;

        try {
          final snap = await FirebaseFirestore.instance
              .collection('groups')
              .doc(g.id)
              .collection('expenses')
              .get();
          for (final doc in snap.docs) {
            final data = doc.data();
            if (data['type'] != 'payment') {
              spent += (data['amount'] as num?)?.toDouble() ?? 0.0;
            }
          }
        } catch (e) {
          debugPrint('Error fetching expenses for budget audit: $e');
        }

        final remaining = budget - spent;
        final statusLabel = remaining < 0 ? 'Excedido' : 'Bajo control';
        final statusBadge = remaining < 0 ? 'badge badge-danger' : 'badge badge-success';

        buffer.write('<tr>');
        buffer.write('<td><strong>${g.name}</strong> <br/><small style="color: #64748b;">Código: ${g.code}</small></td>');
        buffer.write('<td>Q${budget.toStringAsFixed(2)}</td>');
        buffer.write('<td>Q${spent.toStringAsFixed(2)}</td>');
        buffer.write('<td style="color: ${remaining < 0 ? '#b91c1c' : '#15803d'}; font-weight: bold;">Q${remaining.toStringAsFixed(2)}</td>');
        buffer.write('<td><span class="$statusBadge">$statusLabel</span></td>');
        buffer.write('</tr>');
      }

      buffer.write('</tbody></table>');
    }

    // Section 6: Groups List
    if (includeGroups && _latestGroups.isNotEmpty) {
      buffer.write('<h2>Registro General de Grupos</h2>');
      buffer.write('<table><thead><tr><th>Nombre de Grupo</th><th>Código de Acceso</th><th>Miembros</th><th>Creado por</th></tr></thead><tbody>');
      for (var g in _latestGroups) {
        final creatorName = g.createdBy.split('@')[0];
        buffer.write('<tr><td><strong>${g.name}</strong></td><td><code>${g.code}</code></td><td>${g.members.length} miembros</td><td>$creatorName (${g.createdBy})</td></tr>');
      }
      buffer.write('</tbody></table>');
    }

    buffer.write('<script>window.onload = function() { window.print(); }</script>');
    buffer.write('</body></html>');

    printHtmlReport(
      title: 'Reporte_Administracion_Central',
      htmlContent: buffer.toString(),
    );
  }

  // ─── DIALOGS ───────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cerrar Sesión', 'Log Out')),
        content: Text(tr(
          '¿Estás seguro de que deseas cerrar tu sesión?',
          'Are you sure you want to log out?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Salir', 'Exit'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('demo_admin_mode', false);
      adminDemoNotifier.value = false;
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _confirmDeleteUser(String uid, String email) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminar Usuario', 'Delete User')),
        content: Text(tr(
          '¿Estás seguro de que deseas eliminar al usuario $email? Esta acción no se puede deshacer.',
          'Are you sure you want to delete user $email? This action cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Eliminar', 'Delete'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _firestoreService.deleteUser(uid);
        messenger.showSnackBar(SnackBar(
            content: Text(
                tr('Usuario eliminado exitosamente.', 'User deleted successfully.'))));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('${tr('Error al eliminar', 'Error deleting')}: $e')));
      }
    }
  }

  Future<void> _confirmDeleteGroup(GroupModel group) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Eliminar Grupo', 'Delete Group')),
        content: Text(tr(
          '¿Estás seguro de que deseas eliminar el grupo "${group.name}"? Se borrarán todos los datos del grupo permanentemente.',
          'Are you sure you want to delete group "${group.name}"? All group data will be permanently deleted.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Eliminar', 'Delete'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _firestoreService.deleteGroup(groupId: group.id);
        messenger.showSnackBar(SnackBar(
            content: Text(
                tr('Grupo eliminado exitosamente.', 'Group deleted successfully.'))));
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('${tr('Error al eliminar', 'Error deleting')}: $e')));
      }
    }
  }

  Future<void> _toggleUserRole(String uid, String currentRole) async {
    final newRole = currentRole == 'admin' ? 'user' : 'admin';
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _firestoreService.updateUserRole(uid, newRole);
      messenger.showSnackBar(SnackBar(
          content:
              Text(tr('Rol de usuario actualizado.', 'User role updated.'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(
              '${tr('Error al actualizar rol', 'Error updating role')}: $e')));
    }
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Panel de Administración Central', 'Central Administration Panel'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          // PDF export button — single button that exports the active tab
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: tr('Exportar PDF', 'Export PDF'),
            onPressed: _showAdminExportOptionsDialog,
          ),
          TextButton.icon(
            onPressed: widget.onExitAdminMode,
            icon: const Icon(Icons.swap_horiz, color: Colors.white),
            label: Text(tr('Modo Cliente', 'Client Mode'),
                style: const TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: tr('Cerrar sesión', 'Logout'),
            onPressed: _logout,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
                icon: const Icon(Icons.analytics_outlined),
                text: tr('Estadísticas', 'Analytics')),
            Tab(
                icon: const Icon(Icons.people_outline),
                text: tr('Usuarios', 'Users')),
            Tab(
                icon: const Icon(Icons.group_outlined),
                text: tr('Grupos', 'Groups')),
          ],
          indicatorColor: colorScheme.onPrimary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildAnalyticsTab(),
            _UsersTabView(
              stream: _usersStream,
              currentEmail: _currentEmail,
              onToggleRole: _toggleUserRole,
              onDeleteUser: _confirmDeleteUser,
              onUsersUpdated: (u) => _latestUsers = u,
            ),
            _GroupsTabView(
              stream: _groupsStream,
              onDeleteGroup: _confirmDeleteGroup,
              onGroupsUpdated: (g) => _latestGroups = g,
            ),
          ],
        ),
      ),
    );
  }

  // ─── TAB 1: ANALYTICS ──────────────────────────────────────────────────────
  Widget _buildAnalyticsTab() {
    return StreamBuilder<List<GroupModel>>(
      stream: _firestoreService.getAllGroupsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final groups = snapshot.data ?? [];
        // Update cache for PDF export
        _latestGroups = groups;

        if (groups.isEmpty) {
          return Center(
            child: Text(tr('No hay grupos registrados en el sistema.',
                'No groups registered in the system.')),
          );
        }

        final int totalMembers =
            groups.fold<int>(0, (sum, g) => sum + g.members.length);
        final double avgMembers =
            groups.isNotEmpty ? totalMembers / groups.length : 0.0;

        // SingleChildScrollView(vertical) → unbounded height.
        // NEVER use Expanded/Flex-vertical inside it.
        // LayoutBuilder inside it gives bounded width → Row+Expanded is safe.
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stat Cards ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: tr('Total de Grupos', 'Total Groups'),
                      value: '${groups.length}',
                      icon: Icons.group_work_outlined,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF003289), Color(0xFF0052D4)]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title: tr('Total de Miembros', 'Total Members'),
                      value: '$totalMembers',
                      icon: Icons.people_outline,
                      gradient: const LinearGradient(
                          colors: [Color(0xFF005C3E), Color(0xFF008A56)]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatCard(
                      title:
                          tr('Miembros por Grupo (Prom.)', 'Avg Members / Group'),
                      value: avgMembers.toStringAsFixed(1),
                      icon: Icons.bar_chart_outlined,
                      gradient: const LinearGradient(
                          colors: [Color(0xFFBA1A1A), Color(0xFFE53935)]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              // ── Charts ──────────────────────────────────────────────────
              // LayoutBuilder inside SingleChildScrollView(vertical):
              //   maxWidth = bounded (viewport width) ✓
              //   maxHeight = infinite ✗  → do NOT use Expanded vertically
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;

                  final pieCard = _buildChartCard(
                    title: tr('Distribución de Miembros por Grupo',
                        'Group Size Distribution'),
                    child: _buildPieChart(groups),
                  );
                  final barCard = _buildChartCard(
                    title: tr('Comparación de Miembros (Top 5)',
                        'Member Count (Top 5)'),
                    child: _buildBarChart(groups),
                  );

                  if (isWide) {
                    // Row + Expanded: safe because width is bounded
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: pieCard),
                        const SizedBox(width: 20),
                        Expanded(child: barCard),
                      ],
                    );
                  }
                  // Narrow: Column without Expanded — vertical axis unbounded
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [pieCard, const SizedBox(height: 20), barCard],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChartCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Gradient gradient,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      height: 120,
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(icon, size: 64, color: Colors.white10),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(List<GroupModel> groups) {
    int smallCount = 0, mediumCount = 0, largeCount = 0;
    for (var g in groups) {
      if (g.members.length <= 2) {
        smallCount++;
      } else if (g.members.length <= 5) {
        mediumCount++;
      } else {
        largeCount++;
      }
    }
    final total = groups.length;
    final smallPct = total > 0 ? (smallCount / total) : 0.0;
    final mediumPct = total > 0 ? (mediumCount / total) : 0.0;
    final largePct = total > 0 ? (largeCount / total) : 0.0;

    return Row(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _PieChartPainter(
              slices: [smallPct, mediumPct, largePct],
              colors: const [
                Color(0xFF003289),
                Color(0xFF008A56),
                Color(0xFFBA1A1A),
              ],
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendItem(
                  tr('Pequeños (1-2)', 'Small (1-2)'),
                  '${(smallPct * 100).toStringAsFixed(1)}%',
                  const Color(0xFF003289)),
              const SizedBox(height: 8),
              _buildLegendItem(
                  tr('Medianos (3-5)', 'Medium (3-5)'),
                  '${(mediumPct * 100).toStringAsFixed(1)}%',
                  const Color(0xFF008A56)),
              const SizedBox(height: 8),
              _buildLegendItem(
                  tr('Grandes (6+)', 'Large (6+)'),
                  '${(largePct * 100).toStringAsFixed(1)}%',
                  const Color(0xFFBA1A1A)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        Text(value,
            style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBarChart(List<GroupModel> groups) {
    final sorted = List<GroupModel>.from(groups)
      ..sort((a, b) => b.members.length.compareTo(a.members.length));
    final top = sorted.take(5).toList();
    int maxM = top.isNotEmpty ? top.first.members.length : 1;
    if (maxM < 1) maxM = 1;

    return SizedBox(
      height: 140,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: top.map((g) {
          final hFactor = g.members.length / maxM;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${g.members.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11)),
                const SizedBox(height: 4),
                Container(
                  height: (hFactor * 90).clamp(5.0, 90.0),
                  margin: const EdgeInsets.symmetric(horizontal: 8.0),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF003289), Color(0xFF6A1B9A)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  g.name.length > 8 ? '${g.name.substring(0, 7)}…' : g.name,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _UsersTabView extends StatefulWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  final String currentEmail;
  final Function(String uid, String role) onToggleRole;
  final Function(String uid, String email) onDeleteUser;
  final ValueChanged<List<Map<String, dynamic>>> onUsersUpdated;

  const _UsersTabView({
    required this.stream,
    required this.currentEmail,
    required this.onToggleRole,
    required this.onDeleteUser,
    required this.onUsersUpdated,
  });

  @override
  State<_UsersTabView> createState() => _UsersTabViewState();
}

class _UsersTabViewState extends State<_UsersTabView> {
  final TextEditingController _usersSearchController = TextEditingController();
  String _usersQuery = '';

  @override
  void initState() {
    super.initState();
    _usersSearchController.addListener(() {
      setState(() {
        _usersQuery = _usersSearchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _usersSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final users = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onUsersUpdated(users);
        });

        // Apply search filter
        final filtered = _usersQuery.isEmpty
            ? users
            : users.where((u) {
                final email = (u['email'] as String? ?? '').toLowerCase();
                final name = (u['displayName'] as String? ?? '').toLowerCase();
                final role = (u['role'] as String? ?? '').toLowerCase();
                return email.contains(_usersQuery) ||
                    name.contains(_usersQuery) ||
                    role.contains(_usersQuery);
              }).toList();

        return Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _usersSearchController,
                decoration: InputDecoration(
                  hintText: tr('Buscar usuarios…', 'Search users…'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _usersQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: tr('Limpiar', 'Clear'),
                          onPressed: () => _usersSearchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
            ),
            // ── Result count hint ──────────────────────────────────────────
            if (_usersQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(
                      '${filtered.length} resultado(s) de ${users.length}',
                      '${filtered.length} result(s) of ${users.length}',
                    ),
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            // ── List ────────────────────────────────────────────────────────
            if (filtered.isEmpty && users.isNotEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    tr('Sin resultados para "$_usersQuery".',
                        'No results for "$_usersQuery".'),
                  ),
                ),
              )
            else if (users.isEmpty)
              Expanded(
                child: Center(
                  child: Text(tr('No hay usuarios registrados.',
                      'No registered users.'))),
                )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    final email = user['email'] as String? ?? '';
                    final name =
                        user['displayName'] as String? ?? email.split('@')[0];
                    final photoUrl = user['photoUrl'] as String?;
                    final role = user['role'] as String? ?? 'user';
                    final uid = user['uid'] as String;
                    final isSelf = email == widget.currentEmail;

                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: _getUserAvatarImage(photoUrl),
                          child: _getUserAvatarImage(photoUrl) == null
                              ? Text(
                                  name.isNotEmpty
                                      ? name.substring(0, 1).toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.bold))
                              : null,
                        ),
                        title: Row(
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: role == 'admin'
                                    ? colorScheme.primaryContainer
                                    : colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                role.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: role == 'admin'
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(email,
                            style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 13)),
                        trailing: isSelf
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                        role == 'admin'
                                            ? Icons.verified_user
                                            : Icons.security,
                                        color: Colors.blue),
                                    tooltip: role == 'admin'
                                        ? tr('Quitar Admin', 'Revoke Admin')
                                        : tr('Hacer Admin', 'Make Admin'),
                                    onPressed: () =>
                                        widget.onToggleRole(uid, role),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: tr('Eliminar', 'Delete'),
                                    onPressed: () =>
                                        widget.onDeleteUser(uid, email),
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

  ImageProvider? _getUserAvatarImage(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
      return NetworkImage(photoUrl);
    }
    try {
      return MemoryImage(base64Decode(photoUrl));
    } catch (e) {
      debugPrint('Error decoding user base64 photo: $e');
      return null;
    }
  }
}

class _GroupsTabView extends StatefulWidget {
  final Stream<List<GroupModel>> stream;
  final Function(GroupModel group) onDeleteGroup;
  final ValueChanged<List<GroupModel>> onGroupsUpdated;

  const _GroupsTabView({
    required this.stream,
    required this.onDeleteGroup,
    required this.onGroupsUpdated,
  });

  @override
  State<_GroupsTabView> createState() => _GroupsTabViewState();
}

class _GroupsTabViewState extends State<_GroupsTabView> {
  final TextEditingController _groupsSearchController = TextEditingController();
  String _groupsQuery = '';

  @override
  void initState() {
    super.initState();
    _groupsSearchController.addListener(() {
      setState(() {
        _groupsQuery = _groupsSearchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _groupsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<GroupModel>>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final groups = snapshot.data ?? [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onGroupsUpdated(groups);
        });

        // Apply search filter
        final filtered = _groupsQuery.isEmpty
            ? groups
            : groups.where((g) {
                final name = g.name.toLowerCase();
                final code = g.code.toLowerCase();
                final creator = g.createdBy.toLowerCase();
                return name.contains(_groupsQuery) ||
                    code.contains(_groupsQuery) ||
                    creator.contains(_groupsQuery);
              }).toList();

        return Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _groupsSearchController,
                decoration: InputDecoration(
                  hintText: tr('Buscar grupos…', 'Search groups…'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _groupsQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: tr('Limpiar', 'Clear'),
                          onPressed: () => _groupsSearchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                ),
              ),
            ),
            // ── Result count hint ──────────────────────────────────────────
            if (_groupsQuery.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(
                      '${filtered.length} resultado(s) de ${groups.length}',
                      '${filtered.length} result(s) of ${groups.length}',
                    ),
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            // ── List ────────────────────────────────────────────────────────
            if (filtered.isEmpty && groups.isNotEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    tr('Sin resultados para "$_groupsQuery".',
                        'No results for "$_groupsQuery".'),
                  ),
                ),
              )
            else if (groups.isEmpty)
              Expanded(
                child: Center(
                  child: Text(tr('No hay grupos activos en el sistema.',
                      'No active groups in the system.')),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: GroupAvatar(group: group, size: 40),
                        title: Text(group.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          tr(
                            '${group.members.length} miembros • Creado por ${group.createdBy.split('@')[0]}',
                            '${group.members.length} members • Created by ${group.createdBy.split('@')[0]}',
                          ),
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                group.code,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_forever_outlined,
                                  color: Colors.red),
                              tooltip: tr('Eliminar Grupo', 'Delete Group'),
                              onPressed: () => widget.onDeleteGroup(group),
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
}

// ─── PIE CHART PAINTER ───────────────────────────────────────────────────────
class _PieChartPainter extends CustomPainter {
  final List<double> slices;
  final List<Color> colors;

  const _PieChartPainter({required this.slices, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final double total = slices.fold(0, (sum, val) => sum + val);
    if (total == 0) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    double startAngle = -3.14159 / 2;

    for (var i = 0; i < slices.length; i++) {
      if (slices[i] <= 0) continue;
      final sweepAngle = (slices[i] / total) * 2 * 3.14159265;
      paint.color = colors[i];
      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width * 0.25, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.colors != colors;
}
