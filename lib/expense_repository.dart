import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'secure_codec.dart';

class ExpenseSnapshot {
  const ExpenseSnapshot({required this.expenses, required this.budgets});

  final List<Expense> expenses;
  final List<Budget> budgets;
}

class ExpenseRepository {
  ExpenseRepository(this._codec);

  final SecureCodec _codec;
  final _uuid = const Uuid();
  Database? _database;

  Future<void> initialize() async {
    final databasePath =
        p.join(await getDatabasesPath(), 'personal_expenses.db');
    _database = await openDatabase(
      databasePath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            icon_code_point INTEGER NOT NULL,
            color_value INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses (
            id TEXT PRIMARY KEY,
            title_enc TEXT NOT NULL,
            amount_enc TEXT NOT NULL,
            category_id TEXT NOT NULL REFERENCES categories(id),
            spent_at TEXT NOT NULL,
            notes_enc TEXT NOT NULL,
            receipt_path TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE budgets (
            id TEXT PRIMARY KEY,
            amount_enc TEXT NOT NULL,
            category_id TEXT REFERENCES categories(id),
            period TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sync_deletions (
            id TEXT NOT NULL,
            entity TEXT NOT NULL,
            PRIMARY KEY (id, entity)
          )
        ''');
      },
    );
    final categoryRows = await _database!.query('categories', limit: 1);
    if (categoryRows.isEmpty) {
      final batch = _database!.batch();
      for (final category in Category.defaults) {
        batch.insert('categories', {
          'id': category.id,
          'name': category.name,
          'icon_code_point': category.iconCodePoint,
          'color_value': category.colorValue,
        });
      }
      await batch.commit(noResult: true);
    }
  }

  Database get _db {
    final database = _database;
    if (database == null)
      throw StateError('La base local no está inicializada.');
    return database;
  }

  Future<List<Category>> getCategories() async {
    final rows = await _db.query('categories', orderBy: 'name');
    return rows
        .map((row) => Category(
              id: row['id']! as String,
              name: row['name']! as String,
              iconCodePoint: row['icon_code_point']! as int,
              colorValue: row['color_value']! as int,
            ))
        .toList();
  }

  Future<ExpenseSnapshot> loadSnapshot() async {
    final expenseRows = await _db.query('expenses', orderBy: 'spent_at DESC');
    final expenses = <Expense>[];
    for (final row in expenseRows) {
      expenses.add(Expense(
        id: row['id']! as String,
        title: await _codec.decryptText(row['title_enc']! as String),
        amount: double.parse(
            await _codec.decryptText(row['amount_enc']! as String)),
        categoryId: row['category_id']! as String,
        date: DateTime.parse(row['spent_at']! as String),
        notes: await _codec.decryptText(row['notes_enc']! as String),
        receiptPath: row['receipt_path'] as String?,
      ));
    }

    final budgetRows = await _db.query('budgets');
    final budgets = <Budget>[];
    for (final row in budgetRows) {
      budgets.add(Budget(
        id: row['id']! as String,
        amount: double.parse(
            await _codec.decryptText(row['amount_enc']! as String)),
        categoryId: row['category_id'] as String?,
        period: row['period']! as String,
      ));
    }
    return ExpenseSnapshot(expenses: expenses, budgets: budgets);
  }

  Future<void> saveExpense(Expense expense) async {
    if (expense.title.trim().isEmpty ||
        !expense.amount.isFinite ||
        expense.amount <= 0) {
      throw const FormatException('El gasto no tiene datos válidos.');
    }
    final oldRows = await _db.query(
      'expenses',
      columns: ['receipt_path'],
      where: 'id = ?',
      whereArgs: [expense.id],
      limit: 1,
    );
    await _db.transaction((transaction) async {
      await transaction.insert(
        'expenses',
        {
          'id': expense.id,
          'title_enc': await _codec.encryptText(expense.title.trim()),
          'amount_enc': await _codec.encryptText(expense.amount.toString()),
          'category_id': expense.categoryId,
          'spent_at': expense.date.toIso8601String(),
          'notes_enc': await _codec.encryptText(expense.notes.trim()),
          'receipt_path': expense.receiptPath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'sync_deletions',
        where: 'id = ? AND entity = ?',
        whereArgs: [expense.id, 'expenses'],
      );
    });
    final oldPath =
        oldRows.isEmpty ? null : oldRows.first['receipt_path'] as String?;
    if (oldPath != null && oldPath != expense.receiptPath) {
      await _removeReceipt(oldPath);
    }
  }

  Future<String> saveReceipt(String expenseId, List<int> imageBytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final receiptDirectory = Directory(p.join(directory.path, 'receipts'));
    await receiptDirectory.create(recursive: true);
    final file =
        File(p.join(receiptDirectory.path, '$expenseId-${_uuid.v4()}.enc'));
    await file.writeAsBytes(await _codec.encryptBytes(imageBytes), flush: true);
    return p.join('receipts', p.basename(file.path));
  }

  Future<void> deleteExpense(String id) async {
    final rows = await _db.query(
      'expenses',
      columns: ['receipt_path'],
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.transaction((transaction) async {
      await transaction.insert(
        'sync_deletions',
        {'id': id, 'entity': 'expenses'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete('expenses', where: 'id = ?', whereArgs: [id]);
    });
    final receiptPath =
        rows.isEmpty ? null : rows.first['receipt_path'] as String?;
    if (receiptPath != null) await _removeReceipt(receiptPath);
  }

  Future<Uint8List?> readReceipt(String? path) async {
    if (path == null) return null;
    final file = await _receiptFile(path);
    return _codec.decryptBytes(await file.readAsBytes());
  }

  Future<void> _removeReceipt(String path) async {
    final file = await _receiptFile(path);
    if (await file.exists()) await file.delete();
  }

  Future<File> _receiptFile(String path) async {
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, path));
  }

  Future<void> saveBudget(Budget budget) async {
    if (!budget.amount.isFinite || budget.amount <= 0) {
      throw const FormatException('El presupuesto debe ser mayor que cero.');
    }
    await _db.transaction((transaction) async {
      await transaction.insert(
        'budgets',
        {
          'id': budget.id,
          'amount_enc': await _codec.encryptText(budget.amount.toString()),
          'category_id': budget.categoryId,
          'period': budget.period,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'sync_deletions',
        where: 'id = ? AND entity = ?',
        whereArgs: [budget.id, 'budgets'],
      );
    });
  }

  Future<void> deleteBudget(String id) async {
    await _db.transaction((transaction) async {
      await transaction.insert(
        'sync_deletions',
        {'id': id, 'entity': 'budgets'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete('budgets', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> replaceRemoteData(ExpenseSnapshot snapshot) async {
    await _db.transaction((transaction) async {
      await transaction.delete('expenses');
      await transaction.delete('budgets');
      for (final expense in snapshot.expenses) {
        await transaction.insert('expenses', {
          'id': expense.id,
          'title_enc': await _codec.encryptText(expense.title),
          'amount_enc': await _codec.encryptText(expense.amount.toString()),
          'category_id': expense.categoryId,
          'spent_at': expense.date.toIso8601String(),
          'notes_enc': await _codec.encryptText(expense.notes),
          'receipt_path': null,
        });
      }
      for (final budget in snapshot.budgets) {
        await transaction.insert('budgets', {
          'id': budget.id,
          'amount_enc': await _codec.encryptText(budget.amount.toString()),
          'category_id': budget.categoryId,
          'period': budget.period,
        });
      }
    });
  }

  Future<Map<String, Set<String>>> loadPendingDeletions() async {
    final rows = await _db.query('sync_deletions');
    final deletions = <String, Set<String>>{};
    for (final row in rows) {
      final entity = row['entity']! as String;
      deletions.putIfAbsent(entity, () => <String>{}).add(row['id']! as String);
    }
    return deletions;
  }

  Future<void> clearPendingDeletions(
      Map<String, Set<String>> acknowledged) async {
    await _db.transaction((transaction) async {
      for (final entry in acknowledged.entries) {
        for (final id in entry.value) {
          await transaction.delete(
            'sync_deletions',
            where: 'id = ? AND entity = ?',
            whereArgs: [id, entry.key],
          );
        }
      }
    });
  }

  String newId() => _uuid.v4();
}
