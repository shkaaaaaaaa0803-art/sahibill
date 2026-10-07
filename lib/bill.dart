import 'dart:math' as math;

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  }
  return 0;
}

String _str(dynamic v) => v == null ? '' : v.toString().trim();

class LineItem {
  final String name;
  final double qty, unitPrice, amount;
  const LineItem({
    required this.name,
    this.qty = 1,
    this.unitPrice = 0,
    this.amount = 0,
  });

  factory LineItem.fromMap(Map<String, dynamic> m) => LineItem(
    name: _str(m['name']),
    qty: _num(m['qty']) == 0 ? 1.0 : _num(m['qty']),
    unitPrice: _num(m['unitPrice']),
    amount: _num(m['amount']),
  );

  Map<String, dynamic> toMap() =>
      {'name': name, 'qty': qty, 'unitPrice': unitPrice, 'amount': amount};
}

class Bill {
  // original fields (kept, so old Firestore bills still load)
  final String store, invoiceNo, date, gstin, category;
  final double subtotal, tax, total;
  final List<double> items;

  // new fields
  final String currency, address, time, payment, fiscalId;
  final double taxRate;
  final bool dateAmbiguous;
  final List<LineItem> lines;

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
    this.currency = 'INR',
    this.address = '',
    this.time = '',
    this.payment = '',
    this.fiscalId = '',
    this.taxRate = 0,
    this.dateAmbiguous = false,
    this.lines = const [],
  });

  factory Bill.fromMap(Map<String, dynamic> m) {
    final lines = [
      for (final l in (m['lines'] as List? ?? []))
        if (l is Map) LineItem.fromMap(Map<String, dynamic>.from(l)),
    ];
    final items = lines.isNotEmpty
        ? [for (final l in lines) l.amount]
        : [for (final i in (m['items'] as List? ?? [])) _num(i)];
    final cur = _str(m['currency']).toUpperCase();
    return Bill(
      store: _str(m['store']),
      invoiceNo: _str(m['invoiceNo']),
      date: _str(m['date']),
      gstin: _str(m['gstin']).toUpperCase(),
      category: _str(m['category']).isEmpty ? 'Other' : _str(m['category']),
      subtotal: _num(m['subtotal']),
      tax: _num(m['tax']),
      total: _num(m['total']),
      items: items,
      currency: cur.isEmpty ? 'INR' : cur,
      address: _str(m['address']),
      time: _str(m['time']),
      payment: _str(m['payment']),
      fiscalId: _str(m['fiscalId']),
      taxRate: _num(m['taxRate']),
      dateAmbiguous: m['dateAmbiguous'] == true,
      lines: lines,
    );
  }

  Map<String, dynamic> toMap() => {
    'store': store, 'invoiceNo': invoiceNo, 'date': date, 'gstin': gstin,
    'category': category, 'subtotal': subtotal, 'tax': tax,
    'total': total, 'items': items,
    'currency': currency, 'address': address, 'time': time,
    'payment': payment, 'fiscalId': fiscalId, 'taxRate': taxRate,
    'dateAmbiguous': dateAmbiguous,
    'lines': [for (final l in lines) l.toMap()],
  };
}

String money(String cur, double v) {
  const sym = {'INR': '₹', 'USD': '\$', 'EUR': '€', 'GBP': '£'};
  final c = cur.isEmpty ? 'INR' : cur.toUpperCase();
  final s = v.toStringAsFixed(2);
  return sym.containsKey(c) ? '${sym[c]}$s' : '$c $s';
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

// level: 1 = Check, 2 = Suspicious. fields = which form fields to highlight.
typedef Issue = (String reason, int level, List<String> fields);

List<Issue> audit(Bill b, List<Bill> history) {
  final out = <Issue>[];

  // GSTIN check only for Indian-style IDs (start with 2 digits).
  // Foreign tax IDs (e.g. RO41040320) are skipped, not failed.
  if (RegExp(r'^\d{2}').hasMatch(b.gstin) && !validGstin(b.gstin)) {
    out.add(('Invalid GSTIN', 2, ['gstin']));
  }

  // Items vs subtotal (or vs total when prices already include tax)
  final itemSum = b.items.fold(0.0, (a, c) => a + c);
  final target = b.subtotal > 0 ? b.subtotal : b.total;
  if (b.items.isNotEmpty && target > 0) {
    final okSub = (itemSum - target).abs() <= 1;
    final okTotal = (itemSum - b.total).abs() <= 1;
    if (!okSub && !okTotal) {
      out.add(('Items do not match subtotal', 1, ['subtotal', 'total']));
    }
  }

  // Total: subtotal + tax = total (tax extra) OR subtotal = total (tax included)
  if (b.subtotal > 0) {
    final exclusive = (b.subtotal + b.tax - b.total).abs() <= 1;
    final inclusive = (b.subtotal - b.total).abs() <= 1;
    if (!exclusive && !inclusive) {
      out.add(('Total mismatch', 1, ['subtotal', 'tax', 'total']));
    }
  }

  // Tax amount vs printed tax rate (works for tax-included and tax-extra bills)
  if (b.taxRate > 0 && b.tax > 0 && b.total > 0) {
    final r = b.taxRate;
    final incl = b.total * r / (100 + r);
    final base = b.subtotal > 0 ? b.subtotal : b.total - b.tax;
    final excl = base * r / 100;
    final tol = math.max(0.1, b.total * 0.01);
    if ((b.tax - incl).abs() > tol && (b.tax - excl).abs() > tol) {
      final rs = r.toStringAsFixed(r % 1 == 0 ? 0 : 1);
      out.add(('Tax does not match $rs% rate', 1, ['tax', 'taxRate']));
    }
  }

  // NEW: missing date. A bill with no date cannot be trusted.
  if (b.date.isEmpty) {
    out.add(('Date missing. Please add it', 1, ['date']));
  } else if (b.dateAmbiguous) {
    out.add(('Date unclear (day/month). Please confirm', 1, ['date']));
  }

  if (history.any((h) =>
  (h.store == b.store && h.invoiceNo == b.invoiceNo &&
      h.date == b.date && h.total == b.total) ||
      (b.fiscalId.isNotEmpty && b.invoiceNo.isNotEmpty &&
          h.fiscalId == b.fiscalId && h.invoiceNo == b.invoiceNo))) {
    out.add(('Duplicate bill', 2, ['invoiceNo', 'total']));
  }

  final t = history.where((h) => h.category == b.category).map((h) => h.total).toList()..sort();
  if (t.length >= 5 && b.total > 3 * t[t.length ~/ 2]) {
    out.add(('3x usual ${b.category} spend', 1, ['total']));
  }
  return out;
}

String badge(List<Issue> issues) => issues.isEmpty
    ? 'Trusted'
    : issues.any((i) => i.$2 == 2) ? 'Suspicious' : 'Check';