import 'package:flutter/material.dart';
import 'package:proyecto_app/home/home_screen.dart';
import 'package:proyecto_app/home/groups_screen.dart';
import 'package:proyecto_app/home/friends_screen.dart';
import 'package:proyecto_app/home/profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:proyecto_app/services/firestore_service.dart';
import 'package:proyecto_app/models/friend_request.dart';
import '../theme/translations.dart';
import 'package:proyecto_app/widgets/profile_onboarding_dialog.dart';
import 'package:flutter/foundation.dart'; // kIsWeb, defaultTargetPlatform
import 'package:proyecto_app/utils/device_type.dart';
import 'package:proyecto_app/auth/auth_service.dart';
import 'package:proyecto_app/main.dart';
import 'package:proyecto_app/home/admin_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  int _currentIndex = 0;
  late Stream<List<FriendRequest>> _pendingRequestsStream;
  late final Stream<int> _groupsBadgeStream;
  bool _isNavRailExtended = false; // Expandable sidebar state
  bool _isAdminRoleInitialized = false;

  String get _currentEmail =>
      FirebaseAuth.instance.currentUser?.email?.toLowerCase() ?? '';

  @override
  void initState() {
    super.initState();
    _pendingRequestsStream = _firestoreService.pendingFriendRequestsStream(_currentEmail);
    _groupsBadgeStream = _firestoreService.totalPendingGroupActionsStream(_currentEmail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOnboarding();
      _checkPendingJoinLink();
    });
  }

  Future<void> _checkPendingJoinLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('pending_join_code');
      if (code != null && code.isNotEmpty) {
        if (mounted) {
          setState(() {
            _currentIndex = 1; // Cambiar a la pestaña de Grupos
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _checkOnboarding() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestoreService.getUserProfile(user.uid);
      if (!doc.exists ||
          (doc.data() as Map<String, dynamic>?)?['displayName'] == null ||
          ((doc.data() as Map<String, dynamic>?)?['displayName'] as String).trim().isEmpty) {
        if (mounted) {
          await showGeneralDialog<bool>(
            context: context,
            barrierDismissible: false,
            barrierLabel: 'Onboarding',
            pageBuilder: (ctx, anim1, anim2) {
              return ProfileOnboardingDialog(user: user, service: _firestoreService);
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking onboarding: $e');
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cerrar Sesión', 'Log Out')),
        content: Text(tr('¿Estás seguro de que deseas cerrar tu sesión?', 'Are you sure you want to log out?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Salir', 'Exit'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('demo_admin_mode', false);
      adminDemoNotifier.value = false;
      await _authService.logout();
    }
  }

  late final List<Widget> _screens = [
    HomeScreen(onSwitchToGroups: () => setState(() => _currentIndex = 1)),
    const GroupsScreen(),
    const FriendsScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestoreService.userProfileStream(user.uid),
      builder: (context, userSnap) {
        final profileData = userSnap.data?.data() as Map<String, dynamic>?;
        final dbRole = profileData?['role'] as String? ?? 'user';
        final isAdminRole = dbRole == 'admin';

        if (userSnap.hasData && !_isAdminRoleInitialized) {
          _isAdminRoleInitialized = true;
          SharedPreferences.getInstance().then((prefs) {
            if (!mounted) return;
            final storedMode = prefs.getBool('demo_admin_mode');
            if (isAdminRole) {
              adminDemoNotifier.value = storedMode ?? true;
            } else {
              adminDemoNotifier.value = storedMode ?? false;
            }
          });
        }

        return ValueListenableBuilder<bool>(
          valueListenable: adminDemoNotifier,
          builder: (context, isAdminDemo, child) {
            final showAdminPanel = isAdminRole && isAdminDemo && kIsWeb;

            if (showAdminPanel) {
              return AdminDashboardScreen(
                onExitAdminMode: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('demo_admin_mode', false);
                  adminDemoNotifier.value = false;
                },
              );
            }

            final colorScheme = Theme.of(context).colorScheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;

            // Detección combinada: OS real + tamaño de ventana
            final deviceType = getDeviceType(context);
            final useRail = deviceType != DeviceType.mobile;

            if (useRail) {
              return Scaffold(
                body: Row(
                  children: [
                    Container(
                      width: _isNavRailExtended ? 256.0 : 80.0,
                      color: isDark ? const Color(0xFF131B2E) : const Color(0xFF003289),
                      child: Column(
                        children: [
                          Expanded(
                            child: NavigationRail(
                              extended: _isNavRailExtended,
                              minWidth: 72.0,
                              minExtendedWidth: 256.0,
                              selectedIndex: _currentIndex,
                              onDestinationSelected: (index) {
                                setState(() => _currentIndex = index);
                              },
                              backgroundColor: Colors.transparent,
                              selectedIconTheme: isDark ? null : const IconThemeData(color: Colors.white),
                              unselectedIconTheme: isDark ? null : const IconThemeData(color: Colors.white70),
                              selectedLabelTextStyle: isDark ? null : const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              unselectedLabelTextStyle: isDark ? null : const TextStyle(color: Colors.white70),
                              indicatorColor: isDark ? null : Colors.white.withValues(alpha: 0.2),
                              leading: Align(
                                alignment: _isNavRailExtended ? Alignment.centerRight : Alignment.center,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                                  child: IconButton(
                                    icon: Icon(
                                      _isNavRailExtended ? Icons.chevron_left : Icons.chevron_right,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isNavRailExtended = !_isNavRailExtended;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              destinations: [
                                NavigationRailDestination(
                                  icon: const Icon(Icons.dashboard_outlined),
                                  selectedIcon: const Icon(Icons.dashboard),
                                  label: Text(tr('Inicio', 'Dashboard')),
                                ),
                                NavigationRailDestination(
                                  icon: StreamBuilder<int>(
                                    stream: _groupsBadgeStream,
                                    builder: (context, snap) {
                                      final count = snap.data ?? 0;
                                      return Badge(
                                        isLabelVisible: count > 0,
                                        label: Text('$count', style: const TextStyle(color: Colors.white)),
                                        backgroundColor: Colors.red,
                                        child: const Icon(Icons.group_outlined),
                                      );
                                    },
                                  ),
                                  selectedIcon: StreamBuilder<int>(
                                    stream: _groupsBadgeStream,
                                    builder: (context, snap) {
                                      final count = snap.data ?? 0;
                                      return Badge(
                                        isLabelVisible: count > 0,
                                        label: Text('$count', style: const TextStyle(color: Colors.white)),
                                        backgroundColor: Colors.red,
                                        child: const Icon(Icons.group),
                                      );
                                    },
                                  ),
                                  label: Text(tr('Grupos', 'Groups')),
                                ),
                                NavigationRailDestination(
                                  icon: StreamBuilder<List<FriendRequest>>(
                                    stream: _pendingRequestsStream,
                                    builder: (context, snap) {
                                      final count = snap.data?.length ?? 0;
                                      return Stack(
                                        children: [
                                          const Icon(Icons.people_outline),
                                          if (count > 0)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: Badge(
                                                label: Text('$count', style: const TextStyle(color: Colors.white)),
                                                backgroundColor: Colors.red,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                  selectedIcon: StreamBuilder<List<FriendRequest>>(
                                    stream: _pendingRequestsStream,
                                    builder: (context, snap) {
                                      final count = snap.data?.length ?? 0;
                                      return Stack(
                                        children: [
                                          const Icon(Icons.people),
                                          if (count > 0)
                                            Positioned(
                                              right: 0,
                                              top: 0,
                                              child: Badge(
                                                label: Text('$count', style: const TextStyle(color: Colors.white)),
                                                backgroundColor: Colors.red,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                  label: Text(tr('Amigos', 'Friends')),
                                ),
                                NavigationRailDestination(
                                  icon: const Icon(Icons.person_outline),
                                  selectedIcon: const Icon(Icons.person),
                                  label: Text(tr('Perfil', 'Profile')),
                                ),
                              ],
                            ),
                          ),
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24.0),
                              child: _isNavRailExtended
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: InkWell(
                                        onTap: () => _confirmLogout(context),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.logout, color: Colors.white),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Text(
                                                  tr('Cerrar sesión', 'Logout'),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.logout, color: Colors.white),
                                      tooltip: tr('Cerrar sesión', 'Logout'),
                                      onPressed: () => _confirmLogout(context),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(thickness: 1, width: 1),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: _screens,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Bottom navigation for mobile
            return Scaffold(
              body: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
              bottomNavigationBar: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF131B2E)
                      : const Color(0xFF003289),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(10),
                      blurRadius: 12,
                      offset: const Offset(0, -4),
                    )
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildNavItem(
                          icon: Icons.dashboard_outlined,
                          activeIcon: Icons.dashboard,
                          label: tr('Inicio', 'Dashboard'),
                          index: 0,
                          colorScheme: colorScheme,
                        ),
                        StreamBuilder<int>(
                          stream: _groupsBadgeStream,
                          builder: (context, snap) {
                            final count = snap.data ?? 0;
                            return _buildNavItem(
                              icon: Icons.group_outlined,
                              activeIcon: Icons.group,
                              label: tr('Grupos', 'Groups'),
                              index: 1,
                              colorScheme: colorScheme,
                              badgeCount: count,
                            );
                          },
                        ),
                        StreamBuilder<List<FriendRequest>>(
                          stream: _pendingRequestsStream,
                          builder: (context, snapshot) {
                            final pendingCount = snapshot.data?.length ?? 0;
                            return _buildNavItem(
                              icon: Icons.people_outline,
                              activeIcon: Icons.people,
                              label: tr('Amigos', 'Friends'),
                              index: 2,
                              colorScheme: colorScheme,
                              badgeCount: pendingCount,
                            );
                          },
                        ),
                        _buildNavItem(
                          icon: Icons.person_outline,
                          activeIcon: Icons.person,
                          label: tr('Perfil', 'Profile'),
                          index: 3,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required ColorScheme colorScheme,
    int badgeCount = 0,
  }) {
    final isActive = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color activeBgColor = isDark
        ? colorScheme.primary
        : Colors.white.withValues(alpha: 0.2);

    final Color activeTextColor = isDark
        ? colorScheme.onPrimary
        : Colors.white;

    final Color inactiveTextColor = isDark
        ? colorScheme.onSurfaceVariant
        : Colors.white70;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badgeCount > 0,
              label: Text('$badgeCount', style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive ? activeTextColor : inactiveTextColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isActive ? activeTextColor : inactiveTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
