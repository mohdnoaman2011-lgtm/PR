import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBlue = Color(0xFF2563EB);
const kInk = Color(0xFF0F172A);

/// تحويل الأرقام إلى الهندية (٠١٢٣…)
String ar(num n) => n.toString().replaceAllMapped(
    RegExp(r'\d'), (m) => String.fromCharCode(0x0660 + int.parse(m[0]!)));

String whenText(DateTime d) {
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  return 'قبل ${ar(days)} أيام';
}

// ───────────────────────── النموذج ─────────────────────────

class PrintJob {
  final String name;
  final Uint8List bytes;
  final bool isPdf;
  final String? path;
  int pages = 1;
  Uint8List? preview;
  PrintJob(this.name, this.bytes, this.isPdf, this.path);

  /// يستخرج معاينة الصفحة الأولى وعدد الصفحات.
  Future<void> prepare() async {
    if (!isPdf) {
      preview = bytes;
      return;
    }
    var n = 0;
    try {
      await for (final r in Printing.raster(bytes, dpi: 72)) {
        if (n == 0) preview = await r.toPng();
        n++;
      }
    } catch (_) {}
    pages = n == 0 ? 1 : n;
  }
}

class HistoryEntry {
  final String name, printer;
  final String? path;
  final DateTime date;
  HistoryEntry(this.name, this.path, this.date, this.printer);

  Map<String, dynamic> toJson() => {'n': name, 'p': path, 'd': date.toIso8601String(), 'pr': printer};
  factory HistoryEntry.fromJson(Map<String, dynamic> j) =>
      HistoryEntry(j['n'], j['p'], DateTime.parse(j['d']), j['pr'] ?? '');
}

class PrintModel extends ChangeNotifier {
  PrintJob? job;
  int copies = 1;
  bool color = true;
  String paper = 'A4';
  bool canList = false;
  List<Printer> printers = [];
  Printer? selected;
  List<HistoryEntry> history = [];
  SharedPreferences? _prefs;

  PdfPageFormat get format => paper == 'A4' ? PdfPageFormat.a4 : PdfPageFormat.letter;

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    paper = _prefs!.getString('paper') ?? 'A4';
    themeMode.value = (_prefs!.getBool('dark') ?? false) ? ThemeMode.dark : ThemeMode.light;
    try {
      history = (_prefs!.getStringList('history') ?? [])
          .map((s) => HistoryEntry.fromJson(jsonDecode(s)))
          .toList();
    } catch (_) {}
    await loadPrinters();
  }

  Future<void> loadPrinters() async {
    try {
      final info = await Printing.info();
      canList = info.canListPrinters;
      printers = canList ? await Printing.listPrinters() : [];
      if (selected != null && !printers.any((p) => p.url == selected!.url)) selected = null;
      selected ??= printers.isEmpty
          ? null
          : printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);
    } catch (_) {
      canList = false;
    }
    notifyListeners();
  }

  Future<void> setPaper(String p) async {
    update(() => paper = p);
    await _prefs?.setString('paper', p);
  }

  Future<void> setDark(bool v) async {
    themeMode.value = v ? ThemeMode.dark : ThemeMode.light;
    await _prefs?.setBool('dark', v);
  }

  Future<void> _saveHistory() => _prefs?.setStringList(
          'history', history.map((e) => jsonEncode(e.toJson())).toList()) ??
      Future.value(false);

  Future<void> addHistory(PrintJob j, String printer) async {
    history.insert(0, HistoryEntry(j.name, j.path, DateTime.now(), printer));
    if (history.length > 50) {
      for (final old in history.sublist(50)) {
        _deleteFile(old.path);
      }
      history = history.sublist(0, 50);
    }
    notifyListeners();
    await _saveHistory();
  }

  void _deleteFile(String? p) {
    if (p == null) return;
    try {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    for (final e in history) {
      _deleteFile(e.path);
    }
    history = [];
    notifyListeners();
    await _saveHistory();
  }

  String get printerLabel => (canList && selected != null) ? selected!.name : 'نافذة الطباعة في النظام';
}

final model = PrintModel();
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

// ───────────────────────── الطباعة الفعلية ─────────────────────────

