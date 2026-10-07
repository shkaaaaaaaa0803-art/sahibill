import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'bill.dart';

const _prompt = '''
Read this receipt or bill (any country). Return ONLY JSON with these keys:
store (string), address (string),
gstin (tax registration number exactly as printed: GSTIN, VAT no., CUI etc; "" if absent),
invoiceNo (bill / receipt number as printed; if a sale or transaction number AND a fiscal receipt number are both printed, use the fiscal receipt number),
fiscalId (fiscal memory or device ID; "" if absent),
date (YYYY-MM-DD), dateAmbiguous (true if day and month are both 12 or less and could be swapped; assume DD/MM),
time (HH:MM, "" if absent),
currency (ISO code such as INR, RON, USD, EUR),
payment (Cash, Card, UPI or Other; "" if absent),
category (one of Food, Travel, Supplies, Utilities, Other),
lines (list of objects: name, qty, unitPrice, amount),
subtotal (amount before tax; 0 if not printed),
taxRate (tax percent such as 18 or 9; 0 if not printed),
tax (tax amount; 0 if not printed),
total (final amount paid).
Copy numbers exactly as printed. Do not guess or fix them.
Use "" or 0 for anything not printed.
Do NOT extract names of cashiers, waiters or customers.
''';

// Change only these two lines if a model name needs to change.
const _modelName = 'gemini-3.8-flash';
const _fallbackModelName = 'gemini-3.5-flash-lite';

GenerativeModel _make(String name) => FirebaseAI.googleAI().generativeModel(
  model: name,
  generationConfig: GenerationConfig(responseMimeType: 'application/json'),
);

final _primary = _make(_modelName);
final _fallback = _make(_fallbackModelName);

const _attempts = 2;
const _timeout = Duration(seconds: 30);

bool _isQuota(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('quota') ||
      s.contains('429') ||
      s.contains('rate-limit') ||
      s.contains('rate limit') ||
      s.contains('resource_exhausted') ||
      s.contains('resource exhausted');
}

/// Turns any scan error into (title, short message) for the error card.
(String, String) friendlyError(Object e) {
  if (_isQuota(e)) {
    return (
    'AI limit reached',
    'The free AI quota is used up for now. Enter the bill manually, or try again later.',
    );
  }
  final s = e.toString().toLowerCase();
  if (e is TimeoutException || s.contains('timeout')) {
    return (
    'Taking too long',
    'The AI did not answer in time. Check your internet and try again.',
    );
  }
  return (
  'Could not read this bill',
  'Try a clearer photo, or enter the bill manually.',
  );
}

Future<Bill> extractBill(Uint8List img, String mime) async {
  Object? lastError;
  Object? quotaError;
  for (final model in [_primary, _fallback]) {
    var quota = false;
    for (var attempt = 0; attempt < _attempts; attempt++) {
      try {
        final res = await model.generateContent([
          Content.multi([TextPart(_prompt), InlineDataPart(mime, img)]),
        ]).timeout(_timeout);
        return Bill.fromMap(jsonDecode(res.text!));
      } catch (e) {
        lastError = e;
        if (_isQuota(e)) {
          quota = true;
          quotaError = e;
          break; // do not retry on quota, move to the fallback model
        }
        if (attempt < _attempts - 1) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    if (!quota) break; // only a quota error moves on to the fallback model
  }
  throw quotaError ?? lastError!;
}

Future<CollectionReference<Map<String, dynamic>>> _bills() async {
  final auth = FirebaseAuth.instance;
  final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  return FirebaseFirestore.instance.collection('users/${user.uid}/bills');
}

Future<void> saveBill(Bill b) async => (await _bills())
    .add({...b.toMap(), 'createdAt': FieldValue.serverTimestamp()});

Future<List<Bill>> loadBills() async {
  final snap = await (await _bills()).orderBy('createdAt', descending: true).get();
  return [for (final d in snap.docs) Bill.fromMap(d.data())];
}