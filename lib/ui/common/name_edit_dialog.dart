import 'package:flutter/material.dart';

/// نتيجة نافذة إدخال/تعديل اسم (زبون / زميل).
class NameDialogResult {
  final String name;
  final String phone;

  const NameDialogResult({required this.name, this.phone = ''});
}

/// نافذة منبثقة لإدخال أو تعديل اسم، مع رقم هاتف اختياري.
Future<NameDialogResult?> showNameDialog(
  BuildContext context, {
  required String title,
  String label = 'الاسم',
  String? initialValue,
  String? initialPhone,
  bool hasPhone = false,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  final phoneController = TextEditingController(text: initialPhone ?? '');
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<NameDialogResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: label),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
            ),
            if (hasPhone) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (اختياري)',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              NameDialogResult(
                name: controller.text.trim(),
                phone: hasPhone ? phoneController.text.trim() : '',
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );

  controller.dispose();
  phoneController.dispose();
  return result;
}
