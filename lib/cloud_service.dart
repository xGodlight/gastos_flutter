import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'expense_repository.dart';
import 'models.dart';

class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FB_API_KEY');
  static const appId = String.fromEnvironment('FB_APP_ID');
  static const senderId = String.fromEnvironment('FB_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FB_PROJECT_ID');

  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty;
  static bool get hasAnyValue =>
      apiKey.isNotEmpty || appId.isNotEmpty || senderId.isNotEmpty || projectId.isNotEmpty;

  static Future<void> initialize() async {
    if (!hasAnyValue) return;
    if (!isConfigured) {
      throw StateError('La configuración de Firebase está incompleta.');
    }
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
      ),
    );
  }
}

class CloudService {
  CloudService(this._secureStorage);

  static const _ownerKey = 'firestore_local_data_owner';
  final FlutterSecureStorage _secureStorage;

  bool get isConfigured => FirebaseConfig.isConfigured;
  User? get currentUser => isConfigured ? FirebaseAuth.instance.currentUser : null;

  Future<bool> claimLocalData(String userId) async {
    final owner = await _secureStorage.read(key: _ownerKey);
    if (owner != null && owner != userId) return false;
    if (owner == null) await _secureStorage.write(key: _ownerKey, value: userId);
    return true;
  }

  Future<UserCredential> signIn(String email, String password) =>
      FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

  Future<UserCredential> createAccount(String email, String password) =>
      FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  Future<void> sync(String userId, ExpenseSnapshot snapshot) async {
    final firestore = FirebaseFirestore.instance;
    final userPath = firestore.collection('users').doc(userId);
    final expenses = <String, Map<String, dynamic>>{
      for (final expense in snapshot.expenses)
        expense.id: {
        'title': expense.title,
        'amount': expense.amount,
        'categoryId': expense.categoryId,
        'date': expense.date.toIso8601String(),
        'notes': expense.notes,
        },
    };
    final budgets = <String, Map<String, dynamic>>{
      for (final budget in snapshot.budgets)
        budget.id: {
        'amount': budget.amount,
        'categoryId': budget.categoryId,
        'period': budget.period,
        },
    };
    await _syncCollection(userPath.collection('expenses'), expenses);
    await _syncCollection(userPath.collection('budgets'), budgets);
  }

  Future<void> _syncCollection(
    CollectionReference<Map<String, dynamic>> collection,
    Map<String, Map<String, dynamic>> records,
  ) async {
    final existing = await collection.get();
    final changes = <void Function(WriteBatch)>[
      for (final document in existing.docs)
        if (!records.containsKey(document.id))
          (batch) => batch.delete(document.reference),
      for (final entry in records.entries)
        (batch) => batch.set(collection.doc(entry.key), entry.value),
    ];
    for (var start = 0; start < changes.length; start += 400) {
      final batch = FirebaseFirestore.instance.batch();
      for (final change in changes.skip(start).take(400)) {
        change(batch);
      }
      await batch.commit();
    }
  }

  Future<ExpenseSnapshot> download(String userId) async {
    final userPath = FirebaseFirestore.instance.collection('users').doc(userId);
    final expenseDocs = await userPath.collection('expenses').get();
    final budgetDocs = await userPath.collection('budgets').get();
    final expenses = expenseDocs.docs.map((doc) {
      final data = doc.data();
      final title = data['title'] as String?;
      final amount = data['amount'];
      final date = DateTime.tryParse(data['date'] as String? ?? '');
      final categoryId = data['categoryId'] as String? ?? 'other';
      final notes = data['notes'] as String? ?? '';
      if (title == null || title.trim().isEmpty || title.length > 80) {
        throw FormatException('Descripción remota inválida para el gasto ${doc.id}.');
      }
      if (amount is! num || !amount.isFinite || amount <= 0) {
        throw FormatException('Importe remoto inválido para el gasto ${doc.id}.');
      }
      if (date == null || notes.length > 300) {
        throw FormatException('Fecha o notas remotas inválidas para el gasto ${doc.id}.');
      }
      if (!Category.defaults.any((category) => category.id == categoryId)) {
        throw FormatException('Categoría remota desconocida: $categoryId');
      }
      return Expense(
        id: doc.id,
        title: title,
        amount: amount.toDouble(),
        categoryId: categoryId,
        date: date,
        notes: notes,
      );
    }).toList();
    final budgets = budgetDocs.docs.map((doc) {
      final data = doc.data();
      final amount = data['amount'];
      final categoryId = data['categoryId'] as String?;
      if (amount is! num || !amount.isFinite || amount <= 0) {
        throw FormatException('Importe remoto inválido para el presupuesto ${doc.id}.');
      }
      if (categoryId != null &&
          !Category.defaults.any((category) => category.id == categoryId)) {
        throw FormatException('Categoría remota desconocida: $categoryId');
      }
      return Budget(
        id: doc.id,
        amount: amount.toDouble(),
        categoryId: categoryId,
        period: data['period'] as String? ?? 'weekly',
      );
    }).toList();
    return ExpenseSnapshot(expenses: expenses, budgets: budgets);
  }
}
