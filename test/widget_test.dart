import 'package:flutter_test/flutter_test.dart';
import 'package:print_app/main.dart';

void main() {
  test('ar() converts digits to Arabic-Indic', () {
    expect(ar(123), '١٢٣');
  });

  test('PrintModel.update notifies listeners', () {
    final m = PrintModel();
    var calls = 0;
    m.addListener(() => calls++);
    m.update(() => m.copies = 2);
    expect(m.copies, 2);
    expect(calls, 1);
  });
}