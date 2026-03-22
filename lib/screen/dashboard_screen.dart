import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'smart_reminder_screen.dart';
import 'profile_section/profile_screen.dart';
import 'grade_calculator_screen.dart';
import 'planner_screen.dart';
import 'document_manager_screen.dart';
import 'timetable_attendance_screen.dart';

// ─────────────────────────────────────────────────────────────
// ROOT SHELL — floating island unchanged
// ─────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

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
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 25,
              offset: const Offset(0, 10))
        ],
        border: Border.all(color: const Color(0xFF6C757D).withOpacity(0.1)),
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
                      color: const Color(0xFFFFD166).withOpacity(0.6),
                      blurRadius: 15,
                      spreadRadius: 2)
                ]
              : [],
        ),
        child: Icon(
          icon,
          color: isSelected
              ? const Color(0xFF1A1D20)
              : const Color(0xFF6C757D).withOpacity(0.6),
          size: isSelected ? 26 : 24,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DASHBOARD CONTENT
// ─────────────────────────────────────────────────────────────
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});
  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _green      = Color(0xFF34C759);
  static const Color _red        = Color(0xFFFF3B30);

  bool _isLoading = true;
  String _firstName = 'Student';
  double _cgpa   = 0.0;
  double _attPct = 0.0;

  // future-only classes (past stripped out)
  List<Map<String, dynamic>> _upcomingClasses = [];
  bool _hadClassesToday = false; // true if timetable had any classes at all

  // live reminders
  List<Map<String, dynamic>> _reminders = [];

  // library books (local state — stored in Firestore under students/{uid}/library)
  List<Map<String, dynamic>> _libraryBooks = [];

  // ── cache helpers ──────────────────────────────────────────
  Future<DocumentSnapshot<Map<String, dynamic>>> _getCached(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return ref.get(const GetOptions(source: Source.server));
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // ── time parser for "9:00 AM" format ───────────────────────
  // Returns minutes since midnight for comparison
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

  // Returns true if the class's END time is still in the future
  bool _isClassUpcoming(String timeRange) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final sides = timeRange.split(' - ');
    if (sides.length < 2) return true;
    final endMinutes = _parseTimeToMinutes(sides[1]);
    return endMinutes > nowMinutes;
  }

  Future<void> _fetchDashboardData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { setState(() => _isLoading = false); return; }

      final db  = FirebaseFirestore.instance;
      final uid = user.uid;

      // ── Step 1: student doc (cache-first) ──────────────────
      final studentSnap = await _getCached(
          db.collection('students').doc(uid)
              as DocumentReference<Map<String, dynamic>>);
      if (!studentSnap.exists) { setState(() => _isLoading = false); return; }

      final sd       = studentSnap.data()!;
      final rollNo   = (sd['rollNo'] ?? '2401cs80') as String;
      final branch   = (sd['branch'] ?? 'CSE') as String;
      final fullName = (sd['name']   ?? 'Student') as String;
      _firstName     = fullName.split(' ').first;

      // batch year
      final sy  = 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24);
      final dur = (rollNo.length >= 4 &&
              (rollNo.substring(2, 4) == '02' || rollNo.substring(2, 4) == '03'))
          ? 5 : 4;
      final ttDocId = '${branch.toUpperCase()}_$sy-${sy + dur}';

      // ── Step 2: timetable + reminders + library IN PARALLEL ─
      final results = await Future.wait([
        _getCached(db.collection('timetables').doc(ttDocId)
            as DocumentReference<Map<String, dynamic>>),
        // Reminders: fetch unread/upcoming from smart_reminders subcollection
        db.collection('students').doc(uid).collection('reminders')
            .where('isRead', isEqualTo: false)
            .orderBy('createdAt', descending: true)
            .limit(3)
            .get(const GetOptions(source: Source.serverAndCache)),
        // Library books
        db.collection('students').doc(uid).collection('library')
            .orderBy('dueDate')
            .get(const GetOptions(source: Source.serverAndCache)),
      ]);

      final ttSnap       = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final remindersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final librarySnap  = results[2] as QuerySnapshot<Map<String, dynamic>>;

      // Today's class list
      const dayNames = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      final todayName = dayNames[DateTime.now().weekday - 1];
      List<Map<String, dynamic>> allToday = [];
      if (ttSnap.exists) {
        final raw = ttSnap.data()?[todayName];
        if (raw != null) allToday = List<Map<String, dynamic>>.from(raw as List);
      }
      _hadClassesToday = allToday.isNotEmpty;

      // Strip past classes — only keep classes whose END time hasn't passed
      final upcoming = allToday
          .where((c) => _isClassUpcoming((c['time'] ?? '') as String))
          .toList();

      // CGPA from pastSemesters
      double cgpa = ((sd['cpi'] ?? 0.0) as num).toDouble();
      final rawPast = ((sd['pastSemesters'] as List?) ?? [])
          .cast<Map<String, dynamic>>();
      if (rawPast.isNotEmpty) {
        rawPast.sort((a, b) =>
            ((a['semester'] ?? 0) as int).compareTo((b['semester'] ?? 0) as int));
        cgpa = ((rawPast.last['cpi'] ?? 0.0) as num).toDouble();
      }

      // Overall attendance %
      final rawAtt = (sd['attendance'] as Map<String, dynamic>?) ?? {};
      int totalAtt = 0, totalTot = 0;
      rawAtt.forEach((_, v) {
        final m = v as Map<String, dynamic>;
        totalAtt += (m['attended'] ?? 0) as int;
        totalTot += (m['total']   ?? 0) as int;
      });

      setState(() {
        _cgpa            = cgpa;
        _attPct          = totalTot > 0 ? (totalAtt / totalTot) * 100 : 0.0;
        _upcomingClasses = upcoming;
        _reminders       = remindersSnap.docs.map((d) => d.data()).toList();
        _libraryBooks    = librarySnap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Dashboard fetch error: $e');
      setState(() => _isLoading = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(top: -60, right: -40,
            child: CircleAvatar(radius: 140, backgroundColor: _yellow.withOpacity(0.35))),
        Positioned(top: 150, left: -80,
            child: CircleAvatar(radius: 100, backgroundColor: const Color(0xFFE2E5E9))),
        Positioned(bottom: -30, right: -20,
            child: CircleAvatar(radius: 130, backgroundColor: _yellow.withOpacity(0.15))),
        Positioned(bottom: 100, left: 20,
            child: CircleAvatar(radius: 90, backgroundColor: const Color(0xFFD3D6DA))),

        SafeArea(
          bottom: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: _yellow))
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildStatCards()),
                    SliverToBoxAdapter(child: _buildSectionLabel(
                      "Today's Schedule",
                      _upcomingClasses.isEmpty && _hadClassesToday
                          ? 'all wrapped up'
                          : _upcomingClasses.isEmpty
                              ? 'free day'
                              : '${_upcomingClasses.length} remaining',
                    )),
                    SliverToBoxAdapter(
                      child: _NextClassSlider(
                        upcomingClasses: _upcomingClasses,
                        allDoneToday: _hadClassesToday && _upcomingClasses.isEmpty,
                      ),
                    ),
                    if (_reminders.isNotEmpty) ...[
                      SliverToBoxAdapter(child: _buildSectionLabel('Reminders', 'unread')),
                      SliverToBoxAdapter(child: _buildRemindersList(context)),
                    ],
                    SliverToBoxAdapter(child: _buildSectionLabel('Extras', '')),
                    SliverToBoxAdapter(child: _buildExtrasRow(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 140)),
                  ],
                ),
        ),
      ],
    );
  }

  // ── HEADER — standard format ────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _muted)),
              Text(_firstName,
                  style: const TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text("Have a productive day",
                  style: TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const TopActionButtons(unreadCount: 3),
        ],
      ),
    );
  }

  // ── SECTION LABEL ───────────────────────────────────────────
  Widget _buildSectionLabel(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.4)),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(sub,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _muted)),
          ],
        ],
      ),
    );
  }

  // ── STAT CARDS ──────────────────────────────────────────────
  Widget _buildStatCards() {
    final attColor = _attPct >= 80 ? _green : (_attPct >= 70 ? _darkYellow : _red);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'CGPA',
              value: _cgpa > 0 ? _cgpa.toStringAsFixed(2) : '--',
              sub: 'Cumulative',
              dark: true,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Attendance',
              value: _attPct > 0 ? '${_attPct.toStringAsFixed(0)}%' : '--%',
              sub: 'Overall',
              dark: false,
              valueColor: attColor,
            ),
          ),
          const SizedBox(width: 12),
          // Date chip
          Container(
            width: 68,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _yellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _yellow.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              children: [
                Text(_dayAbbr(),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: _darkYellow,
                        letterSpacing: -0.3)),
                const SizedBox(height: 2),
                Text('${DateTime.now().day}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                        letterSpacing: -0.8,
                        height: 1.0)),
                Text(_monthAbbr(),
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dayAbbr() {
    const d = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return d[DateTime.now().weekday - 1];
  }

  String _monthAbbr() {
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
               'Jul','Aug','Sep','Oct','Nov','Dec'];
    return m[DateTime.now().month - 1];
  }

  // ── LIVE REMINDERS ──────────────────────────────────────────
  Widget _buildRemindersList(BuildContext context) {
    return Column(
      children: _reminders.map((r) {
        final title = (r['title'] ?? 'Reminder') as String;
        final time  = (r['time']  ?? '') as String;
        return GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SmartReminderScreen())),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _yellow.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.notifications_active_rounded,
                      color: _darkYellow, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                              letterSpacing: -0.2)),
                      if (time.isNotEmpty)
                        Text(time,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _muted)),
                    ],
                  ),
                ),
                // unread dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: _red, shape: BoxShape.circle),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── EXTRAS ROW: Library + Study Timer ──────────────────────
  Widget _buildExtrasRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Library tile
          Expanded(
            child: GestureDetector(
              onTap: () => _showLibraryDialog(context),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: const Color(0xFF007AFF).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.menu_book_rounded,
                          color: Color(0xFF007AFF), size: 20),
                    ),
                    const SizedBox(height: 12),
                    const Text('Library',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 3),
                    Text(
                      _libraryBooks.isEmpty
                          ? 'No books issued'
                          : '${_libraryBooks.length} book${_libraryBooks.length > 1 ? 's' : ''} issued',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _muted),
                    ),
                    if (_libraryBooks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      // Due date warning for soonest book
                      Builder(builder: (_) {
                        final due = _libraryBooks.first['dueDate'];
                        if (due == null) return const SizedBox.shrink();
                        final dueDate = (due is DateTime)
                            ? due
                            : (due as dynamic).toDate();
                        final diff = dueDate.difference(DateTime.now()).inDays;
                        final color = diff <= 2 ? _red : _darkYellow;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            diff <= 0
                                ? 'Overdue!'
                                : 'Due in $diff day${diff > 1 ? 's' : ''}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Study Timer tile
          Expanded(
            child: GestureDetector(
              onTap: () => _showStudyTimerDialog(context),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.035),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: const Color(0xFFA78BFA).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.timer_rounded,
                          color: Color(0xFFA78BFA), size: 20),
                    ),
                    const SizedBox(height: 12),
                    const Text('Study Timer',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.2)),
                    const SizedBox(height: 3),
                    const Text('Pomodoro & focus',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: _muted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LIBRARY DIALOG ──────────────────────────────────────────
  void _showLibraryDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LibraryDialog(
        books: _libraryBooks,
        uid: FirebaseAuth.instance.currentUser?.uid ?? '',
        onRefresh: () => _fetchDashboardData(),
      ),
    );
  }

  // ── STUDY TIMER DIALOG ──────────────────────────────────────
  void _showStudyTimerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _StudyTimerDialog(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final bool dark;
  final Color? valueColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.dark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    const yellow = Color(0xFFFFD166);
    const ink    = Color(0xFF1A1D20);
    final bg     = dark ? ink : Colors.white;
    final fg     = dark ? Colors.white : ink;
    final acc    = dark ? yellow : ink;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.15 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: acc,
                      letterSpacing: 1.0)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: acc.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(sub,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: acc)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: valueColor ?? fg,
                  letterSpacing: -1.0,
                  height: 1.0)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NEXT CLASS SLIDER — shows only upcoming classes
