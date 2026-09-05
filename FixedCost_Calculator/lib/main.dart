import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const FixedCostApp());
}

class FixedCostApp extends StatelessWidget {
  const FixedCostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '고정비 가계부',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  static const _paydayKey = 'payday';
  static const _salaryKey = 'salary';
  static const _selectedDateKey = 'selected_date';
  static const _recurringItemsKey = 'recurring_items_by_day';
  static const _singleUseItemsKey = 'single_use_items_by_date';
  static const _spentStatusKey = 'spent_status_by_date';

  bool _isLoading = true;
  int? _payday;
  int _salary = 0;
  DateTime _selectedDate = _dateOnly(DateTime.now());
  final Map<int, List<DailyItem>> _recurringItemsByDay = {};
  final Map<String, List<DailyItem>> _singleUseItemsByDate = {};
  final Map<String, bool> _spentStatusByItem = {};

  List<DailyItem> _itemsForDate(DateTime date) {
    final normalized = _dateOnly(date);
    final day = normalized.day;
    final recurring = _recurringItemsByDay[day] ?? const <DailyItem>[];
    final singleUse =
        _singleUseItemsByDate[_dateKey(normalized)] ?? const <DailyItem>[];
    return List<DailyItem>.from([...recurring, ...singleUse]);
  }

  void _updateDayItems(DateTime date, List<DailyItem> items) {
    final normalized = _dateOnly(date);
    final day = normalized.day;
    final dateKey = _dateKey(normalized);
    final recurringItems =
        items.where((item) => item.repeatMonthly).toList(growable: false);
    final singleUseItems =
        items
            .where((item) => !item.repeatMonthly)
            .map((item) => item.copyWith(repeatMonthly: false))
            .toList(growable: false);

    setState(() {
      if (recurringItems.isEmpty) {
        _recurringItemsByDay.remove(day);
      } else {
        _recurringItemsByDay[day] = recurringItems;
      }

      if (singleUseItems.isEmpty) {
        _singleUseItemsByDate.remove(dateKey);
      } else {
        _singleUseItemsByDate[dateKey] = singleUseItems;
      }

      final validItemIds = items.map((item) => item.id).toSet();
      final datePrefix = '$dateKey|';
      _spentStatusByItem.removeWhere((key, _) {
        if (!key.startsWith(datePrefix)) {
          return false;
        }
        final itemId = key.substring(datePrefix.length);
        return !validItemIds.contains(itemId);
      });
    });
    _saveState();
  }

  void _resetAllDayEntries() {
    setState(() {
      _recurringItemsByDay.clear();
      _singleUseItemsByDate.clear();
      _spentStatusByItem.clear();
    });
    _saveState();
  }

  bool _isSpent(DateTime date, String itemId) {
    final key = _spentKey(date, itemId);
    return _spentStatusByItem[key] ?? false;
  }

  void _updateSpentStatus(DateTime date, String itemId, bool isSpent) {
    final key = _spentKey(date, itemId);
    setState(() {
      _spentStatusByItem[key] = isSpent;
    });
    _saveState();
  }

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedPayday = prefs.getInt(_paydayKey);
    final storedSalary = prefs.getInt(_salaryKey) ?? 0;
    final storedSelectedDate = prefs.getString(_selectedDateKey);

    final recurringRaw = prefs.getString(_recurringItemsKey);
    final singleUseRaw = prefs.getString(_singleUseItemsKey);
    final spentRaw = prefs.getString(_spentStatusKey);

    final loadedRecurring = <int, List<DailyItem>>{};
    final loadedSingleUse = <String, List<DailyItem>>{};
    final loadedSpent = <String, bool>{};

