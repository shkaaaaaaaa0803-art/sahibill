import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'bill.dart';
import 'services.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
const cats = ['Food', 'Travel', 'Supplies', 'Utilities', 'Other'];

// Soft, friendly category colours (used by the donut and legend).
const palette = [
  Color(0xFF0F766E),
  Color(0xFF6366F1),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
];

/// Demo bill that works without AI. Total is intentionally wrong
/// (1000 + 180 tax = 1180, but total says 1280) so the audit shows "Check".
const sampleBill = Bill(
  store: 'Sharma Stationers',
  address: 'Hazratganj, Lucknow',
  invoiceNo: 'SS-1042',
  date: '2026-10-05',
  time: '14:35',
  currency: 'INR',
  payment: 'UPI',
  category: 'Supplies',
  subtotal: 1000,
  taxRate: 18,
  tax: 180,
  total: 1280,
  items: [600.0, 400.0],
  lines: [
    LineItem(name: 'A4 paper (5 reams)', qty: 5, unitPrice: 120, amount: 600),
    LineItem(name: 'Pens and markers', qty: 1, unitPrice: 400, amount: 400),
  ],
);

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

List<(Bill, List<Issue>)> audited(List<Bill> all) => [
  for (var i = 0; i < all.length; i++)
    (all[i], audit(all[i], [...all.sublist(0, i), ...all.sublist(i + 1)])),
];

// ---------- Tonal colours for Trusted / Check / Suspicious ----------

class Tone {
  final Color bg, fg, accent;
  const Tone(this.bg, this.fg, this.accent);
}

Tone toneFor(BuildContext c, String name) {
  final theme = Theme.of(c);
  final cs = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  switch (name) {
    case 'Trusted':
      return dark
          ? const Tone(Color(0xFF0F3D22), Color(0xFFA6F0B8), Color(0xFF4CAF50))
          : const Tone(Color(0xFFD7F5DD), Color(0xFF0B5D2A), Color(0xFF2E7D32));
    case 'Check':
      return dark
          ? const Tone(Color(0xFF4A3500), Color(0xFFFFD98A), Color(0xFFFFB300))
          : const Tone(Color(0xFFFFE8B8), Color(0xFF5C3D00), Color(0xFFB26A00));
    default:
      return Tone(cs.errorContainer, cs.onErrorContainer, cs.error);
  }
}

IconData badgeIcon(String name) => name == 'Trusted'
    ? Icons.verified
    : name == 'Check'
    ? Icons.warning_amber_rounded
    : Icons.error;

String levelName(int level) => level == 2 ? 'Suspicious' : 'Check';

/// Solid pill that "pops" (scales in with a small overshoot) when its text changes.
Widget popBadge(BuildContext context, String name) {
  final t = toneFor(context, name);
  return TweenAnimationBuilder<double>(
    key: ValueKey(name),
    tween: Tween<double>(begin: 0.5, end: 1),
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOutBack,
    builder: (_, s, child) => Transform.scale(scale: s, child: child),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.fg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(badgeIcon(name), size: 16, color: t.bg),
        const SizedBox(width: 6),
        Text(
          name.toUpperCase(),
          style: TextStyle(
            color: t.bg,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ]),
    ),
  );
}

/// Soft pill (tinted background) for lists and legends.
Widget softPill(BuildContext context, String name, {String? text}) {
  final t = toneFor(context, name);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: t.bg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(badgeIcon(name), size: 15, color: t.fg),
      const SizedBox(width: 5),
      Text(
        text ?? name,
        style: TextStyle(color: t.fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    ]),
  );
}

Widget emptyState(BuildContext context, IconData icon, String title, String body) {
  final cs = Theme.of(context).colorScheme;
  final th = Theme.of(context).textTheme;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 36, color: cs.onSecondaryContainer),
        ),
        const SizedBox(height: 16),
        Text(title, style: th.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.center,
          style: th.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0),
  );
}

