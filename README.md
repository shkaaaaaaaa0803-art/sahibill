

Readme · MD
SahiBill
SahiBill is a bill and receipt auditor. Take a photo of a bill, and SahiBill reads it with AI, checks it with a set of rules, and gives a clear verdict: Trusted, Check or Suspicious, with the reasons.

Built for Cyrus Hack-A-Thon 2026, Round 2 (Problem Statement 3).

Live demo: https://sahibill.vercel.app

Features
Scan a bill with the camera, or upload a photo
AI reads the bill (store, date, items, tax, total, GSTIN and more)
Rule engine checks the bill and shows a Trusted / Check / Suspicious badge with reasons
Review and edit the extracted fields before saving; problem fields are highlighted
"Enter manually" option if AI is not available
"Try sample bill" button to see the audit without using AI
Dashboard: total spend, tax paid, trust overview, spend by category, monthly spend
Flags page: all bills that need a second look, with reasons
Light and dark mode
Works on web and Android
How it works
Scan or upload a bill photo. The image is resized before sending to keep it fast.
Gemini Vision (through Firebase AI Logic, firebase_ai) extracts the bill fields as JSON.
Rule engine (lib/bill.dart) audits the bill:
Invalid GSTIN (checksum check)
Items do not match subtotal
Subtotal + tax does not match total
Tax amount does not match the printed tax rate
Date missing or unclear (day/month)
Duplicate bill
Spend 3x higher than usual for that category
A badge is shown: Trusted (no issues), Check (minor issues), Suspicious (serious issues such as an invalid GSTIN or a duplicate).
The bill is saved to Firestore under the signed-in (anonymous) user.
The Dashboard and Flags pages read the saved bills.
Tech stack
Flutter (Material 3), Dart
Firebase: Authentication (anonymous), Cloud Firestore, Firebase AI Logic (Gemini)
Packages: fl_chart, flutter_animate, image_picker, google_fonts
Web hosting on Vercel
Project structure
lib/
main.dart             App theme and entry point
screens.dart          Home, Scan, Review form, Dashboard, Flags
bill.dart             Bill model and audit rules
services.dart         Gemini prompt, Firestore, anonymous sign-in
firebase_options.dart Firebase config (generated)
Setup
Install Flutter and clone this repo.
Create a Firebase project and enable:
Authentication, then Anonymous sign-in
Cloud Firestore
Firebase AI Logic (Gemini Developer API)
Generate your own Firebase config:
dart pub global activate flutterfire_cli
flutterfire configure
Set Firestore rules so a signed-in user can read and write only their own bills (users/{uid}/bills).
Run:
flutter pub get
flutter run -d chrome
Build for web:
flutter build web --release
Known limitations
AI quota: the free Gemini tier has a daily limit that is shared by the whole project. If the limit is reached, scanning shows an "AI limit reached" message. In that case use Enter manually or Try sample bill, which work without AI.
AI can misread blurry or crumpled bills. That is why every extracted field can be reviewed and edited before saving.
Rule checks depend on the extracted values. A bill with missing fields gets fewer checks.
GSTIN validation is for Indian-style IDs only. Foreign tax IDs are not failed.
Users are anonymous, so bills belong to the browser or device they were scanned on.
Live demo data is per browser, so a fresh visit starts with an empty dashboard.
Team
The duo


