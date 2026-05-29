import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmailService {
  // Configuración de EmailJS (Crea una cuenta gratis en EmailJS.com)
  // No requiere tarjeta de crédito y te da 200 envíos mensuales gratis.
  static const String _serviceId = 'service_3vtk2yi';
  static const String _templateId = 'template_d8gzoji';
  static const String _publicKey = 'f_Jx2zFRzu4mxVsxA';

  static Future<void> sendGroupInvitation({
    required String toEmail,
    required String groupName,
    required String fromName,
    required String groupCode,
    required String webAppBaseUrl,
    int memberCount = 0,
    double? initialBudget,
    int expenseCount = 0,
    double totalExpenses = 0.0,
  }) async {
    // Si la URL base es local o vacía, usamos el hosting por defecto
    final baseUrl =
        webAppBaseUrl.contains('localhost') ||
            webAppBaseUrl.contains('127.0.0.1')
        ? 'https://smartbudget-88efb.web.app'
        : webAppBaseUrl;

    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final joinUrl = '$cleanBaseUrl/?code=$groupCode';

    // API de EmailJS para envío de correos
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'to_email': toEmail.trim().toLowerCase(),
            'from_name': fromName,
            'name': fromName, // Para resolver {{name}} en tu plantilla
            'email': toEmail.trim().toLowerCase(), // Para resolver {{email}} en tu plantilla
            'group_name': groupName,
            'group_code': groupCode,
            'join_url': joinUrl,
            'member_count': memberCount,
            'initial_budget': initialBudget != null ? '\$${initialBudget.toStringAsFixed(2)}' : 'No definido',
            'expense_count': expenseCount,
            'total_expenses': '\$${totalExpenses.toStringAsFixed(2)}',
          },
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'EmailService (EmailJS) Error: ${response.statusCode} - ${response.body}',
        );
      } else {
        debugPrint(
          'EmailService (EmailJS): Correo enviado exitosamente a $toEmail',
        );
      }
    } catch (e) {
      debugPrint('EmailService Exception: $e');
    }
  }
}