// ---------- Home ----------

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  List<Bill> bills = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final b = await loadBills();
      if (mounted) setState(() => bills = b);
    } catch (e) {
      if (mounted) toast(context, 'Could not load bills: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SahiBill',
          style: TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (_, m, _) => IconButton(
            icon: Icon(m == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => themeMode.value =
            m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: IndexedStack(index: tab, children: [
        ScanPage(history: bills, onSaved: refresh),
        Dashboard(bills: bills),
        Flags(bills: bills),
      ]),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.document_scanner_outlined),
          selectedIcon: Icon(Icons.document_scanner),
          label: 'Scan',
        ),
        NavigationDestination(
          icon: Icon(Icons.pie_chart_outline),
          selectedIcon: Icon(Icons.pie_chart),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.flag_outlined),
          selectedIcon: Icon(Icons.flag),
          label: 'Flags',
        ),
      ],
    ),
  );
}

// ---------- Scanning animation ----------

class ScanningView extends StatefulWidget {
  const ScanningView({super.key});
  @override
  State<ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<ScanningView> {
  static const steps = [
    'Reading your bill',
    'Extracting store and items',
    'Checking totals and tax',
    'Running audit rules',
  ];
  int secs = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => secs++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final th = Theme.of(context).textTheme;
    final current = (secs ~/ 2).clamp(0, steps.length - 1);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 150,
            height: 190,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final w in [90.0, 60.0, 100.0, 70.0, 100.0, 50.0, 80.0])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: Container(
                            width: w,
                            height: 8,
                            decoration: BoxDecoration(
                              color: cs.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  child: Container(height: 4, color: cs.primary)
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(
                    begin: 0,
                    end: 170,
                    duration: 1400.ms,
                    curve: Curves.easeInOut,
                  ),
                ),
              ]),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(
            begin: const Offset(0.9, 0.9),
            end: const Offset(1, 1),
            curve: Curves.easeOutBack,
          ),
          const SizedBox(height: 28),
          Text('Checking your bill',
              style: th.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            width: 260,
            child: Column(children: [
              for (final (idx, s) in steps.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: idx < current
                          ? Icon(Icons.check_circle, color: cs.primary, size: 22)
                          .animate()
                          .scale(duration: 300.ms, curve: Curves.easeOutBack)
                          : idx == current
                          ? const Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                          : Icon(Icons.radio_button_unchecked,
                          color: cs.outlineVariant, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s,
                        style: th.bodyMedium?.copyWith(
                          color: idx <= current ? cs.onSurface : cs.onSurfaceVariant,
                          fontWeight: idx == current ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            opacity: secs >= 10 ? 1 : 0,
            duration: const Duration(milliseconds: 400),
            child: Text(
              'Taking a little longer. Still working…',
              style: th.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- Scan page ----------

class ScanPage extends StatefulWidget {
  final List<Bill> history;
  final VoidCallback onSaved;
  const ScanPage({super.key, required this.history, required this.onSaved});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool busy = false;
  Bill? bill;
  (String, String)? err;

  Future<void> scan(ImageSource src) async {
    final x = await ImagePicker().pickImage(
      source: src,
      maxWidth: 1000,
      imageQuality: 55,
    );
    if (x == null) return;
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final bytes = await x.readAsBytes();
      final mime = bytes[0] == 0x89 ? 'image/png' : 'image/jpeg';
      final b = await extractBill(bytes, mime);
      if (mounted) setState(() => bill = b);
    } catch (e) {
      if (mounted) setState(() => err = friendlyError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void done() {
    setState(() => bill = null);
    widget.onSaved();
  }

  Widget errorCard(ColorScheme cs, TextTheme th) {
    final (title, body) = err!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: th.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onErrorContainer,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(body, style: th.bodyMedium?.copyWith(color: cs.onErrorContainer)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => err = null),
            child: const Text('Dismiss'),
          ),
        ),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (busy) return const ScanningView();
    if (bill != null) {
      return ReviewForm(bill: bill!, history: widget.history, onDone: done);
    }
    final cs = Theme.of(context).colorScheme;
    final th = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Column(children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: cs.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.receipt_long, size: 40, color: cs.primary),
                  ).animate().fadeIn(duration: 400.ms).scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1, 1),
                    curve: Curves.easeOutBack,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Check any bill in seconds',
                    textAlign: TextAlign.center,
                    style: th.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                    ),
                  ).animate().fadeIn(delay: 150.ms),
                  const SizedBox(height: 8),
                  Text(
                    'AI reads your bill, rules verify it, and you get a clear verdict with reasons.',
                    textAlign: TextAlign.center,
                    style: th.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                  ).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      softPill(context, 'Trusted'),
                      softPill(context, 'Check'),
                      softPill(context, 'Suspicious'),
                    ],
                  ).animate().fadeIn(delay: 350.ms),
                ]),
              ),
              const SizedBox(height: 20),
              if (err != null) ...[
                errorCard(cs, th),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: () => scan(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan bill'),
              ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.2, end: 0),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => scan(ImageSource.gallery),
                icon: const Icon(Icons.upload),
                label: const Text('Upload photo'),
              ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.2, end: 0),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() {
                      err = null;
                      bill = const Bill(
                          store: '', date: '', subtotal: 0, tax: 0, total: 0);
                    }),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Enter manually'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      err = null;
                      bill = sampleBill;
                    }),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Try sample bill'),
                  ),
                ],
              ).animate().fadeIn(delay: 650.ms),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Review form ----------