// Past classes are stripped before passing in. User can only
// swipe forward through remaining classes. When all are done
// (or no class day) a styled end-state tile is shown instead.
// ─────────────────────────────────────────────────────────────
class _NextClassSlider extends StatefulWidget {
  final List<Map<String, dynamic>> upcomingClasses;
  final bool allDoneToday; // true: had classes but all ended

  const _NextClassSlider({
    required this.upcomingClasses,
    required this.allDoneToday,
  });

  @override
  State<_NextClassSlider> createState() => _NextClassSliderState();
}

class _NextClassSliderState extends State<_NextClassSlider> {
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _green      = Color(0xFF34C759);

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
    // No classes at all today (weekend / holiday / no timetable entry)
    if (!widget.allDoneToday && widget.upcomingClasses.isEmpty) {
      return _freeDay();
    }

    // All classes for today have ended
    if (widget.allDoneToday && widget.upcomingClasses.isEmpty) {
      return _allDone();
    }

    // Normal upcoming list
    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: widget.upcomingClasses.length,
            itemBuilder: (_, i) {
              final isFirst = i == 0;
              final accent  = _accents[i % _accents.length];
              return AnimatedScale(
                scale: _currentPage == i ? 1.0 : 0.95,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _classCard(widget.upcomingClasses[i], accent, isFirst),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.upcomingClasses.length, (i) {
            final isActive = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive ? _darkYellow : _muted.withOpacity(0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _classCard(Map<String, dynamic> cls, Color accent, bool isNext) {
    final subject = (cls['subject'] ?? '') as String;
    final time    = (cls['time']    ?? '') as String;
    final room    = (cls['room']    ?? '') as String;
    final parts   = subject.split(':');
    final code    = parts.first.trim();
    final name    = parts.length > 1 ? parts[1].trim() : subject;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isNext ? accent.withOpacity(0.5) : Colors.white,
            width: isNext ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: isNext
                ? accent.withOpacity(0.18)
                : Colors.black.withOpacity(0.03),
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
                color: accent, borderRadius: BorderRadius.circular(2)),
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
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(code,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: accent,
                              letterSpacing: 0.4)),
                    ),
                    const SizedBox(width: 6),
                    if (isNext)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('NEXT',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: _ink,
                                letterSpacing: 0.6)),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.2,
                        height: 1.1),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: _muted),
                    const SizedBox(width: 4),
                    Text(time,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _muted)),
                    const SizedBox(width: 10),
                    const Icon(Icons.location_on_rounded,
                        size: 12, color: _muted),
                    const SizedBox(width: 3),
                    Text(room,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _muted)),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: _muted),
        ],
      ),
    );
  }

  // ── ALL CLASSES DONE today ──────────────────────────────────
  Widget _allDone() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 108,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _green.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: _green.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
                color: _green, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 18),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🎓',
                  style: TextStyle(fontSize: 26, height: 1.0)),
              const SizedBox(height: 5),
              const Text('All classes done!',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text('You made it through the day',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted)),
            ],
          ),
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(right: 20),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('✓ Done',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _green)),
          ),
        ],
      ),
    );
  }

  // ── FREE DAY (no classes at all today) ─────────────────────
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
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          Container(
            width: 4,
            height: 64,
            decoration: BoxDecoration(
                color: _yellow, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 18),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(msg.$1,
                  style: const TextStyle(fontSize: 26, height: 1.0)),
              const SizedBox(height: 5),
              Text(msg.$2,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text(msg.$3,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// LIBRARY DIALOG
// ─────────────────────────────────────────────────────────────
class _LibraryDialog extends StatefulWidget {
  final List<Map<String, dynamic>> books;
  final String uid;
  final VoidCallback onRefresh;

  const _LibraryDialog({
    required this.books,
    required this.uid,
    required this.onRefresh,
  });

  @override
  State<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<_LibraryDialog> {
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _red        = Color(0xFFFF3B30);
  static const Color _green      = Color(0xFF34C759);
  static const Color _blue       = Color(0xFF007AFF);

  late List<Map<String, dynamic>> _books;
  final _titleCtrl = TextEditingController();
  DateTime? _dueDate;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _books = List.from(widget.books);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _addBook() async {
    if (_titleCtrl.text.trim().isEmpty || _dueDate == null) return;
    setState(() => _adding = true);

    final data = {
      'title':   _titleCtrl.text.trim(),
      'dueDate': Timestamp.fromDate(_dueDate!),
      'addedAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('students')
          .doc(widget.uid)
          .collection('library')
          .add(data);

      _titleCtrl.clear();
      setState(() {
        _books.add({...data, 'dueDate': _dueDate});
        _dueDate = null;
        _adding  = false;
      });
      widget.onRefresh();
    } catch (e) {
      setState(() => _adding = false);
    }
  }

  Future<void> _returnBook(String id, int index) async {
    await FirebaseFirestore.instance
        .collection('students')
        .doc(widget.uid)
        .collection('library')
        .doc(id)
        .delete();

    setState(() => _books.removeAt(index));
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),

          // header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.menu_book_rounded,
                    color: _blue, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Library Tracker',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _ink)),
                  Text('Track your issued books',
                      style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          // book list
          if (_books.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.28),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _books.length,
                itemBuilder: (_, i) {
                  final b   = _books[i];
                  final due = b['dueDate'];
                  DateTime? dueDate;
                  if (due is Timestamp) dueDate = due.toDate();
                  if (due is DateTime) dueDate   = due;
                  final diff = dueDate != null
                      ? dueDate.difference(DateTime.now()).inDays
                      : null;
                  final dueColor = diff != null
                      ? (diff <= 0 ? _red : (diff <= 3 ? _darkYellow : _green))
                      : _muted;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.book_rounded,
                            color: _blue, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b['title'] ?? '',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _ink)),
                              if (dueDate != null)
                                Text(
                                  diff! <= 0
                                      ? 'Overdue!'
                                      : 'Due in $diff day${diff > 1 ? 's' : ''}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: dueColor),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _returnBook(b['id'] ?? '', i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('Return',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _green)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 16),

          // add book input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _bg, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Issue a new book',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                const SizedBox(height: 10),
                TextField(
                  controller: _titleCtrl,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Book title',
                    hintStyle: TextStyle(color: _muted, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            size: 14, color: _muted),
                        const SizedBox(width: 8),
                        Text(
                          _dueDate == null
                              ? 'Pick due date'
                              : 'Due: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _dueDate == null ? _muted : _ink),
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
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _adding ? null : _addBook,
                    child: _adding
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Text('Issue Book',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
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

// ─────────────────────────────────────────────────────────────
// STUDY TIMER DIALOG  — Pomodoro-style
// ─────────────────────────────────────────────────────────────
class _StudyTimerDialog extends StatefulWidget {
  const _StudyTimerDialog();
  @override
  State<_StudyTimerDialog> createState() => _StudyTimerDialogState();
}

class _StudyTimerDialogState extends State<_StudyTimerDialog>
    with SingleTickerProviderStateMixin {
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _purple     = Color(0xFFA78BFA);
  static const Color _green      = Color(0xFF34C759);
  static const Color _red        = Color(0xFFFF3B30);

  // Presets in minutes
  static const _presets = [
    ('25 min', 25, '🍅 Pomodoro'),
    ('45 min', 45, '📖 Deep focus'),
    ('15 min', 15, '⚡ Quick sprint'),
  ];

  int _selectedPreset = 0;
  int _remainingSeconds = 25 * 60;
  bool _running = false;
  bool _finished = false;

  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _presets[0].$2 * 60;
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.04)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _tick() {
    if (!_running || !mounted) return;
    setState(() {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        Future.delayed(const Duration(seconds: 1), _tick);
      } else {
        _running  = false;
        _finished = true;
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _toggleTimer() {
    HapticFeedback.mediumImpact();
    setState(() => _running = !_running);
    if (_running) Future.delayed(const Duration(seconds: 1), _tick);
  }

  void _resetTimer() {
    HapticFeedback.lightImpact();
    setState(() {
      _running          = false;
      _finished         = false;
      _remainingSeconds = _presets[_selectedPreset].$2 * 60;
    });
  }

  void _selectPreset(int i) {
    if (_running) return;
    setState(() {
      _selectedPreset   = i;
      _remainingSeconds = _presets[i].$2 * 60;
      _finished         = false;
    });
  }

  String get _timeDisplay {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress {
    final total = _presets[_selectedPreset].$2 * 60;
    return 1.0 - (_remainingSeconds / total);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _finished ? _green : (_running ? _purple : _darkYellow);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.timer_rounded, color: _purple, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Study Timer',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: _ink)),
                  Text('Stay focused, stay sharp',
                      style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Preset chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_presets.length, (i) {
              final active = i == _selectedPreset;
              return GestureDetector(
                onTap: () => _selectPreset(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? _ink : _bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_presets[i].$1,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : _muted)),
                ),
              );
            }),
          ),

          const SizedBox(height: 8),
          Text(_presets[_selectedPreset].$3,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _muted)),

          const SizedBox(height: 24),

          // Timer circle
          ScaleTransition(
            scale: _running ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 8,
                    backgroundColor: _bg,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_finished)
                      const Text('🎉',
                          style: TextStyle(fontSize: 32, height: 1.0))
                    else
                      Text(_timeDisplay,
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: _ink,
                              letterSpacing: -1.0)),
                    const SizedBox(height: 4),
                    Text(
                      _finished
                          ? 'Well done!'
                          : (_running ? 'Focusing...' : 'Ready'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accent),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: _finished ? Colors.white : _ink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _finished ? _resetTimer : _toggleTimer,
                  child: Text(
                    _finished
                        ? 'Start Again'
                        : (_running ? 'Pause' : 'Start'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ),
              if (!_finished) ...[
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _resetTimer,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(14)),
                    child:
                        const Icon(Icons.refresh_rounded, color: _muted, size: 20),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TopActionButtons — reusable across all screens
// ─────────────────────────────────────────────────────────────
class TopActionButtons extends StatelessWidget {
  final int unreadCount;
  const TopActionButtons({super.key, this.unreadCount = 0});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SmartReminderScreen())),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded,
                    color: Color(0xFF1A1D20), size: 24),
                if (unreadCount > 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.redAccent, shape: BoxShape.circle),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfileScreen())),
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
                    color: Color(0x66FFD166),
                    blurRadius: 8,
                    offset: Offset(0, 4))
              ],
            ),
            child: const Icon(Icons.person_rounded,
                color: Color(0xFF1A1D20), size: 26),
          ),
        ),
      ],
    );
  }
}