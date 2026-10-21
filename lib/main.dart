import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const kBlue = Color(0xFF2563EB);
const kInk = Color(0xFF0F172A);

/// تحويل الأرقام إلى الهندية (٠١٢٣…)
String ar(num n) => n.toString().replaceAllMapped(
    RegExp(r'\d'), (m) => String.fromCharCode(0x0660 + int.parse(m[0]!)));

// ───────────────────────── النموذج ─────────────────────────

class Printer {
  final String name, info;
  final IconData icon;
  const Printer(this.name, this.info, this.icon);
}

class PrintModel extends ChangeNotifier {
  final printers = <Printer>[
    const Printer('HP LaserJet Pro', 'Wi‑Fi · ملونة · جاهزة', Icons.wifi),
    const Printer('Canon PIXMA', 'Wi‑Fi · ملونة', Icons.wifi),
    const Printer('Brother HL-L2', 'بلوتوث · أبيض وأسود', Icons.bluetooth),
  ];
  int printerIndex = 0;
  int copies = 1;
  bool color = false;
  bool duplex = false;
  String paper = 'A4';
  String fileName = 'عقد الإيجار.pdf';
  int pages = 3;

  Printer get printer => printers[printerIndex];

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

final model = PrintModel();
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

// ───────────────────────── التطبيق ─────────────────────────

void main() => runApp(const PrintApp());

class PrintApp extends StatelessWidget {
  const PrintApp({super.key});

  ThemeData _theme(Brightness b) {
    final base = ThemeData(
      brightness: b,
      colorScheme: ColorScheme.fromSeed(seedColor: kBlue, brightness: b),
      useMaterial3: true,
    );
    return base.copyWith(
      scaffoldBackgroundColor:
          b == Brightness.light ? const Color(0xFFF4F6FB) : null,
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
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
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
        decoration: BoxDecoration(
          color: bg ?? const Color(0xFFE8EFFE),
          borderRadius: BorderRadius.circular(12),
        ),
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
          side: BorderSide(
              color: selected ? kBlue : Colors.transparent, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
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
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          Text(subtitle, style: TextStyle(color: muted, fontSize: 13)),
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
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}

Widget fileBadge(String t, Color bg, Color fg) => Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
    );

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
    _timer = Timer(const Duration(seconds: 3), _go);
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => const Shell()));
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
                  boxShadow: [BoxShadow(color: kBlue.withOpacity(.45), blurRadius: 32, offset: const Offset(0, 12))],
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

// ───────────────────────── الهيكل والتبويبات ─────────────────────────

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

void openPrintSettings(BuildContext context, String name, int pages) {
  // TODO: استبدل هذا بـ FilePicker.platform.pickFiles() لاختيار ملف حقيقي.
  model.update(() {
    model.fileName = name;
    model.pages = pages;
  });
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrintSettingsScreen()));
}

// ───────────────────────── الرئيسية ─────────────────────────