class ReviewForm extends StatefulWidget {
  final Bill bill;
  final List<Bill> history;
  final VoidCallback onDone;
  const ReviewForm({super.key, required this.bill, required this.history, required this.onDone});
  @override
  State<ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<ReviewForm> {
  static const labels = <String, String>{
    'store': 'Store', 'date': 'Date (YYYY-MM-DD)', 'total': 'Total', 'tax': 'Tax amount',
    'time': 'Time', 'currency': 'Currency', 'subtotal': 'Subtotal (before tax)',
    'taxRate': 'Tax rate %', 'gstin': 'Tax ID (GSTIN / VAT)', 'invoiceNo': 'Invoice / receipt no.',
    'address': 'Address', 'payment': 'Payment method', 'fiscalId': 'Fiscal ID',
  };
  static const numeric = {'total', 'tax', 'subtotal', 'taxRate'};
  static const keyFields = ['store', 'date', 'total', 'tax'];
  static const moreFields = [
    'time', 'currency', 'subtotal', 'taxRate', 'gstin',
    'invoiceNo', 'address', 'payment', 'fiscalId',
  ];

  late final Map<String, TextEditingController> c = {
    for (final e in {
      'store': widget.bill.store,
      'date': widget.bill.date,
      'total': widget.bill.total.toString(),
      'tax': widget.bill.tax.toString(),
      'time': widget.bill.time,
      'currency': widget.bill.currency,
      'subtotal': widget.bill.subtotal.toString(),
      'taxRate': widget.bill.taxRate.toString(),
      'gstin': widget.bill.gstin,
      'invoiceNo': widget.bill.invoiceNo,
      'address': widget.bill.address,
      'payment': widget.bill.payment,
      'fiscalId': widget.bill.fiscalId,
    }.entries)
      e.key: TextEditingController(text: e.value),
  };
  late String cat = cats.contains(widget.bill.category) ? widget.bill.category : 'Other';
  late bool dateAmbiguous = widget.bill.dateAmbiguous;

  double n(String k) => double.tryParse(c[k]!.text.replaceAll(',', '')) ?? 0;

  Bill get current => Bill(
    store: c['store']!.text.trim(),
    date: c['date']!.text.trim(),
    time: c['time']!.text.trim(),
    currency: c['currency']!.text.toUpperCase().trim(),
    subtotal: n('subtotal'),
    taxRate: n('taxRate'),
    tax: n('tax'),
    total: n('total'),
    gstin: c['gstin']!.text.toUpperCase().trim(),
    invoiceNo: c['invoiceNo']!.text.trim(),
    address: c['address']!.text.trim(),
    payment: c['payment']!.text.trim(),
    fiscalId: c['fiscalId']!.text.trim(),
    category: cat,
    dateAmbiguous: dateAmbiguous,
    items: widget.bill.items,
    lines: widget.bill.lines,
  );

  Future<void> save() async {
    try {
      await saveBill(current);
      widget.onDone();
    } catch (e) {
      if (mounted) toast(context, 'Save failed: $e');
    }
  }

  @override
  void dispose() {
    for (final t in c.values) {
      t.dispose();
    }
    super.dispose();
  }

  // flagged: field name -> highest issue level (1 = Check, 2 = Suspicious)
  Widget field(String k, Map<String, int> flagged) {
    final lvl = flagged[k];
    final col = lvl == null ? null : toneFor(context, levelName(lvl)).accent;
    final ob = col == null
        ? null
        : OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: col, width: 2),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c[k],
        keyboardType: numeric.contains(k)
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: InputDecoration(
          labelText: labels[k],
          enabledBorder: ob,
          focusedBorder: ob,
          suffixIcon: col == null ? null : Icon(Icons.warning_amber_rounded, color: col),
        ),
        onChanged: (_) => setState(() {
          if (k == 'date') dateAmbiguous = false;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = current;
    final issues = audit(b, widget.history);
    final bd = badge(issues);
    final tone = toneFor(context, bd);
    final th = Theme.of(context).textTheme;

    final flagged = <String, int>{};
    for (final i in issues) {
      for (final f in i.$3) {
        final prev = flagged[f] ?? 0;
        if (i.$2 > prev) flagged[f] = i.$2;
      }
    }
    final rate = b.taxRate == 0
        ? ''
        : ' (${b.taxRate.toStringAsFixed(b.taxRate % 1 == 0 ? 0 : 1)}%)';

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      // Key facts card, tinted by the verdict
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            popBadge(context, bd),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tone.fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(cat,
                  style: TextStyle(
                      color: tone.fg, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: b.total),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(
              money(b.currency, v),
              style: th.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: tone.fg,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(b.store.isEmpty ? 'Unknown store' : b.store,
              style: th.titleMedium?.copyWith(color: tone.fg)),
          Text([b.date, b.time].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(color: tone.fg)),
          if (b.tax > 0)
            Text('Tax ${money(b.currency, b.tax)}$rate',
                style: TextStyle(color: tone.fg)),
          if (b.payment.isNotEmpty)
            Text('Paid by ${b.payment}', style: TextStyle(color: tone.fg)),
        ]),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),
      const SizedBox(height: 8),

      if (issues.isEmpty)
        Builder(builder: (context) {
          final t = toneFor(context, 'Trusted');
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Icon(Icons.verified, color: t.accent),
              const SizedBox(width: 12),
              Text('All checks passed',
                  style: TextStyle(
                      color: t.fg, fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
          );
        }),
      for (final (idx, i) in issues.indexed)
        Builder(builder: (context) {
          final t = toneFor(context, levelName(i.$2));
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Icon(i.$2 == 2 ? Icons.error : Icons.warning_amber_rounded,
                  color: t.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(i.$1,
                    style: TextStyle(
                        color: t.fg, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (dateAmbiguous && i.$3.contains('date'))
                TextButton(
                  onPressed: () => setState(() => dateAmbiguous = false),
                  child: const Text('Date is right'),
                ),
            ]),
          )
              .animate()
              .fadeIn(delay: (80 * idx).ms, duration: 300.ms)
              .slideX(begin: 0.1, end: 0, delay: (80 * idx).ms);
        }),
      const SizedBox(height: 12),

      for (final k in keyFields) field(k, flagged),
      DropdownButtonFormField<String>(
        initialValue: cat,
        decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final x in cats) DropdownMenuItem(value: x, child: Text(x))],
        onChanged: (v) => setState(() => cat = v!),
      ),
      const SizedBox(height: 8),

      ExpansionTile(
        title: const Text('More details'),
        initiallyExpanded: moreFields.any(flagged.containsKey),
        children: [for (final k in moreFields) field(k, flagged)],
      ),
      if (b.lines.isNotEmpty)
        ExpansionTile(
          title: Text('Items (${b.lines.length})'),
          children: [
            for (final l in b.lines)
              ListTile(
                dense: true,
                title: Text(l.name),
                subtitle: Text('${l.qty} × ${money(b.currency, l.unitPrice)}'),
                trailing: Text(money(b.currency, l.amount)),
              ),
          ],
        ),
      const SizedBox(height: 12),
      FilledButton(onPressed: save, child: const Text('Save')),
      TextButton(onPressed: widget.onDone, child: const Text('Cancel')),
    ]);
  }
}