Uint8List _gray(Uint8List b) {
  final d = img.decodeImage(b);
  if (d == null) return b;
  return Uint8List.fromList(img.encodePng(img.grayscale(d)));
}

/// يبني ملف PDF النهائي حسب الإعدادات (عدد النسخ، الألوان، الورق).
Future<Uint8List> buildPdf(PrintJob job, PdfPageFormat fmt) async {
  // بدون أي تعديل: نرسل الـ PDF الأصلي بجودته الكاملة.
  if (job.isPdf && model.copies == 1 && model.color) return job.bytes;

  final pngs = <Uint8List>[];
  if (job.isPdf) {
    await for (final r in Printing.raster(job.bytes, dpi: 200)) {
      pngs.add(await r.toPng());
    }
  } else {
    pngs.add(job.bytes);
  }
  final pages = model.color ? pngs : [for (final p in pngs) await compute(_gray, p)];

  final doc = pw.Document();
  for (var c = 0; c < model.copies; c++) {
    for (final p in pages) {
      final image = pw.MemoryImage(p);
      doc.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ));
    }
  }
  return doc.save();
}

/// يفتح نافذة الطباعة (أو يطبع مباشرة على الطابعة المحددة في أنظمة سطح المكتب).
Future<bool> doPrint() async {
  final job = model.job!;
  if (model.canList && model.selected != null) {
    return Printing.directPrintPdf(
      printer: model.selected!,
      onLayout: (f) => buildPdf(job, f),
      format: model.format,
      name: job.name,
    );
  }
  return Printing.layoutPdf(
    onLayout: (f) => buildPdf(job, f),
    format: model.format,
    name: job.name,
  );
}

// ───────────────────────── اختيار الملفات ─────────────────────────

Future<T> withLoading<T>(BuildContext context, Future<T> Function() task) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

void snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

const _docGroup = XTypeGroup(
  label: 'مستندات',
  extensions: ['pdf', 'jpg', 'jpeg', 'png'],
  mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
  uniformTypeIdentifiers: ['com.adobe.pdf', 'public.jpeg', 'public.png'],
);

const _imageGroup = XTypeGroup(
  label: 'صور',
  extensions: ['jpg', 'jpeg', 'png'],
  mimeTypes: ['image/jpeg', 'image/png'],
  uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
);

/// ينسخ الملف إلى مجلد التطبيق ليبقى متاحاً لإعادة الطباعة من السجل.
Future<String> _store(String name, Uint8List bytes) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/files');
  await dir.create(recursive: true);
  final f = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}

Future<void> pickAndOpen(BuildContext context, {bool images = false}) async {
  final f = await openFile(acceptedTypeGroups: [images ? _imageGroup : _docGroup]);
  if (f == null) return;
  final bytes = await f.readAsBytes();
  if (!context.mounted) return;
  await openJob(context, f.name, bytes, null);
}

Future<void> reopen(BuildContext context, HistoryEntry e) async {
  final p = e.path;
  if (p == null || !await File(p).exists()) {
    if (context.mounted) snack(context, 'الملف لم يعد موجوداً على الهاتف');
    return;
  }
  final bytes = await File(p).readAsBytes();
  if (!context.mounted) return;
  await openJob(context, e.name, bytes, p);
}

Future<void> openJob(BuildContext context, String name, Uint8List bytes, String? path) async {
  final ext = name.toLowerCase().split('.').last;
  final isPdf = ext == 'pdf';
  if (!isPdf && !['jpg', 'jpeg', 'png'].contains(ext)) {
    snack(context, 'نوع الملف غير مدعوم. استخدم PDF أو صورة JPG/PNG (صدّر مستند Word إلى PDF أولاً).');
    return;
  }
  final stored = path ?? await _store(name, bytes);
  final job = PrintJob(name, bytes, isPdf, stored);
  await withLoading(context, job.prepare);
  model.update(() => model.job = job);
  if (!context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintSettingsScreen()));
}

// ───────────────────────── التطبيق ─────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await model.init();
  runApp(const PrintApp());
}

class PrintApp extends StatelessWidget {
  const PrintApp({super.key});

