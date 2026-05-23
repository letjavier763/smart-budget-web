import 'package:flutter/material.dart';
// import 'package:proyecto_app/theme/translations.dart'; // Removed unused import

class StandardDialog extends StatelessWidget {
  final String title;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollable;

  const StandardDialog({
    super.key,
    required this.title,
    this.content,
    required this.actions,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Determine max width: full width on small screens (mobile), limited on larger screens (web)
    final screenWidth = MediaQuery.of(context).size.width;
    final maxDialogWidth = screenWidth < 600 ? double.infinity : 500.0;
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: colorScheme.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 280, minHeight: 100, maxWidth: maxDialogWidth),
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (content != null)
                  scrollable ? SingleChildScrollView(child: content) : content!,
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
