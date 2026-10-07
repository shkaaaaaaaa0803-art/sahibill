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
    final x = await ImagePicker().pickImage(source: src, imageQuality: 85);
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
  late final c = {
    'store': TextEditingController(text: widget.bill.store),
    'invoiceNo': TextEditingController(text: widget.bill.invoiceNo),
    'date': TextEditingController(text: widget.bill.date),
    'gstin': TextEditingController(text: widget.bill.gstin),
    'subtotal': TextEditingController(text: widget.bill.subtotal.toString()),
    'tax': TextEditingController(text: widget.bill.tax.toString()),
    'total': TextEditingController(text: widget.bill.total.toString()),
  };
  late String cat = cats.contains(widget.bill.category) ? widget.bill.category : 'Other';

  double n(String k) => double.tryParse(c[k]!.text) ?? 0;

  Bill get current => Bill(
    store: c['store']!.text,
    invoiceNo: c['invoiceNo']!.text,
    date: c['date']!.text,
    gstin: c['gstin']!.text.toUpperCase().trim(),
    category: cat,
    subtotal: n('subtotal'),
    tax: n('tax'),
    total: n('total'),
    items: widget.bill.items,
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

  @override
  Widget build(BuildContext context) {
    final issues = audit(current, widget.history);
    final b = badge(issues);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Chip(label: Text(b), backgroundColor: badgeColor[b]),
      ),
      for (final i in issues) Text('• ${i.$1}'),
      const SizedBox(height: 12),
      for (final k in c.keys)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: c[k],
            decoration: InputDecoration(labelText: k),
            onChanged: (_) => setState(() {}),
          ),
        ),
      DropdownButtonFormField<String>(
        initialValue: cat,
        decoration: const InputDecoration(labelText: 'category'),
        items: [for (final x in cats) DropdownMenuItem(value: x, child: Text(x))],
        onChanged: (v) => setState(() => cat = v!),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: save, child: const Text('Save')),
      TextButton(onPressed: widget.onDone, child: const Text('Cancel')),
    ]);
  }
}

class Dashboard extends StatelessWidget {
  final List<Bill> bills;
  const Dashboard({super.key, required this.bills});

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) return const Center(child: Text('No bills yet'));
    final spend = <String, double>{};
    for (final b in bills) {
      spend.update(b.category, (v) => v + b.total, ifAbsent: () => b.total);
    }
    final counts = <String, int>{};
    for (final (_, iss) in audited(bills)) {
      counts.update(badge(iss), (v) => v + 1, ifAbsent: () => 1);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, children: [
        for (final e in counts.entries)
          Chip(label: Text('${e.value} ${e.key}'), backgroundColor: badgeColor[e.key]),
      ]),
      const SizedBox(height: 16),
      SizedBox(
        height: 240,
        child: PieChart(PieChartData(sections: [
          for (final e in spend.entries)
            PieChartSectionData(
              value: e.value,
              color: palette[cats.indexOf(e.key) % palette.length],
              title: e.key,
              radius: 90,
              titleStyle: const TextStyle(fontSize: 12, color: Colors.white),
            ),
        ])),
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
          title: Text('${b.store} · ₹${b.total}'),
          subtitle: Text(iss.map((i) => i.$1).join(', ')),
          trailing: Chip(label: Text(badge(iss)), backgroundColor: badgeColor[badge(iss)]),
        ),
    ]);
  }
}