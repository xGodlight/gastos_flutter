import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_gastos_personales/models.dart';

void main() {
  group('Validación de gastos', () {
    test('acepta importes enteros y decimales con coma', () {
      expect(parseExpenseAmount('125'), 125);
      expect(parseExpenseAmount('19,50'), 19.5);
    });

    test('rechaza importes vacíos, no numéricos y no positivos', () {
      for (final input in ['', 'abc', '0', '-2', 'NaN']) {
        expect(() => parseExpenseAmount(input), throwsFormatException);
      }
    });

    test('valida descripción y correo', () {
      expect(validateExpenseTitle('  '), isNotNull);
      expect(validateExpenseTitle('Supermercado'), isNull);
      expect(validateEmail('no-es-correo'), isNotNull);
      expect(validateEmail('persona@ejemplo.com'), isNull);
    });
  });
}
