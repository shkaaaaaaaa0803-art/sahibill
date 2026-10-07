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

final _model = FirebaseAI.googleAI().generativeModel(
  model: 'gemini-3.8-flash',
  generationConfig: GenerationConfig(responseMimeType: 'application/json'),
);

Future<Bill> extractBill(Uint8List img, String mime) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final res = await _model.generateContent([
        Content.multi([TextPart(_prompt), InlineDataPart(mime, img)]),
      ]).timeout(const Duration(seconds: 45));
      return Bill.fromMap(jsonDecode(res.text!));
    } catch (e) {
      lastError = e;
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }
  throw lastError!;
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