// ---------- Dashboard ----------

class Dashboard extends StatefulWidget {
  final List<Bill> bills;
  const Dashboard({super.key, required this.bills});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String? picked;

  static const _mn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String monthLabel(String key) {
    if (key.length != 7) return 'No date';
    final m = int.tryParse(key.substring(5, 7)) ?? 0;
    if (m < 1 || m > 12) return key;
    return '${_mn[m - 1]} ${key.substring(2, 4)}';
  }

  String compact(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  /// Always returns 6 consecutive months ending at the latest month that has
  /// a bill. Months without bills stay in the list (shown as empty bars).
  /// A "No date" bar is added at the end only if some bill has no date.
  List<String> monthWindow(Map<String, double> months) {
    final valid = <String>[];
    for (final k in months.keys) {
      if (k.length == 7 && k[4] == '-') {
        final y = int.tryParse(k.substring(0, 4));
        final m = int.tryParse(k.substring(5, 7));
        if (y != null && m != null && m >= 1 && m <= 12) valid.add(k);
      }
    }
    valid.sort();
    final out = <String>[];
    if (valid.isNotEmpty) {
      var y = int.parse(valid.last.substring(0, 4));
      var m = int.parse(valid.last.substring(5, 7));
      for (var i = 0; i < 6; i++) {
        out.insert(0, '$y-${m.toString().padLeft(2, '0')}');
        m--;
        if (m == 0) {
          m = 12;
          y--;
        }
      }
    }
    if (months.containsKey('No date')) out.add('No date');
    return out;
  }

  Widget stat(String label, String value, IconData icon, Color bg, Color fg, int i) =>
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: fg)),
          ]),
        )
            .animate()
            .fadeIn(delay: (70 * i).ms, duration: 350.ms)
            .slideY(begin: 0.2, end: 0, delay: (70 * i).ms),
      );

  Widget section(String title, String subtitle, Widget child, int i) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
        const SizedBox(height: 16),
        child,
      ]),
    ),
  )
      .animate()
      .fadeIn(delay: (120 * i).ms, duration: 400.ms)
      .slideY(begin: 0.1, end: 0, delay: (120 * i).ms);

  Widget trustBar(Map<String, int> counts) {
    final order = ['Trusted', 'Check', 'Suspicious'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: SizedBox(
          height: 14,
          child: Row(children: [
            for (final name in order)
              if ((counts[name] ?? 0) > 0)
                Expanded(
                  flex: counts[name]!,
                  child: Container(
                    margin: const EdgeInsets.only(right: 2),
                    color: toneFor(context, name).accent,
                  ),
                ),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final name in order)
          if ((counts[name] ?? 0) > 0)
            softPill(context, name, text: '${counts[name]} $name'),
      ]),
    ]);
  }

  Widget donut(String cur, List<MapEntry<String, double>> entries, double total) {
    final th = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Color colorOf(String k) => palette[cats.indexOf(k) % palette.length];

    return Column(children: [
      SizedBox(
        height: 210,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 68,
            startDegreeOffset: -90,
            sections: [
              for (final e in entries)
                PieChartSectionData(
                  value: e.value,
                  color: colorOf(e.key),
                  title: '',
                  radius: 28,
                ),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Total',
                style: th.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            Text(money(cur, total),
                style: th.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Row(children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colorOf(e.key),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(e.key,
                    style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Text(money(cur, e.value),
                  style: th.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              SizedBox(
                width: 44,
                child: Text(
                  '${total > 0 ? (e.value / total * 100).round() : 0}%',
                  textAlign: TextAlign.right,
                  style: th.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: total > 0 ? e.value / total : 0,
                minHeight: 6,
                color: colorOf(e.key),
                backgroundColor: colorOf(e.key).withValues(alpha: 0.15),
              ),
            ),
          ]),
        ),
    ]);
  }

  Widget monthBars(Map<String, double> months, List<String> shown) {
    final cs = Theme.of(context).colorScheme;
    var maxV = 0.0;
    for (final k in shown) {
      final v = months[k] ?? 0;
      if (v > maxV) maxV = v;
    }

    return SizedBox(
      height: 185,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, k) in shown.indexed)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(
                (months[k] ?? 0) > 0 ? compact(months[k]!) : '–',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: (months[k] ?? 0) > 0 ? cs.onSurface : cs.outline,
                ),
              ),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: maxV > 0 ? (months[k] ?? 0) / maxV : 0,
                ),
                duration: Duration(milliseconds: 700 + i * 120),
                curve: Curves.easeOutCubic,
                builder: (_, f, _) {
                  final has = (months[k] ?? 0) > 0;
                  return Container(
                    width: 26,
                    height: 6 + 110 * f,
                    decoration: BoxDecoration(
                      color: !has
                          ? cs.surfaceContainerHighest
                          : (months[k] == maxV ? cs.primary : cs.primaryContainer),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Text(
                monthLabel(k),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = widget.bills;
    if (all.isEmpty) {
      return emptyState(context, Icons.pie_chart_outline, 'No bills yet',
          'Scan or add a bill and your spending summary will show up here.');
    }

    // Never mix currencies in one chart: pick one at a time.
    final currencies = {for (final b in all) b.currency}.toList()..sort();
    final cur = currencies.contains(picked)
        ? picked!
        : (currencies.contains('INR') ? 'INR' : currencies.first);
    final bills = all.where((b) => b.currency == cur).toList();

    final spend = <String, double>{};
    final months = <String, double>{};
    var total = 0.0, tax = 0.0;
    for (final b in bills) {
      total += b.total;
      tax += b.tax;
      spend.update(b.category, (v) => v + b.total, ifAbsent: () => b.total);
      final mk = b.date.length >= 7 ? b.date.substring(0, 7) : 'No date';
      months.update(mk, (v) => v + b.total, ifAbsent: () => b.total);
    }
    final counts = <String, int>{};
    for (final (b, iss) in audited(all)) {
      if (b.currency != cur) continue;
      counts.update(badge(iss), (v) => v + 1, ifAbsent: () => 1);
    }
    final flaggedCount = bills.length - (counts['Trusted'] ?? 0);

    final entries = spend.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = monthWindow(months);

    final attn = toneFor(context, flaggedCount > 0 ? 'Check' : 'Trusted');

    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
      if (currencies.length > 1)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Wrap(spacing: 8, children: [
            for (final c in currencies)
              ChoiceChip(
                label: Text(c),
                selected: c == cur,
                onSelected: (_) => setState(() => picked = c),
              ),
          ]),
        ),

      Row(children: [
        stat('Total spend', money(cur, total), Icons.account_balance_wallet,
            cs.primaryContainer, cs.onPrimaryContainer, 0),
        stat('Bills', '${bills.length}', Icons.receipt_long,
            cs.secondaryContainer, cs.onSecondaryContainer, 1),
      ]),
      Row(children: [
        stat('Tax paid', money(cur, tax), Icons.percent,
            cs.tertiaryContainer, cs.onTertiaryContainer, 2),
        stat('Need attention', '$flaggedCount', Icons.flag,
            attn.bg, attn.fg, 3),
      ]),

      section('Trust overview', 'How your bills were rated', trustBar(counts), 1),
      section('Spend by category', 'Where your money goes',
          donut(cur, entries, total), 2),
      section('Monthly spend', 'Last 6 months',
          monthBars(months, shown), 3),
    ]);
  }
}

