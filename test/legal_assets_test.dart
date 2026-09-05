import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legal markdown assets are loadable', () async {
    final privacy = await rootBundle.loadString('assets/legal/privacy_policy.md');
    expect(privacy, contains('The short version'));
    final terms = await rootBundle.loadString('assets/legal/terms_of_use.md');
    expect(terms, contains('Use of the App'));
  });
}
