import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/custom_refresher.dart';
import '../services/firebase_service.dart';

import 'smart_reminder_screen.dart';
import 'package:campus_sync/screen/profile_section/profile_screen.dart';
import 'grade_calculator_screen.dart';
import 'planner_screen.dart';
import 'document_manager_screen.dart';
import 'timetable_attendance_screen.dart';
import '../services/reminder_badge_controller.dart';

String formatMinutes(int totalMinutes) {
  if (totalMinutes < 60) return '${totalMinutes}m';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class PomodoroService extends ChangeNotifier {
  static final PomodoroService instance = PomodoroService._internal();
  PomodoroService._internal();

  bool isRunning = false;
  bool isFinished = false;
  int selectedPreset = 0;
  int remainingSeconds = 25 * 60;
  int sessionMinutes = 25;
  Timer? _timer;
  Function(int)? onSessionComplete;

  void setCompletionCallback(Function(int) callback) {
    onSessionComplete = callback;
  }

  void selectPreset(int index, int minutes) {
    if (isRunning) return;
    selectedPreset = index;
    sessionMinutes = minutes;
    remainingSeconds = minutes * 60;
    isFinished = false;
    notifyListeners();
  }

  void toggleTimer() {
    isRunning = !isRunning;
    if (isRunning) {
      _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    } else {
      _timer?.cancel();
    }
    notifyListeners();
  }

  void _tick(Timer timer) {
    if (remainingSeconds > 0) {
      remainingSeconds--;
      notifyListeners();
    } else {
      isRunning = false;
      isFinished = true;
      _timer?.cancel();
      if (onSessionComplete != null) {
        onSessionComplete!(sessionMinutes);
      }
      notifyListeners();
    }
  }

  void stopAndReset() {
    isRunning = false;
    isFinished = false;
    _timer?.cancel();
    remainingSeconds = sessionMinutes * 60;
    notifyListeners();
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    ReminderBadgeController.instance.init();
  }

  final List<Widget> _pages = [
    const DashboardView(),
    const TimetableScreen(),
    const GradeCalculatorScreen(),
    const PlannerScreen(),
    const DocumentManagerScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: const Color(0xFFF0F2F5),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _buildGlowingIsland(),
    );
  }

  Widget _buildGlowingIsland() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.8),
            blurRadius: 0,
            spreadRadius: 0,
            offset: const Offset(0, -1),
          ),
        ],
        border: Border.all(color: const Color(0xFFE8EAED), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.dashboard_rounded, 0),
          _buildNavItem(Icons.event_note_rounded, 1),
          _buildNavItem(Icons.analytics_rounded, 2),
          _buildNavItem(Icons.calendar_today_rounded, 3),
          _buildNavItem(Icons.description_rounded, 4),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    final bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutQuart,
        padding: EdgeInsets.all(isSelected ? 14.0 : 10.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD166) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD166).withValues(alpha: 0.6),
                    blurRadius: 15,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          color: isSelected
              ? const Color(0xFF1A1D20)
              : const Color(0xFF6C757D).withValues(alpha: 0.6),
          size: isSelected ? 26 : 24,
        ),
      ),
    );
  }
}

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});
  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  static const Color _yellow = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg = Color(0xFFF0F2F5);
  static const Color _ink = Color(0xFF1A1D20);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _green = Color(0xFF34C759);
  static const Color _red = Color(0xFFFF3B30);

  bool _isLoading = true;
  String _firstName = 'Student';
  double _cgpa = 0.0;
  double _attPct = 0.0;

  List<Map<String, dynamic>> _upcomingClasses = [];
  bool _hadClassesToday = false;
  List<Map<String, dynamic>> _libraryBooks = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // ─────────────────────────────────────────────────────────────
  // REFRESH HANDLER
  // Added to fulfill the Custom Refresher on the Dashboard
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleRefresh() async {
    HapticFeedback.lightImpact();
    // Re-run your existing fetch logic
    await _fetchDashboardData();
    HapticFeedback.mediumImpact();
  }

  int _parseTimeToMinutes(String t) {
    try {
      final parts = t.trim().split(':');
      int hour = int.parse(parts[0]);
      final minParts = parts[1].trim().split(' ');
      int min = int.parse(minParts[0]);
      final period = minParts.length > 1 ? minParts[1].toUpperCase() : '';
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      return hour * 60 + min;
    } catch (_) {
      return 0;
    }
  }

  bool _isClassUpcoming(String timeRange) {
    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    final sides = timeRange.split(' - ');
    if (sides.length < 2) return true;
    return _parseTimeToMinutes(sides[1]) > nowMin;
  }

  Future<void> _fetchDashboardData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final db = FirebaseFirestore.instance;
      final uid = user.uid;
      // Push any books now within 24h window into smart_reminders

      DocumentSnapshot<Map<String, dynamic>> sd;
      try {
        sd = await db
            .collection('students')
            .doc(uid)
            .get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        setState(() => _isLoading = false);
        return;
      }
      if (!sd.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final data = sd.data()!;
      final rollNo = (data['rollNo'] ?? '') as String;
      final branch = (data['branch'] ?? 'CSE') as String;
      final fullName = (data['name'] ?? 'Student') as String;
      _firstName = fullName.trim().split(' ').first;

      final int startYear = rollNo.length >= 2
          ? 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24)
          : 2024;
      final int duration =
          (rollNo.length >= 4 &&
              (rollNo.substring(2, 4) == '02' ||
                  rollNo.substring(2, 4) == '03'))
          ? 5
          : 4;
      final String timetableDocId =
          '${branch.toUpperCase()}_$startYear-${startYear + duration}';

      final futures = await Future.wait([
        db
            .collection('timetables')
            .doc(timetableDocId)
            .get(const GetOptions(source: Source.serverAndCache)),
        db
            .collection('students')
            .doc(uid)
            .collection('pastSemesters')
            .orderBy('semester')
            .get(const GetOptions(source: Source.serverAndCache)),
        db
            .collection('timetable_attendance')
            .doc(uid)
            .collection('attendance')
            .get(const GetOptions(source: Source.serverAndCache)),
        db
            .collection('students')
            .doc(uid)
            .collection('library')
            .orderBy('dueDate')
            .get(
              const GetOptions(source: Source.serverAndCache),
            ), // Now index 3!
      ]);

      const fullDayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final todayName = fullDayNames[DateTime.now().weekday - 1];
      List<Map<String, dynamic>> allToday = [];
      try {
        final ttSnap = futures[0] as DocumentSnapshot<Map<String, dynamic>>?;
        if (ttSnap != null && ttSnap.exists) {
          final raw = ttSnap.data()?[todayName];
          if (raw != null) {
            allToday = List<Map<String, dynamic>>.from(raw as List);
          }
        }
      } catch (_) {}
      _hadClassesToday = allToday.isNotEmpty;
      final upcoming = allToday
          .where((c) => _isClassUpcoming((c['time'] ?? '') as String))
          .toList();

      double cgpa = 0.0;
      try {
        final psSnap = futures[1] as QuerySnapshot<Map<String, dynamic>>?;
        if (psSnap != null && psSnap.docs.isNotEmpty) {
          for (final doc in psSnap.docs.reversed) {
            final d = doc.data();
            final c = d['cpi'];
            final sem = d['semester'];
            debugPrint('Doc: ${doc.id}, semester: $sem, cpi: $c');
            if (c != null && (c is double || c is int) && c.toDouble() > 0) {
              cgpa = c.toDouble();
              break;
            }
          }
        }
      } catch (e) {
        debugPrint("🚨 Error fetching CGPA: $e");
      }

      double attPct = 0.0;
      try {
        final attSnap = futures[2] as QuerySnapshot<Map<String, dynamic>>?;
        if (attSnap != null) {
          int totalAttended = 0, totalClasses = 0;
          for (final doc in attSnap.docs) {
            final d = doc.data();
            totalAttended += ((d['attended'] ?? 0) as num).toInt();
            totalClasses += ((d['total'] ?? 0) as num).toInt();
          }
          if (totalClasses > 0) attPct = (totalAttended / totalClasses) * 100;
        }
      } catch (e) {
        debugPrint("🚨 Error fetching Attendance: $e");
      }

      List<Map<String, dynamic>> books = [];
      try {
        final libSnap =
            futures[3]
                as QuerySnapshot<Map<String, dynamic>>?; // Updated to index 3
        if (libSnap != null) {
          books = libSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        }
      } catch (e) {
        debugPrint("🚨 Error fetching Books: $e");
      }
      try {
        final plannerSnap = await db
            .collection('students')
            .doc(uid)
            .collection('planner')
            .where('isSmartReminder', isEqualTo: true)
            .where('isCompleted', isEqualTo: false)
            .get(const GetOptions(source: Source.serverAndCache));

        for (final doc in plannerSnap.docs) {
          final d = doc.data();
          final dt = (d['dateTime'] as Timestamp?)?.toDate();
          if (dt == null) continue;
          final diff = dt.difference(DateTime.now());
          if (diff.inHours <= 6 && !dt.isBefore(DateTime.now())) {
            await FirebaseService.instance.upsertPlannerReminder(
              uid,
              reminderId:  doc.id,
              title:       (d['title'] ?? 'Task Reminder') as String,
              dateTime:    dt,
              description: (d['description'] as String?)?.isNotEmpty == true
                  ? d['description'] as String
                  : null,
            );
          }
        }
      } catch (e) {
        debugPrint('🚨 Error checking planner window: $e');
      }
      // update the smart remnder for library books
      for (final book in books) {
        final due = book['dueDate'];
        if (due == null) continue;
        final dueDate = due is Timestamp ? due.toDate() : due as DateTime;
        final diff = dueDate.difference(DateTime.now());
        if (diff.inHours <= 24 && !dueDate.isBefore(DateTime.now())) {
          await FirebaseService.instance.upsertLibraryReminder(
            uid,
            bookId:    book['id'] as String,
            bookTitle: (book['title'] ?? '') as String,
            dueDate:   dueDate,
          );
        }
      }

      if (mounted) {
        setState(() {
          _cgpa = cgpa;
          _attPct = attPct;
          _upcomingClasses = upcoming;
          _libraryBooks = books;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("🚨 Master catch block hit: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -60,
          right: -40,
          child: CircleAvatar(
            radius: 140,
            backgroundColor: _yellow.withValues(alpha: 0.35),
          ),
        ),
        Positioned(
          top: 150,
          left: -80,
          child: CircleAvatar(
            radius: 100,
            backgroundColor: const Color(0xFFE2E5E9),
          ),
        ),
        Positioned(
          bottom: -30,
          right: -20,
          child: CircleAvatar(
            radius: 130,
            backgroundColor: _yellow.withValues(alpha: 0.15),
          ),
        ),
        Positioned(
          bottom: 100,
          left: 20,
          child: CircleAvatar(
            radius: 90,
            backgroundColor: const Color(0xFFD3D6DA),
          ),
        ),

        SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _yellow))
              // 🔴 Custom Refresher implemented here
              : CustomRefresher(
                  onRefresh: _handleRefresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader()),
                      SliverToBoxAdapter(child: _buildStatCards()),
                      SliverToBoxAdapter(
                        child: _sectionLabel(
                          "Today's Schedule",
                          _upcomingClasses.isEmpty && _hadClassesToday
                              ? 'all wrapped up'
                              : _upcomingClasses.isEmpty
                              ? 'free day'
                              : '${_upcomingClasses.length} remaining',
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _NextClassSlider(
                          upcomingClasses: _upcomingClasses,
                          allDoneToday:
                              _hadClassesToday && _upcomingClasses.isEmpty,
                        ),
                      ),
                      SliverToBoxAdapter(child: _sectionLabel('Extras', '')),
                      SliverToBoxAdapter(child: _buildExtrasRow()),
                      const SliverToBoxAdapter(child: SizedBox(height: 140)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                    letterSpacing: -0.5,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RichText(
                    text: TextSpan(
                      // 1st Part: "Welcome back, "
                      text: 'Welcome back, ',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFD166),
                      ),
                      children: [
                        // 2nd Part: The user's first name
                        TextSpan(
                          text: _firstName,
                          style: const TextStyle(
                            color: Color(
                              0xFF1A1D20,
                            ), // Dark color (_ink) for the greeting
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Have a productive day',
                  style: TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const TopActionButtons(),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.4,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              sub,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    final attColor = _attPct >= 80
        ? _green
        : (_attPct >= 70 ? _darkYellow : _red);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'CGPA',
              value: _cgpa > 0 ? _cgpa.toStringAsFixed(2) : '--',
              sub: _cgpa > 0 ? 'Live' : 'No data',
              subColor: _cgpa > 0 ? _green : _muted,
              dark: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Attendance',
              value: _attPct > 0 ? '${_attPct.toStringAsFixed(1)}%' : '--%',
              sub: _attPct > 0 ? 'Live' : 'No data',
              subColor: _attPct > 0 ? attColor : _muted,
              dark: true,
              //valueColor: _attPct > 0 ? attColor : null,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _yellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _yellow.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  _dayAbbr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _darkYellow,
                    letterSpacing: -0.8,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${DateTime.now().day}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                  ),
                ),
                Text(
                  _monthAbbr(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dayAbbr() {
    const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d[DateTime.now().weekday - 1];
  }

  String _monthAbbr() {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return m[DateTime.now().month - 1];
  }

  Widget _buildExtrasRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showLibraryDialog(),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Color(0xFF007AFF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Library',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _libraryBooks.isEmpty
                            ? 'No books issued'
                            : '${_libraryBooks.length} book${_libraryBooks.length > 1 ? 's' : ''} issued',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _muted,
                        ),
                      ),
                      if (_libraryBooks.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Builder(
                          builder: (_) {
                            final due = _libraryBooks.first['dueDate'];
                            if (due == null) return const SizedBox.shrink();
                            final dueDate = due is DateTime
                                ? due
                                : (due as Timestamp).toDate();
                            final diff = dueDate
                                .difference(DateTime.now())
                                .inDays;
                            final color = diff <= 2 ? _red : _darkYellow;
                            const mn = [
                              'Jan',
                              'Feb',
                              'Mar',
                              'Apr',
                              'May',
                              'Jun',
                              'Jul',
                              'Aug',
                              'Sep',
                              'Oct',
                              'Nov',
                              'Dec',
                            ];
                            final dateStr =
                                '${dueDate.day} ${mn[dueDate.month - 1]} ${dueDate.year}';
                            return FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  diff <= 0
                                      ? 'Overdue! ($dateStr)'
                                      : 'Last date: $dateStr',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF007AFF,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Manage →',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF007AFF),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: GestureDetector(
                onTap: () => _showStudyTimerDialog(),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.timer_rounded,
                          color: Color(0xFFA78BFA),
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Study Timer',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Pomodoro & focus',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _muted,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFA78BFA,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Start →',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFA78BFA),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLibraryDialog() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LibraryDialog(uid: uid, onRefresh: _fetchDashboardData),
    );
  }

  void _showStudyTimerDialog() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StudyTimerDialog(uid: uid),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final bool dark;
  final Color? valueColor;
  final Color? subColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.dark,
    this.valueColor,
    this.subColor,
  });

  // 🔴 RenderFlex Mitigation - Removed Spacer() causing exact-width overflow
  @override
  Widget build(BuildContext context) {
    const yellow = Color(0xFFFFD166);
    const ink = Color(0xFF1A1D20);
    final bg = dark ? ink : Colors.white;
    final fg = dark ? Colors.white : ink;
    final acc = dark ? yellow : ink;
    final effectiveSubColor = subColor ?? acc;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.15 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: acc,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: effectiveSubColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        sub,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: effectiveSubColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: valueColor ?? fg,
                letterSpacing: -1.0,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextClassSlider extends StatefulWidget {
  final List<Map<String, dynamic>> upcomingClasses;
  final bool allDoneToday;

  const _NextClassSlider({
    required this.upcomingClasses,
    required this.allDoneToday,
  });

  @override
  State<_NextClassSlider> createState() => _NextClassSliderState();
}

class _NextClassSliderState extends State<_NextClassSlider> {
  static const Color _yellow = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _ink = Color(0xFF1A1D20);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _bg = Color(0xFFF0F2F5);
  static const Color _green = Color(0xFF34C759);

  static const _accents = [
    Color(0xFFFFD166),
    Color(0xFF4ECDC4),
    Color(0xFFA78BFA),
    Color(0xFFFF6B6B),
    Color(0xFF34C759),
    Color(0xFF007AFF),
  ];

  late PageController _pageCtrl;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.allDoneToday && widget.upcomingClasses.isEmpty) {
      return _freeDay();
    }
    if (widget.allDoneToday && widget.upcomingClasses.isEmpty) {
      return _allDone();
    }

    final total = widget.upcomingClasses.length;

    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: total,
            itemBuilder: (_, i) => AnimatedScale(
              scale: _currentPage == i ? 1.0 : 0.95,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              child: _classCard(
                widget.upcomingClasses[i],
                _accents[i % _accents.length],
                i == _currentPage,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _currentPage > 0
                  ? () => _pageCtrl.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    )
                  : null,
              child: AnimatedOpacity(
                opacity: _currentPage > 0 ? 1.0 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: _muted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ...List.generate(total, (i) {
              final isActive = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive
                      ? _darkYellow
                      : _muted.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: _currentPage < total - 1
                  ? () => _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    )
                  : null,
              child: AnimatedOpacity(
                opacity: _currentPage < total - 1 ? 1.0 : 0.25,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: _muted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _classCard(Map<String, dynamic> cls, Color accent, bool isNext) {
    final subject = (cls['subject'] ?? '') as String;
    final time = (cls['time'] ?? '') as String;
    final room = (cls['room'] ?? '') as String;
    final parts = subject.split(':');
    final code = parts.first.trim();
    final name = parts.length > 1 ? parts[1].trim() : subject;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isNext ? accent.withValues(alpha: 0.5) : Colors.white,
          width: isNext ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isNext
                ? accent.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: isNext ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: double.infinity,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        code,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: accent,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isNext)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'NEXT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: _muted),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.location_on_rounded,
                      size: 12,
                      color: _muted,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        room,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: _muted),
        ],
      ),
    );
  }

  Widget _allDone() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    height: 108,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _green.withValues(alpha: 0.25), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: _green.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        const SizedBox(width: 20),
        Container(
          width: 4,
          height: 64,
          decoration: BoxDecoration(
            color: _green,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('🎓', style: TextStyle(fontSize: 26, height: 1.0)),
              SizedBox(height: 5),
              Text(
                'All classes done!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'You made it through the day',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(right: 20),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '✓ Done',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _green,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _freeDay() {
    final msgs = [
      ('🌅', 'No classes today', 'Enjoy the break'),
      ('🎉', 'Free day!', 'Rest and recharge'),
      ('☕', 'Clear schedule', 'Make the most of it'),
    ];
    final msg = msgs[DateTime.now().weekday % msgs.length];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 108,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
              color: _yellow,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg.$1, style: const TextStyle(fontSize: 26, height: 1.0)),
                const SizedBox(height: 5),
                Text(
                  msg.$2,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  msg.$3,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryDialog extends StatefulWidget {
  final String uid;
  final VoidCallback onRefresh;

  const _LibraryDialog({required this.uid, required this.onRefresh});

  @override
  State<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<_LibraryDialog> {
  static const Color _ink = Color(0xFF1A1D20);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _red = Color(0xFFFF3B30);
  static const Color _green = Color(0xFF34C759);
  static const Color _blue = Color(0xFF007AFF);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg = Color(0xFFF0F2F5);

  final _titleCtrl = TextEditingController();
  DateTime? _dueDate;
  bool _adding = false;
  bool _loading = true;

  List<Map<String, dynamic>> _books = [];

  @override
  void initState() {
    super.initState();
    _fetchBooks();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBooks() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.uid)
          .collection('library')
          .orderBy('dueDate')
          .get(const GetOptions(source: Source.serverAndCache));
      if (mounted) {
        setState(() {
          _books = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBook() async {
    if (_titleCtrl.text.trim().isEmpty || _dueDate == null) return;
    setState(() => _adding = true);

    final title = _titleCtrl.text.trim();
    final dueDate = _dueDate!;

    try {
      // 1. Write to library subcollection
      final ref = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.uid)
          .collection('library')
          .add({
            'title': title,
            'dueDate': Timestamp.fromDate(dueDate),
            'addedAt': FieldValue.serverTimestamp(),
            'isNotified': false,
            'isRead': false,
            'isDeleted': false,
          });

      // 2. Mirror to smart_reminders so the bell badge picks it up
      final diff = dueDate.difference(DateTime.now());
      if (diff.inHours <= 24 && !dueDate.isBefore(DateTime.now())) {
        await FirebaseService.instance.upsertLibraryReminder(
          widget.uid,
          bookId: ref.id,
          bookTitle: title,
          dueDate: dueDate,
        );
      }

      _titleCtrl.clear();
      setState(() {
        _books.add({
          'id': ref.id,
          'title': title,
          'dueDate': dueDate,
          'isNotified': false,
          'isRead': false,
          'isDeleted': false,
        });
        _dueDate = null;
        _adding = false;
      });

      await _fetchBooks();
      widget.onRefresh();
    } catch (e) {
      setState(() => _adding = false);
    }
  }

  Future<void> _returnBook(String id, int index, String title) async {
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: _muted.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.assignment_return_rounded,
                      color: _green,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Return Book',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '"$title"',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Confirm you\'ve returned this book to the library.',
                style: TextStyle(
                  fontSize: 13,
                  color: _muted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _muted,
                        side: BorderSide(color: _muted.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Return',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.uid)
          .collection('library')
          .doc(id)
          .delete();
      setState(() => _books.removeAt(index));
      widget.onRefresh();
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              16,
              24,
              MediaQuery.of(context).padding.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        color: _blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Library Tracker',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                          ),
                        ),
                        Text(
                          'Track your issued books',
                          style: TextStyle(
                            fontSize: 12,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: Color(0xFF007AFF),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (_books.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: const Center(
                      child: Text(
                        'No books issued yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: _muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_books.length, (i) {
                    final b = _books[i];
                    final due = b['dueDate'];
                    DateTime? dueDate;
                    if (due is Timestamp) dueDate = due.toDate();
                    if (due is DateTime) dueDate = due;
                    final diff = dueDate?.difference(DateTime.now()).inDays;
                    final dueColor = diff == null
                        ? _muted
                        : (diff <= 0
                              ? _red
                              : (diff <= 3 ? _darkYellow : _green));
                    final bookId = (b['id'] ?? '') as String;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.book_rounded,
                            color: _blue,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b['title'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                                if (dueDate != null)
                                  Text(
                                    diff! <= 0
                                        ? 'Overdue!'
                                        : 'Due in $diff day${diff > 1 ? 's' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: dueColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _returnBook(
                              bookId,
                              i,
                              (b['title'] ?? '') as String,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Return',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _green,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Issue a new book',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _titleCtrl,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Book title',
                          hintStyle: const TextStyle(
                            color: _muted,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().add(
                              const Duration(days: 14),
                            ),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 90),
                            ),
                          );
                          if (picked != null && mounted) {
                            setState(() => _dueDate = picked);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: _muted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _dueDate == null
                                    ? 'Pick due date'
                                    : 'Due: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _dueDate == null ? _muted : _ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: _adding ? null : _addBook,
                          child: _adding
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Issue Book',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ),
                    ],
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

class _StudyTimerDialog extends StatefulWidget {
  final String uid;
  const _StudyTimerDialog({required this.uid});
  @override
  State<_StudyTimerDialog> createState() => _StudyTimerDialogState();
}

class _StudyTimerDialogState extends State<_StudyTimerDialog>
    with SingleTickerProviderStateMixin {
  static const Color _ink = Color(0xFF1A1D20);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _purple = Color(0xFFA78BFA);
  static const Color _green = Color(0xFF34C759);
  static const Color _bg = Color(0xFFF0F2F5);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _red = Color(0xFFFF3B30);

  static const _presets = [
    ('25 min', 25, '🍅 Pomodoro'),
    ('45 min', 45, '📖 Deep focus'),
    ('15 min', 15, '⚡ Quick sprint'),
  ];

  int _todayMin = 0;
  int _weekMin = 0;
  int _monthMin = 0;
  Map<String, int> _dailyLog = {};
  bool _statsLoading = true;

  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));

    PomodoroService.instance.setCompletionCallback((minutes) {
      _saveSession(minutes);
    });

    _loadStats();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.uid)
          .collection('focus_stats')
          .doc('summary')
          .get(const GetOptions(source: Source.serverAndCache));

      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        final rawLog = (d['dailyLog'] as Map<String, dynamic>?) ?? {};
        final log = rawLog.map((k, v) => MapEntry(k, (v as num).toInt()));
        if (mounted) {
          setState(() {
            _todayMin = (d['todayMinutes'] ?? 0) as int;
            _weekMin = (d['weekMinutes'] ?? 0) as int;
            _monthMin = (d['monthMinutes'] ?? 0) as int;
            _dailyLog = log;
            _statsLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _statsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _saveSession(int minutes) async {
    if (minutes <= 0) return;
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final ref = FirebaseFirestore.instance
        .collection('students')
        .doc(widget.uid)
        .collection('focus_stats')
        .doc('summary');

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final old = snap.data() ?? {};
        final rawLog = (old['dailyLog'] as Map<String, dynamic>?) ?? {};
        final oldToday = ((old['todayMinutes'] ?? 0) as num).toInt();
        final oldWeek = ((old['weekMinutes'] ?? 0) as num).toInt();
        final oldMonth = ((old['monthMinutes'] ?? 0) as num).toInt();
        final oldDay = ((rawLog[dateKey] ?? 0) as num).toInt();

        final newLog = Map<String, dynamic>.from(rawLog);
        newLog[dateKey] = oldDay + minutes;

        tx.set(ref, {
          'todayMinutes': oldToday + minutes,
          'weekMinutes': oldWeek + minutes,
          'monthMinutes': oldMonth + minutes,
          'dailyLog': newLog,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      await _loadStats();
    } catch (e) {}
  }

  void _confirmStop() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Stop Session?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to stop the session early? Progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () {
              Navigator.pop(ctx);
              _stopAndSave();
            },
            child: const Text('Stop', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _stopAndSave() {
    HapticFeedback.mediumImpact();
    final srv = PomodoroService.instance;
    final totalSecs = srv.sessionMinutes * 60;
    final elapsedSec = totalSecs - srv.remainingSeconds;
    final elapsed = (elapsedSec / 60).floor();
    srv.stopAndReset();
    if (elapsed > 0) _saveSession(elapsed);
  }

  Widget _buildBars(
    List<(double, String)> bars, {
    bool highlightLast = true,
    double barHeight = 80.0,
  }) {
    final maxVal = bars.map((b) => b.$1).reduce((a, b) => a > b ? a : b);
    final barMax = maxVal > 0 ? maxVal : 60.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(bars.length, (i) {
        final isHighlight = highlightLast && i == bars.length - 1;
        final frac = (bars[i].$1 / barMax).clamp(0.0, 1.0);
        final barH = (barHeight * frac).clamp(4.0, barHeight);
        final color = isHighlight ? _purple : _purple.withValues(alpha: 0.28);

        return Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bars[i].$1 > 0)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${bars[i].$1.toInt()}m',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: isHighlight ? _purple : _muted,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 9),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: barH,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    bars[i].$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: isHighlight
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: isHighlight ? _purple : _muted,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDailyBars() {
    final now = DateTime.now();
    const dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthAbbr = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final bars = List.generate(6, (i) {
      final d = now.subtract(Duration(days: 5 - i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final val = (_dailyLog[key] ?? 0).toDouble();
      final label =
          '${dayAbbr[d.weekday - 1]}\n${d.day} ${monthAbbr[d.month - 1]}';
      return (val, label);
    });
    return _buildBars(bars, barHeight: 72.0);
  }

  Widget _buildWeeklyBars() {
    final now = DateTime.now();
    const monthAbbr = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final bars = List.generate(6, (i) {
      final monday = now.subtract(
        Duration(days: now.weekday - 1 + (5 - i) * 7),
      );
      int weekTotal = 0;
      for (int d = 0; d < 7; d++) {
        final day = monday.add(Duration(days: d));
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        weekTotal += _dailyLog[key] ?? 0;
      }
      final sunday = monday.add(const Duration(days: 6));
      String label;
      if (monday.month == sunday.month) {
        label = '${monday.day}–${sunday.day}\n${monthAbbr[monday.month - 1]}';
      } else {
        label =
            '${monday.day} ${monthAbbr[monday.month - 1]}–\n${sunday.day} ${monthAbbr[sunday.month - 1]}';
      }
      return (weekTotal.toDouble(), label);
    });
    return _buildBars(bars, barHeight: 72.0);
  }

  Widget _buildMonthlyBars() {
    final now = DateTime.now();
    const monthAbbr = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final bars = List.generate(6, (i) {
      final offset = 5 - i;
      int year = now.year;
      int month = now.month - offset;
      while (month <= 0) {
        month += 12;
        year--;
      }

      int daysInMonth = DateTime(year, month + 1, 0).day;
      int monthTotal = 0;
      for (int d = 1; d <= daysInMonth; d++) {
        final key =
            '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
        monthTotal += _dailyLog[key] ?? 0;
      }
      return (monthTotal.toDouble(), monthAbbr[month - 1]);
    });
    return _buildBars(bars, barHeight: 72.0);
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _FocusHistoryDialog(
        todayMin: _todayMin,
        weekMin: _weekMin,
        monthMin: _monthMin,
        statsLoading: _statsLoading,
        buildDailyBars: _buildDailyBars,
        buildWeeklyBars: _buildWeeklyBars,
        buildMonthlyBars: _buildMonthlyBars,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PomodoroService.instance,
      builder: (context, _) {
        final srv = PomodoroService.instance;
        final accent = srv.isFinished
            ? _green
            : (srv.isRunning ? _purple : _darkYellow);
        final m = srv.remainingSeconds ~/ 60;
        final s = srv.remainingSeconds % 60;
        final timeDisplay =
            '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        final progress =
            1.0 - (srv.remainingSeconds / (srv.sessionMinutes * 60));

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.timer_rounded,
                      color: _purple,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Study Timer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                        ),
                      ),
                      Text(
                        'Stay focused, stay sharp',
                        style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_presets.length, (i) {
                  final active = i == srv.selectedPreset;
                  return Flexible(
                    child: GestureDetector(
                      onTap: () => srv.selectPreset(i, _presets[i].$2),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: active ? _ink : _bg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _presets[i].$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: active ? Colors.white : _muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 6),
              Text(
                _presets[srv.selectedPreset].$3,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),

              const SizedBox(height: 20),

              ScaleTransition(
                scale: srv.isRunning
                    ? _pulseAnim
                    : const AlwaysStoppedAnimation(1.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 148,
                      height: 148,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        backgroundColor: _bg,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (srv.isFinished)
                          const Text(
                            '🎉',
                            style: TextStyle(fontSize: 30, height: 1.0),
                          )
                        else
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              timeDisplay,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: _ink,
                                letterSpacing: -1.0,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          srv.isFinished
                              ? 'Well done!'
                              : (srv.isRunning ? 'Focusing...' : 'Ready'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: srv.isFinished ? Colors.white : _ink,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: srv.isFinished
                          ? srv.stopAndReset
                          : srv.toggleTimer,
                      child: Text(
                        srv.isFinished
                            ? 'Start Again'
                            : (srv.isRunning ? 'Pause' : 'Start'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  if (!srv.isFinished) ...[
                    const SizedBox(width: 10),
                    if (srv.isRunning ||
                        srv.remainingSeconds < srv.sessionMinutes * 60)
                      GestureDetector(
                        onTap: _confirmStop,
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF3B30,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFFFF3B30,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.stop_rounded,
                            color: Color(0xFFFF3B30),
                            size: 20,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    if (!srv.isRunning)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          srv.stopAndReset();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: _muted,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.local_fire_department_rounded,
                                size: 14,
                                color: _purple,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _statsLoading
                                        ? '...'
                                        : formatMinutes(_todayMin),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: _ink,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'This Week',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _statsLoading ? '...' : formatMinutes(_weekMin),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showHistoryDialog(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.bar_chart_rounded,
                              size: 15,
                              color: _purple,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'History',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FocusHistoryDialog extends StatefulWidget {
  final int todayMin, weekMin, monthMin;
  final bool statsLoading;
  final Widget Function() buildDailyBars;
  final Widget Function() buildWeeklyBars;
  final Widget Function() buildMonthlyBars;

  const _FocusHistoryDialog({
    required this.todayMin,
    required this.weekMin,
    required this.monthMin,
    required this.statsLoading,
    required this.buildDailyBars,
    required this.buildWeeklyBars,
    required this.buildMonthlyBars,
  });

  @override
  State<_FocusHistoryDialog> createState() => _FocusHistoryDialogState();
}

class _FocusHistoryDialogState extends State<_FocusHistoryDialog> {
  static const Color _ink = Color(0xFF1A1D20);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _purple = Color(0xFFA78BFA);
  static const Color _bg = Color(0xFFF0F2F5);

  int _tab = 0;

  static const _tabs = [
    ('6 Days', '6 day history'),
    ('6 Weeks', '6 week history'),
    ('6 Months', '6 month history'),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: _purple,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Focus History',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    Text(
                      'Your study sessions over time',
                      style: TextStyle(
                        fontSize: 11,
                        color: _muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: _bg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                _statBox(
                  'Today',
                  formatMinutes(widget.todayMin),
                  Icons.today_rounded,
                ),
                const SizedBox(width: 8),
                _statBox(
                  'Week',
                  formatMinutes(widget.weekMin),
                  Icons.date_range_rounded,
                ),
                const SizedBox(width: 8),
                _statBox(
                  'Month',
                  formatMinutes(widget.monthMin),
                  Icons.calendar_month_rounded,
                ),
              ],
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final active = i == _tab;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: active ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [],
                        ),
                        child: Text(
                          _tabs[i].$1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: active ? _purple : _muted,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 14),

            if (widget.statsLoading)
              const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(
                    color: _purple,
                    strokeWidth: 2,
                  ),
                ),
              )
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: SizedBox(
                  key: ValueKey(_tab),
                  height: 110,
                  child: _tab == 0
                      ? widget.buildDailyBars()
                      : _tab == 1
                      ? widget.buildWeeklyBars()
                      : widget.buildMonthlyBars(),
                ),
              ),

            const SizedBox(height: 6),

            Center(
              child: Text(
                _tabs[_tab].$2,
                style: TextStyle(
                  fontSize: 10,
                  color: _muted.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: _purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _purple.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 13, color: _purple),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopActionButtons extends StatelessWidget {
  const TopActionButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SmartReminderScreen()),
          ),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            // 🟢 NEW: Listens to the global controller!
            child: ValueListenableBuilder<int>(
              valueListenable: ReminderBadgeController.instance.unreadCount,
              builder: (context, count, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF1A1D20),
                      size: 24,
                    ),
                    if (count > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            count > 99 ? '99+' : count.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          ),
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0xFFFFD166),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x55FFD166),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF1A1D20),
              size: 26,
            ),
          ),
        ),
      ],
    );
  }
}
