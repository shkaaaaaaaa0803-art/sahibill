import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'bill.dart';
import 'services.dart';

final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);
const cats = ['Food', 'Travel', 'Supplies', 'Utilities', 'Other'];
const palette = [Colors.teal, Colors.indigo, Colors.orange, Colors.pink, Colors.brown];
const Map<String, Color> badgeColor = {
  'Trusted': Colors.green, 'Check': Colors.orange, 'Suspicious': Colors.red,
};

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

List<(Bill, List<Issue>)> audited(List<Bill> all) => [
  for (var i = 0; i < all.length; i++)
    (all[i], audit(all[i], [...all.sublist(0, i), ...all.sublist(i + 1)])),
];

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
      title: const Text('SahiBill'),
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
        NavigationDestination(icon: Icon(Icons.document_scanner), label: 'Scan'),
        NavigationDestination(icon: Icon(Icons.pie_chart), label: 'Dashboard'),
        NavigationDestination(icon: Icon(Icons.flag), label: 'Flags'),
      ],
    ),
  );
}

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

  Future<void> scan(ImageSource src) async {
    final x = await ImagePicker().pickImage(
      source: src,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (x == null) return;
    setState(() => busy = true);
    try {
      final bytes = await x.readAsBytes();
      final mime = bytes[0] == 0x89 ? 'image/png' : 'image/jpeg';
      final b = await extractBill(bytes, mime);
      if (mounted) setState(() => bill = b);
    } catch (e) {
      if (mounted) toast(context, 'AI could not read it. Enter manually. ($e)');
    }
    if (mounted) setState(() => busy = false);
  }

  void done() {
    setState(() => bill = null);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (busy) return const Center(child: CircularProgressIndicator());
    if (bill != null) {
      return ReviewForm(bill: bill!, history: widget.history, onDone: done);
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FilledButton.icon(
          onPressed: () => scan(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Scan bill'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => scan(ImageSource.gallery),
          icon: const Icon(Icons.upload),
          label: const Text('Upload photo'),
        ),
        TextButton(
          onPressed: () => setState(() =>
          bill = const Bill(store: '', date: '', subtotal: 0, tax: 0, total: 0)),
          child: const Text('Enter manually'),
        ),
      ]),
    );
  }
}

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

  Widget field(String k, Map<String, Color> flagged) {
    final col = flagged[k];
    final ob = col == null
        ? null
        : OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
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
    final color = badgeColor[bd]!;
    final th = Theme.of(context).textTheme;

    final flagged = <String, Color>{};
    for (final i in issues) {
      for (final f in i.$3) {
        flagged[f] = (flagged[f] == Colors.red || i.$2 == 2) ? Colors.red : Colors.orange;
      }
    }
    final rate = b.taxRate == 0 ? '' : ' (${b.taxRate.toStringAsFixed(b.taxRate % 1 == 0 ? 0 : 1)}%)';

    return ListView(padding: const EdgeInsets.all(16), children: [
      // 1. Key facts card: the part that must catch the eye
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Chip(
                label: Text(bd.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                backgroundColor: color,
              ),
              const Spacer(),
              Chip(label: Text(cat)),
            ]),
            Text(money(b.currency, b.total),
                style: th.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(b.store.isEmpty ? 'Unknown store' : b.store, style: th.titleMedium),
            Text([b.date, b.time].where((s) => s.isNotEmpty).join(' · ')),
            if (b.tax > 0) Text('Tax ${money(b.currency, b.tax)}$rate'),
            if (b.payment.isNotEmpty) Text('Paid by ${b.payment}'),
          ]),
        ),
      ),

      // 2. Issues, loud and clear
      if (issues.isEmpty)
        const ListTile(
          leading: Icon(Icons.verified, color: Colors.green),
          title: Text('All checks passed'),
        ),
      for (final i in issues)
        Card(
          color: (i.$2 == 2 ? Colors.red : Colors.orange).withValues(alpha: 0.12),
          child: ListTile(
            leading: Icon(i.$2 == 2 ? Icons.error : Icons.warning_amber_rounded,
                color: i.$2 == 2 ? Colors.red : Colors.orange),
            title: Text(i.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: dateAmbiguous && i.$3.contains('date')
                ? TextButton(
              onPressed: () => setState(() => dateAmbiguous = false),
              child: const Text('Date is right'),
            )
                : null,
          ),
        ),
      const SizedBox(height: 12),

      // 3. Key fields (editable)
      for (final k in keyFields) field(k, flagged),
      DropdownButtonFormField<String>(
        initialValue: cat,
        decoration: const InputDecoration(labelText: 'Category'),
        items: [for (final x in cats) DropdownMenuItem(value: x, child: Text(x))],
        onChanged: (v) => setState(() => cat = v!),
      ),
      const SizedBox(height: 8),

      // 4. Everything else, tucked away
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

  Widget stat(String label, String value) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ]),
      ),
    ),
  );

  Widget heading(String t) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(t, style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700)),
  );

  @override
  Widget build(BuildContext context) {
    final all = widget.bills;
    if (all.isEmpty) return const Center(child: Text('No bills yet'));

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
      if (b.currency != cur) continue; // count only the selected currency
      counts.update(badge(iss), (v) => v + 1, ifAbsent: () => 1);
    }
    final flaggedCount = bills.length - (counts['Trusted'] ?? 0);

    final keys = months.keys.toList()..sort();
    final shown = keys.length > 6 ? keys.sublist(keys.length - 6) : keys;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (currencies.length > 1)
        Wrap(spacing: 8, children: [
          for (final c in currencies)
            ChoiceChip(
              label: Text(c),
              selected: c == cur,
              onSelected: (_) => setState(() => picked = c),
            ),
        ]),

      // Summary cards
      Row(children: [
        stat('Total spend', money(cur, total)),
        stat('Bills', '${bills.length}'),
      ]),
      Row(children: [
        stat('Tax paid', money(cur, tax)),
        stat('Need attention', '$flaggedCount'),
      ]),

      // Trust badge counts
      Wrap(spacing: 8, children: [
        for (final e in counts.entries)
          Chip(
            label: Text('${e.value} ${e.key}',
                style: const TextStyle(color: Colors.white)),
            backgroundColor: badgeColor[e.key],
          ),
      ]),

      // Pie: where the money goes
      heading('Spend by category'),
      SizedBox(
        height: 220,
        child: PieChart(PieChartData(
          centerSpaceRadius: 36,
          sectionsSpace: 2,
          sections: [
            for (final e in spend.entries)
              PieChartSectionData(
                value: e.value,
                color: palette[cats.indexOf(e.key) % palette.length],
                title: total > 0 ? '${(e.value / total * 100).round()}%' : '',
                radius: 80,
                titleStyle: const TextStyle(
                    fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700),
              ),
          ],
        )),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final e in spend.entries)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                color: palette[cats.indexOf(e.key) % palette.length],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text('${e.key}  ${money(cur, e.value)}'),
          ]),
      ]),

      // Bar: how spending changes month by month
      heading('Monthly spend'),
      SizedBox(
        height: 220,
        child: BarChart(BarChartData(
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= shown.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(monthLabel(shown[i]),
                        style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < shown.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: months[shown[i]]!,
                  color: Theme.of(context).colorScheme.primary,
                  width: 22,
                  borderRadius: BorderRadius.circular(6),
                ),
              ]),
          ],
        )),
      ),
    ]);
  }
}

class Flags extends StatelessWidget {
  final List<Bill> bills;
  const Flags({super.key, required this.bills});

  @override
  Widget build(BuildContext context) {
    final flagged = audited(bills).where((x) => x.$2.isNotEmpty).toList();
    if (flagged.isEmpty) return const Center(child: Text('No flags. All clear.'));
    return ListView(children: [
      for (final (b, iss) in flagged)
        ListTile(
          title: Text('${b.store} · ${money(b.currency, b.total)}'),
          subtitle: Text(iss.map((i) => i.$1).join(', ')),
          trailing: Chip(label: Text(badge(iss)), backgroundColor: badgeColor[badge(iss)]),
        ),
    ]);
  }
}