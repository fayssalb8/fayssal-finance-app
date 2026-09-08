import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/app_database.dart';
import '../../models/app_settings.dart';
import '../../models/client.dart';
import '../../models/time_record.dart';
import '../../services/import_service.dart';

enum ImportCategory {
  clients('الزبائن', Icons.people_outline),
  overtime('الساعات الإضافية', Icons.timer_outlined),
  absence('الغياب', Icons.event_busy_outlined),
  sales('المبيعات', Icons.local_mall_outlined);

  final String title;
  final IconData icon;
  const ImportCategory(this.title, this.icon);
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _db = AppDatabase.instance;
  late final ImportService _service = ImportService(_db);

  ImportCategory _category = ImportCategory.sales;
  final _textController = TextEditingController();
  AppSettings? _settings;

  bool _loading = false;
  bool _importing = false;

  ImportPreviewResult<dynamic>? _preview;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await _db.getSettings();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  void _onTextChanged() {
    if (_textController.text.trim().isEmpty) {
      if (_preview != null) {
        setState(() => _preview = null);
      }
    } else {
      _runPreview();
    }
  }

  Future<void> _runPreview() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final settings = _settings ?? const AppSettings();
    setState(() => _loading = true);

    try {
      final preview = switch (_category) {
        ImportCategory.clients => await _service.parseClients(text),
        ImportCategory.overtime => _service.parseOvertime(text, settings),
        ImportCategory.absence => _service.parseAbsence(text, settings),
        ImportCategory.sales => await _service.parseSales(text, settings),
      };

      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحافظة فارغة، انسخ بيانات من Excel أولاً')),
      );
      return;
    }

    _textController.text = text;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم لصق البيانات بنجاح')),
    );
  }

  void _clearText() {
    _textController.clear();
    setState(() => _preview = null);
  }

  void _showSampleTemplate() {
    final template = switch (_category) {
      ImportCategory.clients => ImportService.clientsTemplate,
      ImportCategory.overtime => ImportService.overtimeTemplate,
      ImportCategory.absence => ImportService.absenceTemplate,
      ImportCategory.sales => ImportService.salesTemplate,
    };

    final hint = switch (_category) {
      ImportCategory.clients =>
        'الأعمدة: الاسم، رقم الهاتف (يدعم تكرار الزبون لطلبات متعددة)',
      ImportCategory.overtime =>
        'الأعمدة: التاريخ، وقت البداية، وقت النهاية، السعر اليدوي، السبب',
      ImportCategory.absence =>
        'الأعمدة: التاريخ، النوع (ساعات/أيام)، البداية/الأيام، النهاية، السعر اليدوي، السبب',
      ImportCategory.sales =>
        'الأعمدة: التاريخ، اسم الزبون، نوع الطلب (مطبخ/دريسنج/...)، المساحة، نسبة العمولة، الحالة',
    };

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_category.icon, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('نموذج ${_category.title}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hint,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                template,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: template));
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ النموذج التجريبي إلى الحافظة')),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('نسخ النموذج'),
          ),
          FilledButton(
            onPressed: () {
              _textController.text = template;
              Navigator.pop(context);
            },
            child: const Text('استخدام النموذج للتجربة'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeImport() async {
    final preview = _preview;
    if (preview == null || !preview.canImport) return;

    setState(() => _importing = true);

    try {
      int count = 0;
      switch (_category) {
        case ImportCategory.clients:
          final clients = preview.validData.cast<Client>();
          count = await _service.executeImportClients(clients);
        case ImportCategory.overtime:
        case ImportCategory.absence:
          final records = preview.validData.cast<TimeRecord>();
          count = await _service.executeImportTimeRecords(records);
        case ImportCategory.sales:
          final sales = preview.validData.cast<ParsedSaleItem>();
          count = await _service.executeImportSales(sales);
      }

      if (!mounted) return;
      setState(() {
        _importing = false;
        _textController.clear();
        _preview = null;
      });

      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 48),
          title: const Text('اكتمل الاستيراد بنجاح!'),
          content: Text(
            'تم استيراد وحفظ $count سجلاً بنجاح في قاعدة البيانات.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // العودة للشاشة السابقة
              },
              child: const Text('تم'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إكمال الاستيراد، يرجى المحاولة ثانية')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('استيراد البيانات (Excel / CSV)'),
        actions: [
          IconButton(
            tooltip: 'نموذج تجريبي',
            onPressed: _showSampleTemplate,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCategorySelector(),
          const SizedBox(height: 16),
          _buildActionButtons(),
          const SizedBox(height: 12),
          _buildInputCard(),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_preview != null) ...[
            _buildPreviewHeader(),
            const SizedBox(height: 8),
            _buildPreviewList(),
            const SizedBox(height: 20),
            _buildConfirmButton(),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اختر نوع البيانات المراد استيرادها:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ImportCategory>(
            segments: [
              for (final cat in ImportCategory.values)
                ButtonSegment(
                  value: cat,
                  icon: Icon(cat.icon, size: 16),
                  label: Text(cat.title, style: const TextStyle(fontSize: 11)),
                ),
            ],
            selected: {_category},
            onSelectionChanged: (selection) {
              setState(() {
                _category = selection.first;
                _textController.clear();
                _preview = null;
              });
            },
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              selectedBackgroundColor: AppColors.primaryContainer,
              selectedForegroundColor: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pasteFromClipboard,
            icon: const Icon(Icons.paste_outlined, size: 18),
            label: const Text('لصق من Excel'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showSampleTemplate,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('عرض النموذج'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (_textController.text.isNotEmpty) ...[
          const SizedBox(width: 8),
          IconButton.outlined(
            onPressed: _clearText,
            tooltip: 'مسح',
            icon: const Icon(Icons.clear, size: 18),
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInputCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _textController,
        maxLines: 6,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
          hintText: 'الصق صفوف جدول Excel أو نص CSV هنا...\n\n'
              'مثال:\n'
              '${switch (_category) {
                ImportCategory.clients => "سفيان بن علي,0555123456",
                ImportCategory.overtime => "2026-03-10,17:00,19:00,600,تسليم مطبخ",
                ImportCategory.absence => "2026-03-11,ساعات,09:00,12:00,400,موعد",
                ImportCategory.sales => "2026-03-10,فيلا الأبيار,مطبخ,14.5,1.5,مؤكد",
              }}',
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewHeader() {
    final preview = _preview!;
    return Row(
      children: [
        const Icon(Icons.visibility_outlined, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        const Text(
          'معاينة البيانات قبل الاستيراد',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: preview.canImport ? AppColors.successLight : AppColors.dangerLight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${preview.validCount} صالح  •  ${preview.errorCount} به خطأ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: preview.canImport ? AppColors.success : AppColors.danger,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewList() {
    final preview = _preview!;
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: preview.rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = preview.rows[index];
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              row.isValid ? Icons.check_circle : Icons.error_outline,
              color: row.isValid ? AppColors.success : AppColors.danger,
              size: 20,
            ),
            title: Text(
              'السطر ${row.lineNumber}: ${row.rawColumns.join(" | ")}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              row.isValid ? (row.extraInfo ?? 'سليم') : (row.error ?? 'بيانات غير صالحة'),
              style: TextStyle(
                fontSize: 11,
                color: row.isValid ? AppColors.textSecondary : AppColors.danger,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConfirmButton() {
    final preview = _preview!;
    final canSave = preview.canImport && !_importing;

    return FilledButton.icon(
      onPressed: canSave ? _executeImport : null,
      icon: _importing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : const Icon(Icons.download_done_outlined),
      label: Text(
        _importing
            ? 'جارٍ الاستيراد...'
            : 'تأكيد استيراد ${preview.validCount} سجلاً إلى قاعدة البيانات',
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