    if (recurringRaw != null && recurringRaw.isNotEmpty) {
      final decoded = jsonDecode(recurringRaw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final day = int.tryParse(entry.key);
          if (day == null || day < 1 || day > 31) {
            continue;
          }
          final rawList = entry.value;
          if (rawList is List) {
            loadedRecurring[day] =
                rawList
                    .whereType<Map<String, dynamic>>()
                    .map(DailyItem.fromJson)
                    .toList(growable: false);
          }
        }
      }
    }

    if (singleUseRaw != null && singleUseRaw.isNotEmpty) {
      final decoded = jsonDecode(singleUseRaw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final rawList = entry.value;
          if (rawList is List) {
            loadedSingleUse[entry.key] =
                rawList
                    .whereType<Map<String, dynamic>>()
                    .map(DailyItem.fromJson)
                    .toList(growable: false);
          }
        }
      }
    }

    if (spentRaw != null && spentRaw.isNotEmpty) {
      final decoded = jsonDecode(spentRaw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          if (entry.value is bool) {
            loadedSpent[entry.key] = entry.value as bool;
          }
        }
      }
    }

    setState(() {
      _payday = storedPayday;
      _salary = storedSalary;
      if (storedSelectedDate != null) {
        final parsed = DateTime.tryParse(storedSelectedDate);
        if (parsed != null) {
          _selectedDate = _dateOnly(parsed);
        }
      }
      _recurringItemsByDay
        ..clear()
        ..addAll(loadedRecurring);
      _singleUseItemsByDate
        ..clear()
        ..addAll(loadedSingleUse);
      _spentStatusByItem
        ..clear()
        ..addAll(loadedSpent);
      _isLoading = false;
    });
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_payday == null) {
      await prefs.remove(_paydayKey);
    } else {
      await prefs.setInt(_paydayKey, _payday!);
    }

    await prefs.setInt(_salaryKey, _salary);
    await prefs.setString(_selectedDateKey, _selectedDate.toIso8601String());
    await prefs.setString(
      _recurringItemsKey,
      jsonEncode(
        _recurringItemsByDay.map(
          (key, value) => MapEntry(
            key.toString(),
            value.map((item) => item.toJson()).toList(growable: false),
          ),
        ),
      ),
    );
    await prefs.setString(
      _singleUseItemsKey,
      jsonEncode(
        _singleUseItemsByDate.map(
          (key, value) => MapEntry(
            key,
            value.map((item) => item.toJson()).toList(growable: false),
          ),
        ),
      ),
    );
    await prefs.setString(_spentStatusKey, jsonEncode(_spentStatusByItem));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_payday == null) {
      return PaydayOnboardingPage(
        onSaved: (value) {
          setState(() {
            _payday = value;
            _selectedDate = _dateOnly(DateTime.now());
          });
          _saveState();
        },
      );
    }

    final cycleDates = _buildPayCycleDates(DateTime.now(), _payday!);
    if (cycleDates.isNotEmpty && !cycleDates.contains(_dateOnly(_selectedDate))) {
      _selectedDate = cycleDates.first;
    }

    return PayCycleListPage(
      payday: _payday!,
      salary: _salary,
      dates: cycleDates,
      selectedDate: _selectedDate,
      dayItemsOf: _itemsForDate,
      isSpentOf: _isSpent,
      onDateSelected: (date) {
        setState(() {
          _selectedDate = date;
        });
        _saveState();
      },
      onDayItemsChanged: _updateDayItems,
      onSpentChanged: _updateSpentStatus,
      onResetAllEntries: _resetAllDayEntries,
      onSalaryChanged: (value) {
        setState(() {
          _salary = value;
        });
        _saveState();
      },
      onResetPayday: () {
        setState(() {
          _payday = null;
          _salary = 0;
          _selectedDate = _dateOnly(DateTime.now());
          _recurringItemsByDay.clear();
          _singleUseItemsByDate.clear();
          _spentStatusByItem.clear();
        });
        _saveState();
      },
    );
  }
}

class PaydayOnboardingPage extends StatefulWidget {
  const PaydayOnboardingPage({super.key, required this.onSaved});

  final ValueChanged<int> onSaved;

  @override
  State<PaydayOnboardingPage> createState() => _PaydayOnboardingPageState();
}

