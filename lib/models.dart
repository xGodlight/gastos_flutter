class Category {
  const Category({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    required this.colorValue,
  });

  final String id;
  final String name;
  final int iconCodePoint;
  final int colorValue;

  static const defaults = <Category>[
    Category(
        id: 'food',
        name: 'Comida',
        iconCodePoint: 0xe25a,
        colorValue: 0xfff97316),
    Category(
        id: 'transport',
        name: 'Transporte',
        iconCodePoint: 0xe1d7,
        colorValue: 0xff3b82f6),
    Category(
        id: 'home',
        name: 'Hogar',
        iconCodePoint: 0xe318,
        colorValue: 0xff8b5cf6),
    Category(
        id: 'health',
        name: 'Salud',
        iconCodePoint: 0xe3f3,
        colorValue: 0xff14b8a6),
    Category(
        id: 'leisure',
        name: 'Ocio',
        iconCodePoint: 0xe40f,
        colorValue: 0xffec4899),
    Category(
        id: 'other',
        name: 'Otros',
        iconCodePoint: 0xe5d3,
        colorValue: 0xff64748b),
  ];
}

class Expense {
  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.notes = '',
    this.receiptPath,
  });

  final String id;
  final String title;
  final double amount;
  final String categoryId;
  final DateTime date;
  final String notes;
  final String? receiptPath;

  Expense copyWith({
    String? title,
    double? amount,
    String? categoryId,
    DateTime? date,
    String? notes,
    String? receiptPath,
    bool clearReceipt = false,
  }) {
    return Expense(
      id: id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      receiptPath: clearReceipt ? null : receiptPath ?? this.receiptPath,
    );
  }
}

class Budget {
  const Budget({
    required this.id,
    required this.amount,
    this.categoryId,
    this.period = 'weekly',
  });

  final String id;
  final double amount;
  final String? categoryId;
  final String period;
}

double parseExpenseAmount(String input) {
  final value = double.tryParse(input.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0) {
    throw const FormatException('Ingresa un importe mayor que cero.');
  }
  if (value > 999999999) {
    throw const FormatException('El importe supera el límite permitido.');
  }
  return value;
}

String? validateExpenseTitle(String? value) {
  final title = value?.trim() ?? '';
  if (title.isEmpty) return 'Describe el gasto.';
  if (title.length > 80) return 'Usa 80 caracteres o menos.';
  return null;
}

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Ingresa un correo válido.';
  }
  return null;
}

String? validatePassword(String? value) {
  if ((value ?? '').length < 8)
    return 'La contraseña debe tener al menos 8 caracteres.';
  return null;
}

List<Expense> filterExpenses(
  List<Expense> expenses, {
  required DateTime now,
  required bool currentMonthOnly,
  String query = '',
}) {
  final monthStart = DateTime(now.year, now.month);
  final normalizedQuery = query.trim().toLowerCase();
  return expenses.where((expense) {
    final matchesMonth =
        !currentMonthOnly || !expense.date.isBefore(monthStart);
    final matchesQuery = expense.title.toLowerCase().contains(normalizedQuery);
    return matchesMonth && matchesQuery;
  }).toList();
}
