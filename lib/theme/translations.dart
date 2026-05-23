import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ValueNotifier<String> languageNotifier = ValueNotifier('es');

String tr(String es, String en) {
  return languageNotifier.value == 'en' ? en : es;
}

Future<void> loadLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  languageNotifier.value = prefs.getString('language_code') ?? 'es';
}

Future<void> changeLanguage(String lang) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('language_code', lang);
  languageNotifier.value = lang;
}

String translateCategory(String category) {
  switch (category) {
    case 'Comida':
      return tr('Comida', 'Food');
    case 'Alquiler':
      return tr('Alquiler', 'Rent');
    case 'Servicios':
      return tr('Servicios', 'Services');
    case 'Actividades':
      return tr('Actividades', 'Activities');
    case 'Transporte':
      return tr('Transporte', 'Transport');
    case 'Otros':
    default:
      return tr('Otros', 'Others');
  }
}

