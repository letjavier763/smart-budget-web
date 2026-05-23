import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/translations.dart';
import 'activity_screen.dart';
import 'payments_screen.dart';
import 'settings_screen.dart';


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final authService = AuthService();
  final _firestoreService = FirestoreService();
  String? _photoUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await _firestoreService.getUserProfile(user.uid);
      if (doc.exists && mounted) {
        setState(() {
          _photoUrl = (doc.data() as Map<String, dynamic>)['photoUrl'];
        });
      }
    }
  }

  Future<void> _uploadProfilePicture(BuildContext context, User user) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 50, // Comprimir más para que quepa bien en Firestore
      maxWidth: 400,
      maxHeight: 400,
    );

    if (pickedFile == null) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    messenger.showSnackBar(SnackBar(content: Text(tr('Procesando imagen...', 'Processing image...'))));

    try {
      final bytes = await pickedFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      await _firestoreService.updateUserProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        photoUrl: base64Image,
      );

      if (!mounted) return;
      setState(() {
        _photoUrl = base64Image;
        _isLoading = false;
      });
      messenger.showSnackBar(SnackBar(content: Text(tr('Imagen actualizada correctamente.', 'Image updated successfully.'))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(SnackBar(content: Text('${tr('Error al guardar imagen', 'Error saving image')}: $e')));
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
      )
    );

    if (confirmed == true) {
      await authService.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(tr('Mi Perfil', 'My Profile'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Profile Header with Gradient
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                top: 120,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: user != null ? () => _uploadProfilePicture(context, user) : null,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 46,
                          backgroundColor: colorScheme.surface,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: colorScheme.primaryContainer,
                            backgroundImage: _photoUrl != null 
                                ? MemoryImage(base64Decode(_photoUrl!)) 
                                : null,
                            child: _photoUrl == null ? (_isLoading 
                              ? const CircularProgressIndicator()
                              : Text(
                              (user?.displayName?.isNotEmpty == true
                                      ? user!.displayName!
                                      : (user?.email ?? 'U'))
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 28,
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            )) : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.secondary,
                              shape: BoxShape.circle,
                              border: Border.all(color: colorScheme.surface, width: 2),
                            ),
                            child: Icon(Icons.camera_alt, size: 14, color: colorScheme.onSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 42),
          Text(
            user?.displayName?.isNotEmpty == true ? user!.displayName! : (user?.email?.split('@')[0] ?? tr('Usuario', 'User')),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            user?.email ?? tr('No email', 'No email'),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // Actions List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                _buildProfileListTile(
                  context,
                  icon: Icons.payments_outlined,
                  title: tr('Mis Pagos', 'My Payments'),
                  iconColor: colorScheme.primary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PaymentsScreen()),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildProfileListTile(
                  context,
                  icon: Icons.history,
                  title: tr('Historial de Actividad', 'Activity History'),
                  iconColor: colorScheme.tertiary,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ActivityScreen()),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _buildProfileListTile(
                  context,
                  icon: Icons.settings_outlined,
                  title: tr('Configuración', 'Settings'),
                  iconColor: colorScheme.secondary,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  },
                ),
                const SizedBox(height: 8),
                _buildProfileListTile(
                  context,
                  icon: Icons.logout,
                  title: tr('Cerrar Sesión', 'Log Out'),
                  iconColor: colorScheme.error,
                  textColor: colorScheme.error,
                  hideArrow: true,
                  onTap: () => _confirmLogout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color iconColor,
    Color? textColor,
    bool hideArrow = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: textColor ?? theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (!hideArrow) Icon(Icons.chevron_right, color: theme.colorScheme.outlineVariant, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
