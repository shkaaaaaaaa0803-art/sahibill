class Bill {
  final String store, invoiceNo, date, gstin, category;
  final double subtotal, tax, total;
  final List<double> items;

  const Bill({
    required this.store,
    required this.date,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.invoiceNo = '',
    this.gstin = '',
    this.category = 'Other',
    this.items = const [],
  });

  factory Bill.fromMap(Map<String, dynamic> m) => Bill(
    store: m['store'] ?? '',
    invoiceNo: m['invoiceNo'] ?? '',
    date: m['date'] ?? '',
    gstin: (m['gstin'] ?? '').toString().toUpperCase().trim(),
    category: m['category'] ?? 'Other',
    subtotal: (m['subtotal'] ?? 0).toDouble(),
    tax: (m['tax'] ?? 0).toDouble(),
    total: (m['total'] ?? 0).toDouble(),
    items: [for (final i in m['items'] ?? []) (i as num).toDouble()],
  );

  Map<String, dynamic> toMap() => {
    'store': store, 'invoiceNo': invoiceNo, 'date': date, 'gstin': gstin,
    'category': category, 'subtotal': subtotal, 'tax': tax,
    'total': total, 'items': items,
  };
}

const _cs = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

bool validGstin(String g) {
  if (!RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(g)) return false;
  var sum = 0;
  for (var i = 0; i < 14; i++) {
    final v = _cs.indexOf(g[i]) * (i.isEven ? 1 : 2);
    sum += v ~/ 36 + v % 36;
  }
  return g[14] == _cs[(36 - sum % 36) % 36];
}

typedef Issue = (String reason, int level); // level: 1 = Check, 2 = Suspicious

List<Issue> audit(Bill b, List<Bill> history) {
  final out = <Issue>[];
  if (b.gstin.isNotEmpty && !validGstin(b.gstin)) out.add(('Invalid GSTIN', 2));
  if (b.items.isNotEmpty && (b.items.fold(0.0, (a, c) => a + c) - b.subtotal).abs() > 1) {
    out.add(('Items do not match subtotal', 1));
  }
  if ((b.subtotal + b.tax - b.total).abs() > 1) out.add(('Total mismatch', 1));
  if (history.any((h) => h.store == b.store && h.invoiceNo == b.invoiceNo &&
      h.date == b.date && h.total == b.total)) {
    out.add(('Duplicate bill', 2));
  }
  final t = history.where((h) => h.category == b.category).map((h) => h.total).toList()..sort();
  if (t.length >= 5 && b.total > 3 * t[t.length ~/ 2]) {
    out.add(('3x usual ${b.category} spend', 1));
  }
  return out;
}

String badge(List<Issue> issues) => issues.isEmpty
    ? 'Trusted'
    : issues.any((i) => i.$2 == 2) ? 'Suspicious' : 'Check';