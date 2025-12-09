import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omi_local/main.dart';

void main() {
  testWidgets('App builds successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const OmiLocalApp());
    expect(find.text('Omi Local'), findsOneWidget);
  });
}
