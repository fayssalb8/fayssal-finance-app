import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../data/app_database.dart';
import '../../models/client.dart';
import '../common/name_edit_dialog.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _db = AppDatabase.instance;
  List<Client> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final clients = await _db.getClients();
    if (!mounted) return;
    setState(() {
      _clients = clients;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await showNameDialog(
      context,
      title: 'إضافة زبون جديد',
      label: 'اسم الزبون',
      hasPhone: true,
    );
    if (result == null) return;
    await _db.insertClient(Client(name: result.name, phone: result.phone));
    _load();
  }

  Future<void> _edit(Client client) async {
    final result = await showNameDialog(
      context,
      title: 'تعديل الزبون',
      label: 'اسم الزبون',
      initialValue: client.name,
      initialPhone: client.phone,
      hasPhone: true,
    );
    if (result == null) return;
    await _db.updateClient(
      client.copyWith(name: result.name, phone: result.phone),
    );
    _load();
  }

  Future<void> _delete(Client client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الزبون'),
        content: Text('حذف الزبون "${client.name}"؟'),
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
      await _db.deleteClient(client.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        tooltip: 'إضافة زبون',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _clients.isEmpty
          ? EmptyStateView(
              icon: Icons.person_outline,
              title: 'لا يوجد عملاء بعد\nأضف أول زبون لربطه بالمبيعات',
              actionLabel: 'إضافة زبون',
              onAction: _add,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _clients.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final client = _clients[i];
                  return AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.infoLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: AppColors.info,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                client.name,
                                style: AppTextStyles.listTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (client.phone.isNotEmpty)
                                Text(client.phone, style: AppTextStyles.small),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _edit(client),
                          tooltip: 'تعديل الزبون',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: AppColors.textSecondary,
                        ),
                        IconButton(
                          onPressed: () => _delete(client),
                          tooltip: 'حذف الزبون',
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