  ThemeData _theme(Brightness b) {
    final base = ThemeData(
      brightness: b,
      colorScheme: ColorScheme.fromSeed(seedColor: kBlue, brightness: b),
      useMaterial3: true,
    );
    return base.copyWith(
      scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF4F6FB) : null,
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'طباعتي',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        locale: const Locale('ar'),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const SplashScreen(),
      ),
    );
  }
}

// ───────────────────────── عناصر مشتركة ─────────────────────────

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? bg, fg;
  const IconTile(this.icon, {super.key, this.bg, this.fg});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: bg ?? const Color(0xFFE8EFFE), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: fg ?? const Color(0xFF1D4ED8)),
      );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  const AppCard({super.key, required this.child, this.onTap, this.selected = false});

  @override
  Widget build(BuildContext context) => Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? kBlue : Colors.transparent, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: child)),
      );
}

class Item extends StatelessWidget {
  final Widget leading;
  final String title, subtitle;
  final Widget? trailing;
  const Item(this.leading, this.title, this.subtitle, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      leading,
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 13)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class Heading extends StatelessWidget {
  final String title, sub;
  const Heading(this.title, this.sub, {super.key});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}

Widget fileBadge(String name) {
  final pdf = name.toLowerCase().endsWith('.pdf');
  return Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: pdf ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(pdf ? 'PDF' : 'IMG',
        style: TextStyle(color: pdf ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8), fontWeight: FontWeight.w800, fontSize: 12)),
  );
}

// ───────────────────────── شاشة البداية ─────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), _go);
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kInk,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: kBlue,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: kBlue.withValues(alpha: .45), blurRadius: 32, offset: const Offset(0, 12))],
                ),
                child: const Icon(Icons.print_rounded, size: 56, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text('طباعتي', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)),
              const Text('اطبع من هاتفك إلى أي طابعة', style: TextStyle(color: Color(0xFFCBD5E1))),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(onPressed: _go, child: const Text('ابدأ الآن', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              ),
              const SizedBox(height: 12),
              Text('الإصدار ${ar(1)}.${ar(0)}.${ar(0)}', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
            ]),
          ),
        ),
      );
}

// ───────────────────────── الهيكل ─────────────────────────

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeTab(onOpenPrinters: () => setState(() => _index = 1)),
      const PrintersTab(),
      const HistoryTab(),
      const SettingsTab(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: tabs)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.print_outlined), selectedIcon: Icon(Icons.print), label: 'الطابعات'),
          NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// ───────────────────────── الرئيسية ─────────────────────────