class _PaydayOnboardingPageState extends State<PaydayOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('월급날 설정')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '매월 월급일(1~28일)을 입력하세요.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '월급날',
                    hintText: '예: 25',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null) {
                      return '숫자를 입력해 주세요.';
                    }
                    if (parsed < 1 || parsed > 28) {
                      return '1~28 사이로 입력해 주세요.';
                    }
                    return null;
                  },
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        widget.onSaved(int.parse(_controller.text));
                      }
                    },
                    child: const Text('저장하고 시작'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PayCycleListPage extends StatefulWidget {
  const PayCycleListPage({
    super.key,
    required this.payday,
    required this.salary,
    required this.dates,
    required this.selectedDate,
    required this.dayItemsOf,
    required this.isSpentOf,
    required this.onDateSelected,
    required this.onDayItemsChanged,
    required this.onSpentChanged,
    required this.onResetAllEntries,
    required this.onSalaryChanged,
    required this.onResetPayday,
  });

  final int payday;
  final int salary;
  final List<DateTime> dates;
  final DateTime selectedDate;
  final List<DailyItem> Function(DateTime date) dayItemsOf;
  final bool Function(DateTime date, String itemId) isSpentOf;
  final ValueChanged<DateTime> onDateSelected;
  final void Function(DateTime date, List<DailyItem> items) onDayItemsChanged;
  final void Function(DateTime date, String itemId, bool isSpent) onSpentChanged;
  final VoidCallback onResetAllEntries;
  final ValueChanged<int> onSalaryChanged;
  final VoidCallback onResetPayday;

  @override
  State<PayCycleListPage> createState() => _PayCycleListPageState();
}

class _PayCycleListPageState extends State<PayCycleListPage> {
  int? _weekdayFilter;
  bool _showOnlyUnchecked = false;
  bool _showSalary = false;

  @override
  Widget build(BuildContext context) {
    final selected = _dateOnly(widget.selectedDate);
    final fixedCostTotal = widget.dates.fold<int>(0, (sum, date) {
      return sum + _sumItems(widget.dayItemsOf(date));
    });
    final spentTotal = widget.dates.fold<int>(0, (sum, date) {
      final dateItems = widget.dayItemsOf(date);
      final dateSpent = dateItems.fold<int>(0, (itemSum, item) {
        if (!widget.isSpentOf(date, item.id)) {
          return itemSum;
        }
        return itemSum + item.amount;
      });
      if (dateSpent == 0) {
        return sum;
      }
      return sum + dateSpent;
    });
    final remainingSpending = fixedCostTotal - spentTotal;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('이번 월급 주기'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '월급날 재설정',
            icon: const Icon(Icons.settings),
            onSelected: (value) {
              switch (value) {
                case 'payday':
                  widget.onResetPayday();
                case 'salary':
                  _showSalarySettings(context);
                case 'reset':
                  _confirmResetAllEntries(context);
                case 'developer':
                  _showDeveloperInfo(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'payday',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_month_outlined),
                  title: Text('월급일 설정'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'salary',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.payments_outlined),
                  title: Text('월급 설정'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'reset',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('일별 기록 초기화'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'developer',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('개발자 정보'),
                ),
              ),
            ],
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: '현황', icon: Icon(Icons.calendar_month_outlined)),
            Tab(text: '고정비 설정', icon: Icon(Icons.view_list_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _buildDailyInputTab(
            context,
            selected,
            fixedCostTotal,
            spentTotal,
            remainingSpending,
          ),
          _buildSummaryTab(context),
        ],
      ),
    ));
  }

  Widget _buildDailyInputTab(
    BuildContext context,
    DateTime selected,
    int fixedCostTotal,
    int spentTotal,
    int remainingSpending,
  ) {
    final visibleDates =
        widget.dates.where((date) {
          final matchWeekday =
              _weekdayFilter == null || date.weekday == _weekdayFilter;
          final matchUnchecked =
              !_showOnlyUnchecked || _hasUncheckedItem(date, widget.dayItemsOf(date));
          return matchWeekday && matchUnchecked;
        }).toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '월급날: 매월 ${widget.payday}일',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '월급: ${_showSalary ? _formatWon(widget.salary) : '••••••원'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: _showSalary ? '월급 숨기기' : '월급 보기',
                        onPressed: () {
                          setState(() {
                            _showSalary = !_showSalary;
                          });
                        },
                        icon: Icon(
                          _showSalary
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '고정비: ${_formatWon(fixedCostTotal)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '남은 지출: ${_formatWon(remainingSpending)}',
                          style: TextStyle(
                            color:
                                remainingSpending >= 0
                                    ? Colors.teal
                                    : Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '지출 완료: ${_formatWon(spentTotal)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _weekdayFilter,
                  decoration: const InputDecoration(
                    labelText: '요일 선택',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('전체')),
                    ...List<DropdownMenuItem<int?>>.generate(7, (index) {
                      final weekday = index + 1;
                      return DropdownMenuItem<int?>(
                        value: weekday,
                        child: Text(_weekdayLabel(weekday)),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _weekdayFilter = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('미지출만'),
                    Switch(
                      value: _showOnlyUnchecked,
                      onChanged: (value) {
                        setState(() {
                          _showOnlyUnchecked = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: visibleDates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final date = visibleDates[index];
              final items = widget.dayItemsOf(date);
              final dayTotal = _sumItems(items);
              final preview = _descriptionPreview(items);
              final isSelected = _dateOnly(date) == selected;
              final checkedCount =
                  items.where((item) => widget.isSpentOf(date, item.id)).length;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ExpansionTile(
                  initiallyExpanded: isSelected,
                  onExpansionChanged: (expanded) {
                    if (expanded) {
                      widget.onDateSelected(date);
                    }
                  },
                  leading: CircleAvatar(child: Text('${date.day}')),
                  title: Text(_formatDate(date)),
                  subtitle: Text(
                    preview.isEmpty
                        ? '항목 없음'
                        : '$preview (${items.length}건 · 완료 $checkedCount건)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatWon(dayTotal),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  children: items
                      .map(
                        (item) => CheckboxListTile(
                          dense: true,
                          value: widget.isSpentOf(date, item.id),
                          onChanged: (value) {
                            widget.onSpentChanged(date, item.id, value ?? false);
                          },
                          title: Text(_formatWon(item.amount)),
                          subtitle: Text(
                            item.description.trim().isEmpty
                                ? '설명 없음'
                                : item.description.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _hasUncheckedItem(DateTime date, List<DailyItem> items) {
    if (items.isEmpty) {
      return false;
    }
    return items.any((item) => !widget.isSpentOf(date, item.id));
  }

  Widget _buildSummaryTab(BuildContext context) {
    final sortedDays = widget.dates.map((date) => date.day).toSet().toList()..sort();

    return ListView.separated(
      itemCount: sortedDays.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final representativeDate = widget.dates.firstWhere((date) => date.day == day);
        final items = widget.dayItemsOf(representativeDate);
        final description = _descriptionPreview(items);
        final total = _sumItems(items);

        return ListTile(
          title: Text('${day}일 기준'),
          subtitle: Text(
            description.isEmpty ? '항목 없음' : '$description (${items.length}건)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text(
                _formatWon(total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                tooltip: '${day}일 항목 편집',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showManageDayItemsDialog(
                  context,
                  representativeDate,
                  items,
                ),
              ),
            ],
          ),
          onTap: () => _showManageDayItemsDialog(context, representativeDate, items),
        );
      },
    );
  }

  Future<void> _showSalarySettings(BuildContext context) async {
    var salary = widget.salary;
    final savedSalary = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('월급 설정'),
          content: SalaryInput(
            initialSalary: widget.salary,
            onChanged: (value) {
              salary = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, salary),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    if (savedSalary != null) {
      widget.onSalaryChanged(savedSalary);
    }
  }

  Future<void> _confirmResetAllEntries(BuildContext context) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('일별 기록 초기화'),
          content: const Text('모든 날짜의 금액/설명을 초기 상태로 되돌릴까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('초기화'),
            ),
          ],
        );
      },
    );

    if (shouldReset == true) {
      widget.onResetAllEntries();
    }
  }

  Future<void> _showDeveloperInfo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('개발자 정보'),
          content: const Text('개발자 : 심정욱\n이메일 : sim12131@naver.com'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showManageDayItemsDialog(
    BuildContext context,
    DateTime date,
    List<DailyItem> currentItems,
  ) async {
    final localItems = List<DailyItem>.from(currentItems);

    final savedItems = await showDialog<List<DailyItem>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${_formatDate(date)} 항목 관리'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          final item = await _showSingleItemEditor(context, null);
                          if (item != null) {
                            setDialogState(() {
                              localItems.add(item);
                            });
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('항목 추가'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 300,
                      child: localItems.isEmpty
                          ? const Center(child: Text('등록된 항목이 없습니다.'))
                          : ListView.separated(
                              itemCount: localItems.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = localItems[index];
                                final description = item.description.trim();
                                return ListTile(
                                  dense: true,
                                  title: Text(_formatWon(item.amount)),
                                  subtitle: Text(
                                    description.isEmpty
                                        ? (item.repeatMonthly ? '설명 없음 · 매월 반복' : '설명 없음 · 이번 달만')
                                        : '$description · ${item.repeatMonthly ? '매월 반복' : '이번 달만'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Wrap(
                                    spacing: 2,
                                    children: [
                                      IconButton(
                                        tooltip: '수정',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () async {
                                          final edited = await _showSingleItemEditor(
                                            context,
                                            item,
                                          );
                                          if (edited != null) {
                                            setDialogState(() {
                                              localItems[index] = edited;
                                            });
                                          }
                                        },
                                      ),
                                      IconButton(
                                        tooltip: '삭제',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () {
                                          setDialogState(() {
                                            localItems.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '합계: ${_formatWon(_sumItems(localItems))}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext, List<DailyItem>.from(localItems));
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (savedItems != null) {
      widget.onDayItemsChanged(date, savedItems);
    }
  }

  Future<DailyItem?> _showSingleItemEditor(
    BuildContext context,
    DailyItem? initialItem,
  ) async {
    var repeatMonthly = initialItem?.repeatMonthly ?? true;
    final amountController = TextEditingController(
      text: initialItem == null ? '' : initialItem.amount.toString(),
    );
    final descriptionController = TextEditingController(
      text: initialItem?.description ?? '',
    );

    final saved = await showDialog<DailyItem>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(initialItem == null ? '항목 추가' : '항목 수정'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '사용 금액',
                        suffixText: '원',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                        if (digitsOnly != value) {
                          amountController.value = amountController.value.copyWith(
                            text: digitsOnly,
                            selection: TextSelection.collapsed(offset: digitsOnly.length),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: '설명',
                        hintText: '예: 교통비, 점심, 구독료',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 80,
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: repeatMonthly,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('다음 달에도 반복 반영'),
                      subtitle: Text(
                        repeatMonthly ? '매월 같은 날짜에 반복됩니다.' : '이번 월급 주기에만 반영됩니다.',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          repeatMonthly = value ?? true;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final amount = int.tryParse(amountController.text) ?? 0;
                    final description = descriptionController.text.trim();
                    Navigator.pop(
                      dialogContext,
                      DailyItem(
                        id: initialItem?.id ?? _newItemId(),
                        amount: amount,
                        description: description,
                        repeatMonthly: repeatMonthly,
                      ),
                    );
                  },
                  child: const Text('확인'),
                ),
              ],
            );
          },
        );
      },
    );

    amountController.dispose();
    descriptionController.dispose();
    return saved;
  }
}

class DailyItem {
  const DailyItem({
    required this.id,
    required this.amount,
    required this.description,
    required this.repeatMonthly,
  });

  final String id;
  final int amount;
  final String description;
  final bool repeatMonthly;

  DailyItem copyWith({
    int? amount,
    String? description,
    bool? repeatMonthly,
  }) {
    return DailyItem(
      id: id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      repeatMonthly: repeatMonthly ?? this.repeatMonthly,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'description': description,
      'repeatMonthly': repeatMonthly,
    };
  }

  factory DailyItem.fromJson(Map<String, dynamic> json) {
    return DailyItem(
      id: (json['id'] as String?) ?? _newItemId(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      description: (json['description'] as String?) ?? '',
      repeatMonthly: (json['repeatMonthly'] as bool?) ?? true,
    );
  }
}

class SalaryInput extends StatefulWidget {
  const SalaryInput({
    super.key,
    required this.initialSalary,
    required this.onChanged,
  });

  final int initialSalary;
  final ValueChanged<int> onChanged;

  @override
  State<SalaryInput> createState() => _SalaryInputState();
}

class _SalaryInputState extends State<SalaryInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialSalary == 0 ? '' : widget.initialSalary.toString(),
    );
  }

  @override
  void didUpdateWidget(covariant SalaryInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSalary != widget.initialSalary) {
      final nextText =
          widget.initialSalary == 0 ? '' : widget.initialSalary.toString();
      if (_controller.text != nextText) {
        _controller.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '월급',
        hintText: '예: 3000000',
        border: OutlineInputBorder(),
        suffixText: '원',
      ),
      onChanged: (value) {
        final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (digitsOnly != value) {
          _controller.value = _controller.value.copyWith(
            text: digitsOnly,
            selection: TextSelection.collapsed(offset: digitsOnly.length),
          );
        }
        widget.onChanged(int.tryParse(digitsOnly) ?? 0);
      },
    );
  }
}

List<DateTime> _buildPayCycleDates(DateTime now, int payday) {
  final today = _dateOnly(now);
  final thisMonthPayday = DateTime(today.year, today.month, payday);
  final start =
      today.isBefore(thisMonthPayday)
          ? DateTime(today.year, today.month - 1, payday)
          : thisMonthPayday;
  final end = DateTime(start.year, start.month + 1, payday);
  final days = end.difference(start).inDays;

  return List<DateTime>.generate(days, (index) {
    return _dateOnly(start.add(Duration(days: index)));
  });
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _spentKey(DateTime date, String itemId) {
  return '${_dateKey(date)}|$itemId';
}

String _newItemId() {
  return DateTime.now().microsecondsSinceEpoch.toString();
}

String _dateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

int _sumItems(List<DailyItem> items) {
  return items.fold<int>(0, (sum, item) => sum + item.amount);
}

String _descriptionPreview(List<DailyItem> items) {
  final descriptions =
      items
          .map((item) => item.description.trim())
          .where((text) => text.isNotEmpty)
          .toList();
  return descriptions.join(', ');
}

String _weekdayLabel(int weekday) {
  const labels = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  return labels[weekday - 1];
}

String _formatDate(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} (${weekdays[date.weekday - 1]})';
}

String _formatWon(int amount) {
  final source = amount.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    final indexFromRight = source.length - i;
    buffer.write(source[i]);
    if (indexFromRight > 1 && indexFromRight % 3 == 1) {
      buffer.write(',');
    }
  }
  return '${buffer.toString()}원';
}
