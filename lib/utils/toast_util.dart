import 'package:flutter/material.dart';

class ToastUtil {
  static void showToast(String message, {BuildContext? context}) {
    if (context != null) {
      // Use SnackBar if context is provided
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Just print to console if no context
      debugPrint('Toast message (no context): $message');
    }
  }
  
  // Helper for showing a more advanced SnackBar
  static void showSnackBar({
    required BuildContext context,
    required String message,
    Color backgroundColor = Colors.black87,
    Color textColor = Colors.white,
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: textColor),
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
} 