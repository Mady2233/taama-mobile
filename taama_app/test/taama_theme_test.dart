import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/theme/taama_theme.dart';

void main() {
  testWidgets(
      'FilledButton et OutlinedButton dans un Row : pas de largeur infinie',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: TaamaTheme.light(),
      home: Scaffold(
        body: Row(
          children: [
            FilledButton(onPressed: () {}, child: const Text('A')),
            OutlinedButton(onPressed: () {}, child: const Text('B')),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
