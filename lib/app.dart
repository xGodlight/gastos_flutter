// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'budget_notifications.dart';
import 'auth_error_message.dart';
import 'cloud_service.dart';
import 'expense_repository.dart';
import 'models.dart';

const _ink = Color(0xff16251f);
const _green = Color(0xff14804a);
const _canvas = Color(0xfff4f7f4);
final _currency =
    NumberFormat.currency(locale: 'es_MX', symbol: '\$', decimalDigits: 2);

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({
    required this.repository,
    required this.cloud,
    required this.notifications,
    super.key,
  });

  final ExpenseRepository repository;
  final CloudService cloud;
  final BudgetNotifications notifications;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mis gastos',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: _canvas,
          colorScheme: ColorScheme.fromSeed(seedColor: _green),
          appBarTheme: const AppBarTheme(
            backgroundColor: _canvas,
            foregroundColor: _ink,
            centerTitle: false,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        home: DashboardPage(
          repository: repository,
          cloud: cloud,
          notifications: notifications,
        ),
      );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.repository,
    required this.cloud,
    required this.notifications,
    super.key,
  });

  final ExpenseRepository repository;
  final CloudService cloud;
  final BudgetNotifications notifications;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  ExpenseSnapshot _snapshot =
      const ExpenseSnapshot(expenses: <Expense>[], budgets: <Budget>[]);
  List<Category> _categories = Category.defaults;
  bool _loading = true;
  bool _syncing = false;
  bool _cloudReady = false;
  String? _error;
  User? _user;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.cloud.isConfigured) {
      _user = widget.cloud.currentUser;
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen((user) {
        if (!mounted) return;
        setState(() {
          _user = user;
          _cloudReady = false;
          if (user == null) _error = null;
        });
        if (user != null) _syncFromCloud(user.uid);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.loadSnapshot(),
        widget.repository.getCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = results[0] as ExpenseSnapshot;
        _categories = results[1] as List<Category>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error al leer los datos locales: $error';
      });
    }
  }

  Future<void> _syncFromCloud(String userId) async {
    setState(() => _syncing = true);
    try {
      if (!await widget.cloud.claimLocalData(userId)) {
        await widget.cloud.signOut();
        throw StateError('Los datos locales están vinculados a otra cuenta.');
      }
      final remote = await widget.cloud.download(userId);
      final local = await widget.repository.loadSnapshot();
      final pendingDeletions = await widget.repository.loadPendingDeletions();
      final deletedExpenseIds = pendingDeletions['expenses'] ?? <String>{};
      final deletedBudgetIds = pendingDeletions['budgets'] ?? <String>{};
      final mergedExpenses = <String, Expense>{
        for (final expense in remote.expenses)
          if (!deletedExpenseIds.contains(expense.id)) expense.id: expense,
      };
      for (final expense in local.expenses) {
        mergedExpenses[expense.id] = expense.copyWith(
          receiptPath:
              expense.receiptPath ?? mergedExpenses[expense.id]?.receiptPath,
        );
      }
      final mergedBudgets = <String, Budget>{
        for (final budget in remote.budgets)
          if (!deletedBudgetIds.contains(budget.id)) budget.id: budget,
        for (final budget in local.budgets) budget.id: budget,
      };
      final merged = ExpenseSnapshot(
        expenses: mergedExpenses.values.toList(),
        budgets: mergedBudgets.values.toList(),
      );
      await widget.repository.replaceRemoteData(merged);
      await _load();
      await widget.cloud.sync(userId, merged);
      await widget.repository.clearPendingDeletions(pendingDeletions);
      if (mounted) {
        setState(() {
          _cloudReady = true;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Sincronización pendiente: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncLocalToCloud() async {
    final user = _user;
    if (user == null || !_cloudReady) return;
    setState(() => _syncing = true);
    try {
      if (!await widget.cloud.claimLocalData(user.uid)) {
        await widget.cloud.signOut();
        throw StateError('Los datos locales están vinculados a otra cuenta.');
      }
      await widget.cloud.sync(user.uid, await widget.repository.loadSnapshot());
      await widget.repository.clearPendingDeletions(
        await widget.repository.loadPendingDeletions(),
      );
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted)
        setState(
            () => _error = 'Guardado local; sincronización pendiente: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _saveExpense(Expense expense) async {
    await widget.repository.saveExpense(expense);
    await _load();
    final budget = _snapshot.budgets.firstWhere(
      (item) => item.categoryId == null,
      orElse: () => const Budget(id: '', amount: 0),
    );
    final spent = _snapshot.expenses
        .where((item) =>
            item.date.isAfter(DateTime.now().subtract(const Duration(days: 7))))
        .fold<double>(0, (total, item) => total + item.amount);
    await widget.notifications.updateThresholdAlert(
      exceededThreshold: budget.amount > 0 && spent / budget.amount >= 0.8,
    );
    await _syncLocalToCloud();
  }

  Future<void> _deleteExpense(Expense expense) async {
    try {
      await widget.repository.deleteExpense(expense.id);
      await _load();
      await _syncLocalToCloud();
    } catch (error) {
      _showMessage('No se pudo eliminar el gasto: $error');
    }
  }

  Future<void> _showExpenseForm([Expense? expense]) async {
    final saved = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _canvas,
      builder: (context) => ExpenseForm(
        repository: widget.repository,
        categories: _categories,
        initial: expense,
      ),
    );
    if (saved == null) return;
    try {
      await _saveExpense(saved);
      if (mounted) _showMessage('Gasto guardado.');
    } catch (error) {
      _showMessage('No se pudo guardar el gasto: $error');
    }
  }

  Future<void> _showBudgetForm() async {
    final current = _snapshot.budgets.firstWhere(
      (item) => item.categoryId == null,
      orElse: () => Budget(id: widget.repository.newId(), amount: 0),
    );
    final controller = TextEditingController(
      text: current.amount > 0 ? current.amount.toStringAsFixed(2) : '',
    );
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Presupuesto semanal'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Límite semanal'),
            validator: (input) {
              try {
                parseExpenseAmount(input ?? '');
                return null;
              } on FormatException catch (error) {
                return error.message;
              }
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, parseExpenseAmount(controller.text));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await widget.repository.saveBudget(
        Budget(id: current.id, amount: value, period: 'weekly'),
      );
      await _load();
      final spent = _snapshot.expenses
          .where((item) => item.date
              .isAfter(DateTime.now().subtract(const Duration(days: 7))))
          .fold<double>(0, (total, item) => total + item.amount);
      await widget.notifications.updateThresholdAlert(
        exceededThreshold: spent / value >= 0.8,
      );
      await _syncLocalToCloud();
    } catch (error) {
      _showMessage('No se pudo guardar el presupuesto: $error');
    }
  }

  Future<void> _showAccountDialog() async {
    if (_user != null) {
      await widget.cloud.signOut();
      return;
    }
    if (!widget.cloud.isConfigured) {
      _showMessage(
          'Configura Firebase para habilitar inicio de sesión y sincronización.');
      return;
    }
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final key = GlobalKey<FormState>();
    var createAccount = false;
    var submitting = false;
    var obscurePassword = true;
    String? authError;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(createAccount ? 'Crear cuenta' : 'Iniciar sesión'),
          content: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  keyboardType: TextInputType.emailAddress,
                  validator: validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    suffixIcon: IconButton(
                      tooltip: obscurePassword
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  obscureText: obscurePassword,
                  validator: validatePassword,
                ),
                if (authError != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      authError!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      if (!createAccount)
                        TextButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final emailError =
                                      validateEmail(emailController.text);
                                  if (emailError != null) {
                                    setDialogState(
                                        () => authError = emailError);
                                    return;
                                  }
                                  setDialogState(() {
                                    submitting = true;
                                    authError = null;
                                  });
                                  try {
                                    await widget.cloud.sendPasswordReset(
                                        emailController.text);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Si el correo está registrado, recibirás instrucciones para restablecer la contraseña.',
                                          ),
                                        ),
                                      );
                                    }
                                  } on FirebaseAuthException catch (error) {
                                    if (context.mounted) {
                                      setDialogState(
                                        () => authError =
                                            authErrorMessage(error.code),
                                      );
                                    }
                                  } catch (_) {
                                    if (context.mounted) {
                                      setDialogState(
                                        () => authError =
                                            authErrorMessage('unexpected'),
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setDialogState(() => submitting = false);
                                    }
                                  }
                                },
                          child: const Text('Olvidé mi contraseña'),
                        ),
                      TextButton(
                        onPressed: submitting
                            ? null
                            : () => setDialogState(() {
                                  createAccount = !createAccount;
                                  authError = null;
                                }),
                        child: Text(
                            createAccount ? 'Ya tengo cuenta' : 'Crear cuenta'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!key.currentState!.validate()) return;
                      setDialogState(() {
                        submitting = true;
                        authError = null;
                      });
                      try {
                        if (createAccount) {
                          await widget.cloud.createAccount(
                            emailController.text,
                            passwordController.text,
                          );
                        } else {
                          await widget.cloud.signIn(
                            emailController.text,
                            passwordController.text,
                          );
                        }
                        if (context.mounted) Navigator.pop(context);
                      } on FirebaseAuthException catch (error) {
                        if (context.mounted) {
                          setDialogState(
                              () => authError = authErrorMessage(error.code));
                        }
                      } catch (_) {
                        if (context.mounted) {
                          setDialogState(
                            () => authError = authErrorMessage('unexpected'),
                          );
                        }
                      } finally {
                        if (context.mounted) {
                          setDialogState(() => submitting = false);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    passwordController.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final weeklyBudget = _snapshot.budgets.firstWhere(
      (item) => item.categoryId == null,
      orElse: () => const Budget(id: '', amount: 0),
    );
    final now = DateTime.now();
    final weekExpenses = _snapshot.expenses
        .where(
            (item) => item.date.isAfter(now.subtract(const Duration(days: 7))))
        .toList();
    final weeklySpent =
        weekExpenses.fold<double>(0, (sum, item) => sum + item.amount);
    final categoryNames = {for (final item in _categories) item.id: item};
    final totalSpent =
        _snapshot.expenses.fold<double>(0, (sum, item) => sum + item.amount);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis gastos',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: _user == null ? 'Iniciar sesión' : 'Cerrar sesión',
            onPressed: _showAccountDialog,
            icon: Icon(_user == null
                ? Icons.cloud_outlined
                : Icons.cloud_done_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _showExpenseForm(),
        icon: const Icon(Icons.add),
        label: const Text('Añadir gasto'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _snapshot.expenses.isEmpty && _categories.isEmpty
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    children: [
                      if (_error != null) ...[
                        _ErrorBanner(
                          message: _error!,
                          onRetry: _user == null
                              ? null
                              : () => _syncFromCloud(_user!.uid),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _SummaryCard(
                          total: totalSpent, count: _snapshot.expenses.length),
                      const SizedBox(height: 16),
                      _BudgetCard(
                        spent: weeklySpent,
                        budget: weeklyBudget.amount,
                        onEdit: _showBudgetForm,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Por categoría',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text('${_snapshot.expenses.length} gastos'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _CategoryChart(
                          expenses: _snapshot.expenses,
                          categories: categoryNames),
                      const SizedBox(height: 24),
                      const Text(
                        'Movimientos recientes',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (_snapshot.expenses.isEmpty)
                        const _EmptyState()
                      else
                        ..._snapshot.expenses.map((expense) {
                          final category = categoryNames[expense.categoryId];
                          return _ExpenseTile(
                            expense: expense,
                            category: category,
                            onEdit: () => _showExpenseForm(expense),
                            onDelete: () => _deleteExpense(expense),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.total, required this.count});

  final double total;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gasto registrado',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text(
              _currency.format(total),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Text('$count movimientos',
                style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.spent,
    required this.budget,
    required this.onEdit,
  });

  final double spent;
  final double budget;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ratio =
        budget > 0 ? (spent / budget).clamp(0.0, 1.0).toDouble() : 0.0;
    final exceeded = budget > 0 && spent >= budget;
    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Presupuesto semanal',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'Editar presupuesto',
                  onPressed: onEdit,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            if (budget == 0)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Define un límite y recibe un aviso al llegar al 80%.'),
              )
            else ...[
              LinearProgressIndicator(
                value: ratio,
                minHeight: 9,
                borderRadius: BorderRadius.circular(8),
                color: exceeded ? Colors.red : _green,
                backgroundColor: _canvas,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text('Gastado: ${_currency.format(spent)}')),
                  Text('Límite: ${_currency.format(budget)}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryChart extends StatelessWidget {
  const _CategoryChart({required this.expenses, required this.categories});

  final List<Expense> expenses;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final expense in expenses) {
      totals.update(
        expense.categoryId,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    if (totals.isEmpty) {
      return const Card(
        color: Colors.white,
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Agrega tu primer gasto para ver el resumen.'),
        ),
      );
    }
    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 190,
          child: Row(
            children: [
              Expanded(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 38,
                    sections: totals.entries.map((entry) {
                      final category = categories[entry.key];
                      return PieChartSectionData(
                        value: entry.value,
                        color: Color(category?.colorValue ?? 0xff64748b),
                        radius: 54,
                        showTitle: false,
                      );
                    }).toList(),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: totals.entries.map((entry) {
                    final category = categories[entry.key];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 10,
                            color: Color(category?.colorValue ?? 0xff64748b),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              category?.name ?? 'Otros',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(_currency.format(entry.value),
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final Category? category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Color(category?.colorValue ?? 0xff64748b)
                .withValues(alpha: .12),
            child: Icon(
              _categoryIcon(category?.id),
              color: Color(category?.colorValue ?? 0xff64748b),
            ),
          ),
          title:
              Text(expense.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${category?.name ?? 'Otros'} · ${DateFormat('d MMM', 'es_MX').format(expense.date)}'
            '${expense.receiptPath == null ? '' : ' · Ticket adjunto'}',
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
          onTap: onEdit,
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Card(
        color: Colors.white,
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Text(
              'Aún no hay gastos. Registra uno para empezar a organizarte.'),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xffffeded),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(color: Color(0xff8d2525))),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.sync),
                  label: const Text('Reintentar sincronización'),
                ),
              ),
          ],
        ),
      );
}

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({
    required this.repository,
    required this.categories,
    this.initial,
    super.key,
  });

  final ExpenseRepository repository;
  final List<Category> categories;
  final Expense? initial;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late String _categoryId;
  late DateTime _date;
  late final String _expenseId;
  String? _receiptPath;
  Uint8List? _receiptPreview;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _expenseId = initial?.id ?? widget.repository.newId();
    _title = TextEditingController(text: initial?.title ?? '');
    _amount = TextEditingController(
      text: initial == null ? '' : initial.amount.toStringAsFixed(2),
    );
    _notes = TextEditingController(text: initial?.notes ?? '');
    _categoryId = initial?.categoryId ?? widget.categories.first.id;
    _date = initial?.date ?? DateTime.now();
    _receiptPath = initial?.receiptPath;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _captureReceipt() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      final path = await widget.repository.saveReceipt(_expenseId, bytes);
      final temporaryImage = File(image.path);
      if (await temporaryImage.exists()) await temporaryImage.delete();
      if (mounted) {
        setState(() {
          _receiptPath = path;
          _receiptPreview = bytes;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo capturar el ticket: $error')),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'MX'),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (!mounted) return;
      Navigator.pop(
        context,
        Expense(
          id: _expenseId,
          title: _title.text.trim(),
          amount: parseExpenseAmount(_amount.text),
          categoryId: _categoryId,
          date: _date,
          notes: _notes.text.trim(),
          receiptPath: _receiptPath,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el ticket: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.initial == null ? 'Nuevo gasto' : 'Editar gasto',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  maxLength: 80,
                  validator: validateExpenseTitle,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                      labelText: 'Importe', prefixText: '\$ '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    try {
                      parseExpenseAmount(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: widget.categories
                      .map((category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _categoryId = value);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  decoration:
                      const InputDecoration(labelText: 'Notas (opcional)'),
                  maxLength: 300,
                  maxLines: 2,
                  validator: (value) => (value?.length ?? 0) > 300
                      ? 'Usa 300 caracteres o menos.'
                      : null,
                ),
                OutlinedButton.icon(
                  onPressed: _selectDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(DateFormat('d MMMM yyyy', 'es_MX').format(_date)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _captureReceipt,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    _receiptPreview != null || _receiptPath != null
                        ? 'Ticket capturado (cifrado)'
                        : 'Capturar ticket con cámara',
                  ),
                ),
                if (_receiptPreview != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _receiptPreview!,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Guardando…' : 'Guardar gasto'),
                ),
              ],
            ),
          ),
        ),
      );
}

IconData _categoryIcon(String? id) => switch (id) {
      'food' => Icons.restaurant_outlined,
      'transport' => Icons.directions_transit_outlined,
      'home' => Icons.home_outlined,
      'health' => Icons.health_and_safety_outlined,
      'leisure' => Icons.sports_esports_outlined,
      _ => Icons.receipt_long_outlined,
    };
