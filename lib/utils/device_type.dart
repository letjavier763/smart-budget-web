import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tipo de dispositivo detectado por la combinación de:
///   1. `defaultTargetPlatform` → OS real del navegador (Android / iOS / desktop)
///   2. `MediaQuery.size.width`  → tamaño real de la ventana/pantalla
///
/// Umbrales:
///   mobile  < 600 px  o  OS móvil (Android / iOS)
///   tablet  600–1099 px  en OS de escritorio
///   desktop ≥ 1100 px  en OS de escritorio
enum DeviceType { mobile, tablet, desktop }

DeviceType getDeviceType(BuildContext context) {
  final width = MediaQuery.of(context).size.width;

  // Detecta si el OS real es Android o iOS (incluye navegadores móviles)
  final isMobileOS = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // Un OS móvil O pantalla pequeña → interfaz móvil
  if (isMobileOS || width < 600) return DeviceType.mobile;

  // Pantalla mediana en OS de escritorio → tablet / ventana pequeña
  if (width < 1100) return DeviceType.tablet;

  // Pantalla grande en OS de escritorio → desktop completo
  return DeviceType.desktop;
}

/// Helpers de conveniencia
bool isMobile(BuildContext context) =>
    getDeviceType(context) == DeviceType.mobile;

bool isTablet(BuildContext context) =>
    getDeviceType(context) == DeviceType.tablet;

bool isDesktop(BuildContext context) =>
    getDeviceType(context) == DeviceType.desktop;

/// True si el dispositivo tiene pantalla grande (tablet o desktop)
bool isWideScreen(BuildContext context) =>
    getDeviceType(context) != DeviceType.mobile;
