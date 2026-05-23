import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/firestore_service.dart';
import '../theme/translations.dart';
import '../widgets/standard_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool notificationsEnabled = true;
  String _selectedLanguage = 'Español';
  String _currentThemeString = 'system';
  bool _isAdminDemo = false;
  bool _isRealAdmin = false;

  final _languages = ['Español', 'English'];
  final _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _loadThemeString();
    _loadAdminDemo();
    _selectedLanguage = languageNotifier.value == 'en' ? 'English' : 'Español';
  }

  Future<void> _loadAdminDemo() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await _firestoreService.getUserProfile(user.uid);
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          final role = data?['role'] as String? ?? 'user';
          if (mounted) {
            setState(() {
              _isRealAdmin = (role == 'admin');
            });
          }
        }
      } catch (e) {
        debugPrint('Error loading user role: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isAdminDemo = prefs.getBool('demo_admin_mode') ?? false;
      });
    }
  }

  Future<void> _loadThemeString() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentThemeString = prefs.getString('theme_mode') ?? 'system';
    });
  }

  void _showPersonalInfoDialog(BuildContext context, User? user) {
    final nameController = TextEditingController(text: user?.displayName ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Información Personal', 'Personal Information')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: tr('Nombre completo', 'Full name'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              enabled: false,
              decoration: InputDecoration(
                labelText: tr('Correo electrónico', 'Email address'),
                prefixIcon: const Icon(Icons.mail_outline),
                helperText: tr('No se puede cambiar el correo aquí.', 'Email cannot be changed here.'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancelar', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(ctx);
              if (name.isEmpty || user == null) return;
              try {
                await user.updateDisplayName(name);
                await _firestoreService.updateUserProfile(
                  uid: user.uid,
                  email: user.email ?? '',
                  displayName: name,
                );
                navigator.pop();
                messenger.showSnackBar(
                  SnackBar(content: Text(tr('Nombre actualizado correctamente.', 'Name updated successfully.'))),
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
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
          title: Text(tr('Privacidad y Seguridad', 'Privacy & Security')),
          content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _privacyItem(
                Icons.lock_outline,
                tr('Contraseña', 'Password'),
                tr('Cambia tu contraseña de acceso', 'Change your access password'),
              ),
              const Divider(),
              _privacyItem(
                Icons.verified_user_outlined,
                tr('Datos cifrados', 'Encrypted data'),
                tr('Todos tus datos están encriptados con AES-256', 'All your data is encrypted with AES-256'),
              ),
              const Divider(),
              _privacyItem(
                Icons.delete_outline,
                tr('Eliminar datos', 'Delete data'),
                tr('Contacta soporte para eliminar tu cuenta', 'Contact support to delete your account'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Aceptar', 'Accept')),
          ),
        ],
      ),
    );
  }

  Widget _privacyItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }



  void _showThemeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StandardDialog(
        title: tr('Tema de la Aplicación', 'Application Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ignore: deprecated_member_use
            RadioListTile<String>(
              value: 'light',
              // ignore: deprecated_member_use
              groupValue: _currentThemeString,
              title: Text(tr('Claro', 'Light')),
              // ignore: deprecated_member_use
              onChanged: _onThemeChanged,
            ),
            // ignore: deprecated_member_use
            RadioListTile<String>(
              value: 'dark',
              // ignore: deprecated_member_use
              groupValue: _currentThemeString,
              title: Text(tr('Oscuro', 'Dark')),
              // ignore: deprecated_member_use
              onChanged: _onThemeChanged,
            ),
            // ignore: deprecated_member_use
            RadioListTile<String>(
              value: 'system',
              // ignore: deprecated_member_use
              groupValue: _currentThemeString,
              title: Text(tr('Automático (Sistema)', 'Automatic (System)')),
              // ignore: deprecated_member_use
              onChanged: _onThemeChanged,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cerrar', 'Close')),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    String tempLanguage = _selectedLanguage;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(tr('Seleccionar Idioma', 'Select Language')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: _languages.map((lang) {
                // ignore: deprecated_member_use
                return RadioListTile<String>(
                  value: lang,
                  // ignore: deprecated_member_use
                  groupValue: tempLanguage,
                  title: Text(lang),
                  // ignore: deprecated_member_use
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tempLanguage = val);
                    }
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Cancelar', 'Cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  setState(() => _selectedLanguage = tempLanguage);
                  Navigator.pop(ctx);
                  final code = _selectedLanguage == 'English' ? 'en' : 'es';
                  await changeLanguage(code);
                },
                child: Text(tr('Aplicar', 'Apply')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onThemeChanged(String? val) async {
    if (val != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', val);
      setState(() => _currentThemeString = val);
      
      if (val == 'light') {
        themeNotifier.value = ThemeMode.light;
      } else if (val == 'dark') {
        themeNotifier.value = ThemeMode.dark;
      } else {
        themeNotifier.value = ThemeMode.system;
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Tema actualizado', 'Theme updated'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Configuración', 'Settings'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── SECCIÓN CUENTA ───────────────────────
              _sectionLabel(tr('Cuenta', 'Account'), colorScheme),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.person_outline, color: colorScheme.onSurface),
                      title: Text(tr('Información Personal', 'Personal Information')),
                      subtitle: Text(
                        user?.displayName?.isNotEmpty == true
                            ? user!.displayName!
                            : (user?.email ?? ''),
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(Icons.chevron_right, color: colorScheme.outlineVariant),
                      onTap: () => _showPersonalInfoDialog(context, user),
                    ),
                    Divider(height: 1, indent: 56, color: colorScheme.outlineVariant.withAlpha(80)),
                    ListTile(
                      leading: Icon(Icons.security, color: colorScheme.onSurface),
                      title: Text(tr('Privacidad y Seguridad', 'Privacy & Security')),
                      trailing: Icon(Icons.chevron_right, color: colorScheme.outlineVariant),
                      onTap: () => _showPrivacyDialog(context),
                    ),
                    if (_isRealAdmin) ...[
                      Divider(height: 1, indent: 56, color: colorScheme.outlineVariant.withAlpha(80)),
                      SwitchListTile(
                        secondary: Icon(Icons.admin_panel_settings, color: colorScheme.onSurface),
                        title: Text(tr('Modo Administrador (Demo)', 'Admin Mode (Demo)')),
                        subtitle: Text(
                          _isAdminDemo ? tr('Activado', 'Enabled') : tr('Desactivado', 'Disabled'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _isAdminDemo ? colorScheme.primary : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: _isAdminDemo,
                        activeThumbColor: colorScheme.primary,
                        onChanged: (val) async {
                          final messenger = ScaffoldMessenger.of(context);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('demo_admin_mode', val);
                          adminDemoNotifier.value = val;
                          setState(() {
                            _isAdminDemo = val;
                          });
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                val
                                    ? tr('Modo Administrador activado.', 'Admin Mode enabled.')
                                    : tr('Modo Administrador desactivado.', 'Admin Mode disabled.'),
                              ),
                              duration: const Duration(milliseconds: 800),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ─── SECCIÓN NOTIFICACIONES ───────────────
              _sectionLabel(tr('Notificaciones', 'Notifications'), colorScheme),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: SwitchListTile(
                  secondary: Icon(
                    notificationsEnabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(tr('Notificaciones Push', 'Push Notifications')),
                  subtitle: Text(
                    notificationsEnabled ? tr('Activadas', 'Enabled') : tr('Desactivadas', 'Disabled'),
                    style: TextStyle(
                      fontSize: 12,
                      color: notificationsEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: notificationsEnabled,
                  activeThumbColor: colorScheme.primary,
                  onChanged: (val) {
                    setState(() => notificationsEnabled = val);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          val
                              ? tr('Notificaciones activadas', 'Notifications enabled')
                              : tr('Notificaciones desactivadas', 'Notifications disabled'),
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // ─── SECCIÓN SISTEMA ──────────────────────
              _sectionLabel(tr('Sistema', 'System'), colorScheme),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        _currentThemeString == 'dark'
                            ? Icons.dark_mode
                            : _currentThemeString == 'light'
                                ? Icons.light_mode_outlined
                                : Icons.brightness_auto,
                        color: colorScheme.onSurface,
                      ),
                      title: Text(tr('Tema', 'Theme')),
                      subtitle: Text(
                        _currentThemeString == 'dark'
                            ? tr('Oscuro', 'Dark')
                            : _currentThemeString == 'light'
                                ? tr('Claro', 'Light')
                                : tr('Automático', 'Automatic'),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right, color: colorScheme.outlineVariant),
                      onTap: () => _showThemeDialog(context),
                    ),
                    Divider(height: 1, indent: 56, color: colorScheme.outlineVariant.withAlpha(80)),
                    ListTile(
                      leading: Icon(Icons.language, color: colorScheme.onSurface),
                      title: Text(tr('Idioma', 'Language')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_selectedLanguage, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: colorScheme.outlineVariant),
                        ],
                      ),
                      onTap: () => _showLanguageDialog(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ─── SECCIÓN ACERCA DE ────────────────────
              _sectionLabel(tr('Acerca de', 'About'), colorScheme),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.info_outline, color: colorScheme.onSurface),
     
                title: Text(tr('Versión de la App', 'App Version')),
                      trailing: Text('1.0.0', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                    ),
                    Divider(height: 1, indent: 56, color: colorScheme.outlineVariant.withAlpha(80)),
                    ListTile(
                      leading: Icon(Icons.description_outlined, color: colorScheme.onSurface),
                      title: Text(tr('Términos y Condiciones', 'Terms & Conditions')),
                      trailing: Icon(Icons.chevron_right, color: colorScheme.outlineVariant),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: Text(tr('Términos y Condiciones', 'Terms & Conditions')),
                              content: SingleChildScrollView(
                                child: Text(
                                  tr(
                                    'SmartBudget es una aplicación para gestión de gastos compartidos. '
                                    'Al usar esta aplicación, aceptas que tus datos serán almacenados '
                                    'de forma segura en Firebase con cifrado en tránsito.\n\n'
                                    'No compartimos tu información con terceros.\n\n'
                                    'Puedes eliminar tu cuenta y datos en cualquier momento contactando a soporte.',
                                    'SmartBudget is a shared expense management application. '
                                    'By using this app, you agree that your data will be stored '
                                    'securely on Firebase with in-transit encryption.\n\n'
                                    'We do not share your information with third parties.\n\n'
                                    'You can delete your account and data at any time by contacting support.',
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(tr('Aceptar', 'Accept')),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, ColorScheme colorScheme) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }
}
