import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'bill.dart';

const _prompt = '''
Read this Indian bill/receipt. Return ONLY JSON with keys:
store (string), invoiceNo (string), date (YYYY-MM-DD), gstin (string, "" if absent),
category (one of Food, Travel, Supplies, Utilities, Other),
items (list of line-item amounts as numbers), subtotal, tax, total (numbers).
Copy numbers exactly as printed. Do not guess or fix them.
''';

final _model = FirebaseAI.googleAI().generativeModel(
  model: 'gemini-3.8-flash',
  generationConfig: GenerationConfig(responseMimeType: 'application/json'),
);

Future<Bill> extractBill(Uint8List img, String mime) async {
  final res = await _model.generateContent([
    Content.multi([TextPart(_prompt), InlineDataPart(mime, img)]),
  ]);
  return Bill.fromMap(jsonDecode(res.text!));
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