class HomeTab extends StatelessWidget {
  final VoidCallback onOpenPrinters;
  const HomeTab({super.key, required this.onOpenPrinters});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final seen = <String>{};
        final recent = model.history.where((e) => seen.add(e.name)).take(3).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Heading('طباعة', 'أهلاً، ماذا تريد أن تطبع اليوم؟'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(24)),
              child: Column(children: [
                InkWell(
                  onTap: onOpenPrinters,
                  child: Row(children: [
                    const IconTile(Icons.print_rounded, bg: Color(0xFF1E293B), fg: Color(0xFF93B4F8)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(model.printerLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        const Text('اختر الطابعة عند الطباعة', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                      ]),
                    ),
                    const CircleAvatar(radius: 5, backgroundColor: Color(0xFF22C55E)),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: () => pickAndOpen(context),
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('اختيار مستند للطباعة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _quick(context, Icons.picture_as_pdf_outlined, 'ملفات PDF', false)),
              const SizedBox(width: 12),
              Expanded(child: _quick(context, Icons.image_outlined, 'صور من المعرض', true)),
            ]),
            const SizedBox(height: 20),
            const Text('الملفات الأخيرة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              Text('لا توجد ملفات بعد. اختر مستنداً لتبدأ.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            for (final e in recent) ...[
              AppCard(
                onTap: () => reopen(context, e),
                child: Item(fileBadge(e.name), e.name, whenText(e.date), trailing: const Icon(Icons.chevron_left)),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 4),
            Text('يدعم التطبيق PDF وصور JPG/PNG. لطباعة مستند Word صدّره إلى PDF أولاً.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        );
      },
    );
  }

  Widget _quick(BuildContext context, IconData icon, String label, bool images) => AppCard(
        onTap: () => pickAndOpen(context, images: images),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(icon),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      );
}

// ───────────────────────── الطابعات ─────────────────────────

class PrintersTab extends StatelessWidget {
  const PrintersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Heading('الطابعات', model.canList ? 'تم العثور على ${ar(model.printers.length)} طابعات' : 'الطباعة عبر نظام الهاتف'),
          const SizedBox(height: 16),
          if (!model.canList)
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [IconTile(Icons.print), SizedBox(width: 12), Expanded(child: Text('اختيار الطابعة يتم عند الطباعة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)))]),
                const SizedBox(height: 10),
                Text(
                  'على الهاتف تظهر نافذة الطباعة الخاصة بالنظام عند الضغط على «طباعة»، وتعرض كل الطابعات المتاحة (Wi‑Fi، بلوتوث، USB، Mopria/AirPrint) ويمكنك الاختيار منها هناك.\n\n'
                  'لإضافة طابعة جديدة: فعّل خدمة الطباعة المناسبة من إعدادات الهاتف (الاتصال ← الطباعة) أو من متجر التطبيقات.',
                  style: TextStyle(color: muted, height: 1.6),
                ),
              ]),
            ),
          for (final p in model.printers) ...[
            AppCard(
              selected: model.selected?.url == p.url,
              onTap: () => model.update(() => model.selected = p),
              child: Item(
                const IconTile(Icons.print),
                p.name,
                p.model ?? p.location ?? p.url,
                trailing: model.selected?.url == p.url
                    ? const CircleAvatar(radius: 13, backgroundColor: kBlue, child: Icon(Icons.check, size: 16, color: Colors.white))
                    : const Icon(Icons.circle_outlined, color: Color(0xFFCBD5E1)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (model.canList)
            OutlinedButton.icon(
              onPressed: model.loadPrinters,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث القائمة'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── السجل ─────────────────────────

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Heading('السجل', 'آخر عمليات الطباعة'),
          const SizedBox(height: 16),
          if (model.history.isEmpty)
            Text('لم تطبع أي ملف بعد.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          for (final e in model.history) ...[
            AppCard(
              onTap: () => reopen(context, e),
              child: Item(const IconTile(Icons.check_circle_outline, bg: Color(0xFFDCFCE7), fg: Color(0xFF15803D)), e.name, '${whenText(e.date)} · ${e.printer}'),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── الإعدادات ─────────────────────────

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  Widget _group(BuildContext context, String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Card(child: Column(children: rows)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Heading('الإعدادات', 'خصّص التطبيق كما تحب'),
          _group(context, 'الطباعة', [
            ListTile(
              leading: const IconTile(Icons.description_outlined),
              title: const Text('حجم الورق الافتراضي'),
              trailing: SizedBox(
                width: 170,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'A4', label: Text('A4')), ButtonSegment(value: 'Letter', label: Text('Letter'))],
                  selected: {model.paper},
                  onSelectionChanged: (s) => model.setPaper(s.first),
                ),
              ),
            ),
          ]),
          _group(context, 'التطبيق', [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeMode,
              builder: (_, m, __) => SwitchListTile(
                secondary: const IconTile(Icons.dark_mode_outlined),
                title: const Text('الوضع الداكن'),
                value: m == ThemeMode.dark,
                onChanged: model.setDark,
              ),
            ),
            ListTile(
              leading: const IconTile(Icons.delete_outline),
              title: const Text('مسح سجل الطباعة'),
              onTap: model.history.isEmpty
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('مسح السجل؟'),
                          content: const Text('سيتم حذف قائمة الملفات المطبوعة من التطبيق فقط.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
                          ],
                        ),
                      );
                      if (ok == true) await model.clearHistory();
                    },
            ),
          ]),
          _group(context, 'حول', [
            ListTile(leading: const IconTile(Icons.info_outline), title: const Text('الإصدار'), trailing: Text('${ar(1)}.${ar(0)}.${ar(0)}')),
          ]),
        ],
      ),
    );
  }
}

// ───────────────────────── إعدادات الطباعة ─────────────────────────

class PrintSettingsScreen extends StatelessWidget {
  const PrintSettingsScreen({super.key});

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الطباعة')),
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final job = model.job!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('${job.name} · ${ar(job.pages)} صفحات', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
              const SizedBox(height: 12),
              Container(
                height: 260,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(20)),
                child: job.preview == null
                    ? const Center(child: Icon(Icons.description_outlined, size: 48))
                    : Center(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 6))]),
                          child: ColorFiltered(
                            colorFilter: model.color
                                ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                                : const ColorFilter.matrix(<double>[
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0, 0, 0, 1, 0,
                                  ]),
                            child: Image.memory(job.preview!, fit: BoxFit.contain, gaplessPlayback: true),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Expanded(child: Text('عدد النسخ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                      IconButton.filledTonal(onPressed: model.copies < 99 ? () => model.update(() => model.copies++) : null, icon: const Icon(Icons.add)),
                      SizedBox(width: 40, child: Center(child: Text(ar(model.copies), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)))),
                      IconButton.filledTonal(onPressed: model.copies > 1 ? () => model.update(() => model.copies--) : null, icon: const Icon(Icons.remove)),
                    ]),
                    _label('الألوان'),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [ButtonSegment(value: true, label: Text('ملون')), ButtonSegment(value: false, label: Text('أبيض وأسود'))],
                        selected: {model.color},
                        onSelectionChanged: (s) => model.update(() => model.color = s.first),
                      ),
                    ),
                    _label('حجم الورق'),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [ButtonSegment(value: 'A4', label: Text('A4')), ButtonSegment(value: 'Letter', label: Text('Letter'))],
                        selected: {model.paper},
                        onSelectionChanged: (s) => model.setPaper(s.first),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text('خيارات أخرى مثل الطباعة على وجهين تجدها في نافذة الطباعة بعد الضغط على «طباعة».', style: TextStyle(color: muted, fontSize: 12)),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(model.printerLabel, style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintProgressScreen())),
                icon: const Icon(Icons.print),
                label: const Text('طباعة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────── جارٍ الطباعة ─────────────────────────

enum _Phase { busy, done, cancelled, error }

class PrintProgressScreen extends StatefulWidget {
  const PrintProgressScreen({super.key});
  @override
  State<PrintProgressScreen> createState() => _PrintProgressScreenState();
}

class _PrintProgressScreenState extends State<PrintProgressScreen> {
  _Phase _phase = _Phase.busy;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _phase = _Phase.busy);
    try {
      final ok = await doPrint();
      if (ok) await model.addHistory(model.job!, model.printerLabel);
      if (mounted) setState(() => _phase = ok ? _Phase.done : _Phase.cancelled);
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final (IconData?, Color, String, String) v = switch (_phase) {
      _Phase.busy => (null, kBlue, 'جارٍ تجهيز الطباعة…', 'ستظهر نافذة اختيار الطابعة بعد لحظات'),
      _Phase.done => (Icons.check_circle, const Color(0xFF15803D), 'تم إرسال المستند للطباعة', model.job!.name),
      _Phase.cancelled => (Icons.cancel_outlined, const Color(0xFFB45309), 'تم إلغاء الطباعة', 'لم يُرسل أي شيء إلى الطابعة'),
      _Phase.error => (Icons.error_outline, const Color(0xFFB91C1C), 'تعذّرت الطباعة', _error),
    };
    return PopScope(
      canPop: _phase != _Phase.busy,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Spacer(),
              if (v.$1 == null)
                const SizedBox(width: 96, height: 96, child: CircularProgressIndicator(strokeWidth: 8, strokeCap: StrokeCap.round))
              else
                Icon(v.$1, size: 96, color: v.$2),
              const SizedBox(height: 24),
              Text(v.$3, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(v.$4, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
              const Spacer(),
              if (_phase == _Phase.cancelled || _phase == _Phase.error) ...[
                SizedBox(width: double.infinity, height: 54, child: FilledButton(onPressed: _run, child: const Text('إعادة المحاولة'))),
                const SizedBox(height: 10),
              ],
              if (_phase != _Phase.busy)
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: Text(_phase == _Phase.done ? 'تم' : 'رجوع'),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}