class HomeTab extends StatelessWidget {
  final VoidCallback onOpenPrinters;
  const HomeTab({super.key, required this.onOpenPrinters});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ListView(
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
                      Text(model.printer.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(model.printer.info, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
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
                  onPressed: () => openPrintSettings(context, 'عقد الإيجار.pdf', 3),
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('اختيار مستند للطباعة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _quick(context, Icons.description_outlined, 'ملفات PDF وWord')),
            const SizedBox(width: 12),
            Expanded(child: _quick(context, Icons.image_outlined, 'صور من المعرض')),
          ]),
          const SizedBox(height: 20),
          const Text('الملفات الأخيرة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 12),
          AppCard(
            onTap: () => openPrintSettings(context, 'عقد الإيجار.pdf', 3),
            child: Item(fileBadge('PDF', const Color(0xFFFEE2E2), const Color(0xFFB91C1C)), 'عقد الإيجار.pdf', '${ar(3)} صفحات · أمس', trailing: const Icon(Icons.chevron_left)),
          ),
          const SizedBox(height: 12),
          AppCard(
            onTap: () => openPrintSettings(context, 'تقرير المبيعات.docx', 12),
            child: Item(fileBadge('DOC', const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)), 'تقرير المبيعات.docx', '${ar(12)} صفحة · قبل ${ar(3)} أيام', trailing: const Icon(Icons.chevron_left)),
          ),
        ],
      ),
    );
  }

  Widget _quick(BuildContext context, IconData icon, String label) => AppCard(
        onTap: () => openPrintSettings(context, 'عقد الإيجار.pdf', 3),
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

  Future<void> _addByIp(BuildContext context) async {
    final c = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة طابعة'),
        content: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: '192.168.1.50'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('إضافة')),
        ],
      ),
    );
    if (ip != null && ip.isNotEmpty) {
      model.update(() => model.printers.add(Printer('طابعة $ip', 'عنوان IP', Icons.lan)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Heading('اختيار الطابعة', 'تم العثور على ${ar(model.printers.length)} طابعات قريبة'),
          const SizedBox(height: 16),
          for (var i = 0; i < model.printers.length; i++) ...[
            AppCard(
              selected: i == model.printerIndex,
              onTap: () => model.update(() => model.printerIndex = i),
              child: Item(
                IconTile(model.printers[i].icon),
                model.printers[i].name,
                model.printers[i].info,
                trailing: i == model.printerIndex
                    ? const CircleAvatar(radius: 13, backgroundColor: kBlue, child: Icon(Icons.check, size: 16, color: Colors.white))
                    : const Icon(Icons.circle_outlined, color: Color(0xFFCBD5E1)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: () => _addByIp(context),
            icon: const Icon(Icons.add),
            label: const Text('إضافة طابعة بعنوان IP'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          ),
          const SizedBox(height: 12),
          Center(child: Text('تأكد أن الهاتف والطابعة على نفس الشبكة', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13))),
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
    const jobs = [
      ('عقد الإيجار.pdf', 'أمس · HP LaserJet Pro'),
      ('تقرير المبيعات.docx', 'قبل 3 أيام · Canon PIXMA'),
      ('فاتورة.pdf', 'الأسبوع الماضي · HP LaserJet Pro'),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Heading('السجل', 'آخر عمليات الطباعة'),
        const SizedBox(height: 16),
        for (final j in jobs) ...[
          AppCard(child: Item(const IconTile(Icons.check_circle_outline, bg: Color(0xFFDCFCE7), fg: Color(0xFF15803D)), j.$1, j.$2)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ───────────────────────── الإعدادات ─────────────────────────

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _notify = true;

  Widget _group(String title, List<Widget> rows) => Column(
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
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Heading('الإعدادات', 'خصّص التطبيق كما تحب'),
        _group('الطباعة', [
          ListTile(leading: const IconTile(Icons.print), title: const Text('الطابعة الافتراضية'), subtitle: Text(model.printer.name), trailing: const Icon(Icons.chevron_left)),
          ListTile(leading: const IconTile(Icons.description_outlined), title: const Text('حجم الورق'), subtitle: Text(model.paper), trailing: const Icon(Icons.chevron_left)),
          const ListTile(leading: IconTile(Icons.high_quality_outlined), title: Text('جودة الطباعة'), subtitle: Text('عادية'), trailing: Icon(Icons.chevron_left)),
        ]),
        _group('التطبيق', [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (_, m, __) => SwitchListTile(
              secondary: const IconTile(Icons.dark_mode_outlined),
              title: const Text('الوضع الداكن'),
              value: m == ThemeMode.dark,
              onChanged: (v) => themeMode.value = v ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
          SwitchListTile(
            secondary: const IconTile(Icons.notifications_outlined),
            title: const Text('إشعار عند اكتمال الطباعة'),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ]),
        _group('حول', [
          ListTile(leading: const IconTile(Icons.info_outline), title: const Text('الإصدار'), trailing: Text('${ar(1)}.${ar(0)}.${ar(0)}')),
        ]),
      ],
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
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الطباعة')),
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${model.fileName} · ${ar(model.pages)} صفحات', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Container(
              height: 210,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(20)),
              alignment: Alignment.center,
              child: Container(
                width: 130,
                height: 180,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 6))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 10, width: 70, color: kInk),
                  for (final w in [1.0, .9, 1.0, .7, .95, 1.0, .5]) ...[
                    const SizedBox(height: 8),
                    FractionallySizedBox(widthFactor: w, child: Container(height: 6, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(3)))),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Expanded(child: Text('عدد النسخ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    IconButton.filledTonal(onPressed: () => model.update(() => model.copies++), icon: const Icon(Icons.add)),
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
                      onSelectionChanged: (s) => model.update(() => model.paper = s.first),
                    ),
                  ),
                  _label('الطباعة'),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [ButtonSegment(value: false, label: Text('وجه واحد')), ButtonSegment(value: true, label: Text('وجهان'))],
                      selected: {model.duplex},
                      onSelectionChanged: (s) => model.update(() => model.duplex = s.first),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${model.printer.name} · الصفحات ${ar(1)}–${ar(model.pages)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgressScreen())),
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

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  double _p = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // TODO: استبدل المحاكاة بإرسال المستند فعلياً إلى الطابعة
    // (مثلاً عبر حزمة printing: Printing.directPrintPdf).
    _timer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (!mounted) return;
      setState(() => _p = (_p + .04).clamp(0.0, 1.0));
      if (_p >= 1) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _p >= 1;
    final page = (_p * model.pages).ceil().clamp(1, model.pages);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Spacer(),
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(child: CircularProgressIndicator(value: _p, strokeWidth: 12, strokeCap: StrokeCap.round, backgroundColor: const Color(0xFFDCE3F2))),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${ar((_p * 100).round())}٪', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                  Text('صفحة ${ar(page)} من ${ar(model.pages)}', style: TextStyle(color: muted, fontSize: 13)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Text(done ? 'تمت الطباعة' : 'جارٍ الطباعة…', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text('${model.fileName} · ${model.printer.name}', style: TextStyle(color: muted)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: done
                  ? FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('تم'))
                  : OutlinedButton(
                      onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFB91C1C), side: const BorderSide(color: Color(0xFFB91C1C), width: 2)),
                      child: const Text('إلغاء الطباعة', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}