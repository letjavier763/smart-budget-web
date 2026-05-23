import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/group.dart';

String _normalizeString(String input) {
  var text = input.toLowerCase().trim();
  const Map<String, String> accentMap = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
    'ü': 'u', 'ñ': 'n',
    'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
    'â': 'a', 'ê': 'e', 'î': 'i', 'ô': 'o', 'û': 'u',
    'ä': 'a', 'ë': 'e', 'ï': 'i', 'ö': 'o',
  };
  accentMap.forEach((key, value) {
    text = text.replaceAll(key, value);
  });
  return text;
}

String? getBrandAssetPath(String groupName) {
  final name = _normalizeString(groupName);
  if (name.contains('netflix')) return 'assets/brand_logos/netflix.png';
  if (name.contains('spotify')) return 'assets/brand_logos/spotify.png';
  if (name.contains('disney')) return 'assets/brand_logos/disney.png';
  if (name.contains('hbo') || name.contains('max')) return 'assets/brand_logos/hbo_max.png';
  if (name.contains('youtube')) return 'assets/brand_logos/youtube.png';
  if (name.contains('prime')) return 'assets/brand_logos/prime.png';
  if (name.contains('nintendo')) return 'assets/brand_logos/nintendo.png';
  if (name.contains('xbox')) return 'assets/brand_logos/xbox.png';
  if (name.contains('playstation') || name.contains('ps5') || name.contains('ps4')) {
    return 'assets/brand_logos/playstation.png';
  }
  if (name.contains('apple')) return 'assets/brand_logos/apple.png';
  return null;
}

Color getBrandBgColor(String assetPath, BuildContext context, bool isDark) {
  if (assetPath.contains('apple')) {
    return isDark ? Colors.white : const Color(0xFFF5F5F7);
  }
  if (assetPath.contains('netflix')) {
    return const Color(0xFF141414);
  }
  if (assetPath.contains('spotify')) {
    return const Color(0xFF121212);
  }
  if (assetPath.contains('disney')) {
    return const Color(0xFF040B24);
  }
  if (assetPath.contains('hbo_max')) {
    return const Color(0xFF000B26);
  }
  if (assetPath.contains('playstation')) {
    return const Color(0xFF0037AE);
  }
  if (assetPath.contains('xbox')) {
    return const Color(0xFF052B05);
  }
  if (assetPath.contains('nintendo')) {
    return const Color(0xFFE60012);
  }
  return isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
}

class GroupBrandStyle {
  final IconData icon;
  final List<Color> gradientColors;
  final Color iconColor;

  const GroupBrandStyle({
    required this.icon,
    required this.gradientColors,
    this.iconColor = Colors.white,
  });
}

GroupBrandStyle? getGroupBrandStyle(String groupName) {
  final name = _normalizeString(groupName);

  // Utilities & Housing (Casa, Agua, Luz, Renta, etc.)
  if (name.contains('casa') || name.contains('hogar') || name.contains('apartamento') || name.contains('depto')) {
    return const GroupBrandStyle(
      icon: Icons.home_outlined,
      gradientColors: [Color(0xFFFF9800), Color(0xFFE65100)],
    );
  }
  if (name.contains('agua')) {
    return const GroupBrandStyle(
      icon: Icons.water_drop_outlined,
      gradientColors: [Color(0xFF03A9F4), Color(0xFF01579B)],
    );
  }
  if (name.contains('electricidad') || name.contains('luz') || name.contains('energia') || name.contains('electric')) {
    return const GroupBrandStyle(
      icon: Icons.bolt,
      gradientColors: [Color(0xFFFFEB3B), Color(0xFFF57F17)],
    );
  }
  if (name.contains('renta') || name.contains('alquiler') || name.contains('arriendo') || name.contains('centa') || name.contains('cuarto')) {
    return const GroupBrandStyle(
      icon: Icons.key_outlined,
      gradientColors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
    );
  }
  if (name.contains('comida') || name.contains('super') || name.contains('despensa') || name.contains('mercado') || name.contains('restaurante')) {
    return const GroupBrandStyle(
      icon: Icons.restaurant_outlined,
      gradientColors: [Color(0xFFEC407A), Color(0xFF880E4F)],
    );
  }
  if (name.contains('internet') || name.contains('wifi') || name.contains('fibra')) {
    return const GroupBrandStyle(
      icon: Icons.wifi,
      gradientColors: [Color(0xFF00BCD4), Color(0xFF006064)],
    );
  }
  if (name.contains('viaje') || name.contains('gasolina') || name.contains('transporte') || name.contains('gas') || name.contains('carro') || name.contains('auto')) {
    return const GroupBrandStyle(
      icon: Icons.local_gas_station_outlined,
      gradientColors: [Color(0xFF9C27B0), Color(0xFF4A148C)],
    );
  }

  return null;
}

class GroupAvatar extends StatelessWidget {
  final GroupModel group;
  final double size;

  const GroupAvatar({
    super.key,
    required this.group,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final brandAsset = getBrandAssetPath(group.name);
    final brandStyle = getGroupBrandStyle(group.name);
    final customImageBase64 = group.imageUrl;

    Widget? avatarContent;
    BoxDecoration containerDecoration;

    if (customImageBase64 != null && customImageBase64.isNotEmpty) {
      try {
        avatarContent = Image.memory(
          base64Decode(customImageBase64),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
      } catch (_) {}
    }

    if (avatarContent != null) {
      containerDecoration = BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      );
    } else if (brandAsset != null) {
      // Official commercial brand logo rendered from local assets
      containerDecoration = BoxDecoration(
        color: getBrandBgColor(brandAsset, context, isDark),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      );
      avatarContent = Padding(
        padding: EdgeInsets.all(size * 0.15), // Elegant inner padding to fit the logo beautifully
        child: Image.asset(
          brandAsset,
          fit: BoxFit.contain,
        ),
      );
    } else if (brandStyle != null) {
      // App-styled utilities/categories (Casa, Agua, Luz, Renta, etc.)
      containerDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: brandStyle.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: brandStyle.gradientColors.first.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      );
      avatarContent = Icon(
        brandStyle.icon,
        color: brandStyle.iconColor,
        size: size * 0.55,
      );
    } else {
      // Fallback premium default gradient using theme colors
      final startColor = theme.colorScheme.primaryContainer;
      final endColor = theme.colorScheme.secondaryContainer;
      containerDecoration = BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      );
      avatarContent = Center(
        child: Text(
          group.name.isNotEmpty ? group.name.substring(0, 1).toUpperCase() : '?',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: containerDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: avatarContent,
      ),
    );
  }
}
