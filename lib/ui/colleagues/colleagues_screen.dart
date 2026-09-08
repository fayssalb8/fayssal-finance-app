import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../data/app_database.dart';
import '../../models/client.dart';
import '../common/name_edit_dialog.dart';

class ColleaguesScreen extends StatefulWidget {
  const ColleaguesScreen({super.key});

  @override
  State<ColleaguesScreen> createState() => _ColleaguesScreenState();
}

class _ColleaguesScreenState extends State<ColleaguesScreen> {
  final _db = AppDatabase.instance;
  List<Colleague> _colleagues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final colleagues = await _db.getColleagues();
    if (!mounted) return;
    setState(() {
      _colleagues = colleagues;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showNameDialog(context, title: 'إضافة زميل جديد');
    if (result == null) return;
    await _db.insertColleague(Colleague(name: result.name));
    _load();
  }

  Future<void> _edit(Colleague colleague) async {
    final result = await showNameDialog(
      context,
      title: 'تعديل الزميل',
      initialValue: colleague.name,
    );
    if (result == null) return;
    await _db.updateColleague(Colleague(id: colleague.id, name: result.name));
    _load();
  }

  Future<void> _delete(Colleague colleague) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الزميل'),
        content: Text('حذف الزميل "${colleague.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteColleague(colleague.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الزملاء')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: 'إضافة زميل',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _colleagues.isEmpty
          ? EmptyStateView(
              icon: Icons.group_outlined,
              title: 'لا يوجد زملاء بعد\nأضف زملاء للمبيعات المشتركة',
              actionLabel: 'إضافة زميل',
              onAction: _add,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _colleagues.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final colleague = _colleagues[i];
                  return AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.group_outlined,
                            color: AppColors.success,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            colleague.name,
                            style: AppTextStyles.listTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _edit(colleague),
                          tooltip: 'تعديل الزميل',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: AppColors.textSecondary,
                        ),
                        IconButton(
                          onPressed: () => _delete(colleague),
                          tooltip: 'حذف الزميل',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: AppColors.danger,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