// ---------- Flags ----------

class Flags extends StatelessWidget {
  final List<Bill> bills;
  const Flags({super.key, required this.bills});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final th = Theme.of(context).textTheme;
    final flagged = audited(bills).where((x) => x.$2.isNotEmpty).toList();
    if (flagged.isEmpty) {
      return emptyState(context, Icons.verified, 'No flags. All clear.',
          'Bills that need a second look will appear here with the reasons.');
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          '${flagged.length} bill${flagged.length == 1 ? '' : 's'} need a look',
          style: th.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      for (final (idx, (b, iss)) in flagged.indexed)
        Builder(builder: (context) {
          final name = badge(iss);
          final t = toneFor(context, name);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: t.bg, shape: BoxShape.circle),
                  child: Icon(badgeIcon(name), color: t.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      b.store.isEmpty ? 'Unknown store' : b.store,
                      style: th.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [money(b.currency, b.total), b.date]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: th.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    for (final i in iss)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6, right: 8),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: toneFor(context, levelName(i.$2)).accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Expanded(child: Text(i.$1, style: th.bodySmall)),
                          ],
                        ),
                      ),
                  ]),
                ),
                const SizedBox(width: 8),
                softPill(context, name),
              ]),
            ),
          )
              .animate()
              .fadeIn(delay: (70 * idx).ms, duration: 350.ms)
              .slideY(begin: 0.2, end: 0, delay: (70 * idx).ms);
        }),
    ]);
  }
}