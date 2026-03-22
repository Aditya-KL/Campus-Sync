import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────
// GRADE POINT TABLE  (official institute scale)
// ─────────────────────────────────────────────────────────────
const Map<String, double> _gradePoints = {
  'AA': 10.0,
  'AB': 9.0,
  'BB': 8.0,
  'BC': 7.0,
  'CC': 6.0,
  'CD': 5.0,
  'DD': 4.0,
  'F':  0.0,
  '-':  0.0,
};

String _marksToGrade(double marks) {
  if (marks == 0) return '-';
  if (marks >= 91) return 'AA';
  if (marks >= 81) return 'AB';
  if (marks >= 71) return 'BB';
  if (marks >= 61) return 'BC';
  if (marks >= 51) return 'CC';
  if (marks >= 41) return 'CD';
  if (marks >= 30) return 'DD';
  return 'F';
}

double _gradeToPoint(String grade) => _gradePoints[grade] ?? 0.0;

// ─────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────
class CourseGrade {
  final String id;
  final String name;
  final double credit;
  String expectedGrade;
  double marksObtained;
  Map<String, dynamic>? advancedGrading;

  CourseGrade({
    required this.id,
    required this.name,
    required this.credit,
    this.expectedGrade = '-',
    this.marksObtained = 0.0,
    this.advancedGrading,
  });
}

class PastSemester {
  final int semester;
  int credit;       // mutable — user can edit
  double spi;       // mutable — user can edit; CGPA re-derives from this
  double cpi;       // derived, stored for display only
  PastSemester({
    required this.semester,
    required this.credit,
    required this.spi,
    required this.cpi,
  });
}

// ─────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────
class GradeCalculatorScreen extends StatefulWidget {
  const GradeCalculatorScreen({super.key});
  @override
  State<GradeCalculatorScreen> createState() => _GradeCalculatorScreenState();
}

class _GradeCalculatorScreenState extends State<GradeCalculatorScreen> {
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF4F5F7);
  static const Color _ink        = Color(0xFF0F1117);
  static const Color _muted      = Color(0xFF8A8F9D);
  static const Color _green      = Color(0xFF34C759);
  static const Color _red        = Color(0xFFFF3B30);

  bool _isLoading = true;
  int  _currentSemester = 1;
  List<CourseGrade>  _currentCourses = [];
  List<PastSemester> _pastSemesters  = [];

  // ── Editable SGPA controllers — one per past semester row ──
  final Map<int, TextEditingController> _spiCtrls = {};

  // Recomputes the cumulative CPI column for all past rows
  // using the official CGPA formula: Σ(Ci×Pi)/Σ(Ci)
  void _recomputePastCGPA() {
    double sumCP = 0, sumC = 0;
    for (final s in _pastSemesters) {
      sumCP += s.credit * s.spi;
      sumC  += s.credit;
      s.cpi = sumC > 0 ? sumCP / sumC : 0.0;
    }
  }

  // ── Persist an edited SGPA value back to Firestore ──────────
  // Updates the matching entry inside the pastSemesters array.
  // Uses a transaction so concurrent edits don't corrupt the array.
  // Debounce is handled implicitly: each keystroke fires this but
  // Firestore offline persistence queues and deduplicates writes.
  Future<void> _saveSpiToDb(String uid, int semester, double newSpi) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('students').doc(uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return;

        final rawList = ((snap.data()?['pastSemesters'] as List?) ?? [])
            .cast<Map<String, dynamic>>();

        // Find the entry for this semester and update its spi
        bool found = false;
        final updated = rawList.map((m) {
          if ((m['semester'] ?? 0) == semester) {
            found = true;
            // Preserve all existing fields, only overwrite spi/spi-space
            return {
              ...m,
              'spi': newSpi,
              'spi ': newSpi, // keep trailing-space key in sync
            };
          }
          return m;
        }).toList();

        if (!found) {
          // Semester wasn't in DB yet (was a placeholder) → append it
          updated.add({
            'semester': semester,
            'credit':   _pastSemesters
                .firstWhere((s) => s.semester == semester,
                    orElse: () => PastSemester(semester: semester, credit: 21, spi: newSpi, cpi: 0.0))
                .credit,
            'spi':  newSpi,
            'spi ': newSpi,
            'cpi':  _pastSemesters
                .firstWhere((s) => s.semester == semester,
                    orElse: () => PastSemester(semester: semester, credit: 21, spi: newSpi, cpi: 0.0))
                .cpi,
          });
        }

        tx.update(docRef, {'pastSemesters': updated});
      });
    } catch (e) {
      debugPrint('SGPA save error (sem $semester): $e');
    }
  }

  // ── SGPA formula  Σ(Ci×Pi)/Σ(Ci)  for current sem ──────────
  double get _currentSPI {
    double sumCP = 0, sumC = 0;
    for (final c in _currentCourses) {
      if (c.expectedGrade == '-') continue;
      sumCP += c.credit * _gradeToPoint(c.expectedGrade);
      sumC  += c.credit;
    }
    return sumC > 0 ? sumCP / sumC : 0.0;
  }

  // ── CGPA formula  Σ(Ci×Pi)/Σ(Ci)  across ALL semesters ────
  double get _calculatedCGPA {
    double sumCP = 0, sumC = 0;
    for (final s in _pastSemesters) {
      sumCP += s.credit * s.spi;
      sumC  += s.credit;
    }
    for (final c in _currentCourses) {
      if (c.expectedGrade == '-') continue;
      sumCP += c.credit * _gradeToPoint(c.expectedGrade);
      sumC  += c.credit;
    }
    return sumC > 0 ? sumCP / sumC : 0.0;
  }

  int _totalCredits() {
    final pastCr = _pastSemesters.fold(0, (s, p) => s + p.credit);
    final curCr  = _currentCourses.fold(0.0, (s, c) => s + c.credit).toInt();
    return pastCr + curCr;
  }

  @override
  void dispose() {
    _spiCtrls.forEach((_, c) => c.dispose());
    super.dispose();
  }

  int _calculateCurrentSemester(String roll) {
    if (roll.length < 4) return 1;
    final joinYear  = 2000 + (int.tryParse(roll.substring(0, 2)) ?? 24);
    final joinDate  = DateTime(joinYear, 7, 1);
    final now       = DateTime.now();
    final months    = (now.year - joinDate.year) * 12 + now.month - joinDate.month;
    return months < 0 ? 1 : (months / 6).floor() + 1;
  }

  double _calcPredictedScore(Map<String, dynamic> d) {
    final tW = ((d['theory_weight'] ?? 70.0) as num).toDouble();
    final lW = ((d['lab_weight']   ?? 30.0) as num).toDouble();
    double tScore = 0, lScore = 0;
    for (final c in (d['theory'] ?? []) as List) {
      final w = ((c['weight'] ?? 0.0) as num).toDouble();
      final t = ((c['total']  ?? 0.0) as num).toDouble();
      final o = ((c['obtained'] ?? 0.0) as num).toDouble();
      if (t > 0) tScore += (o / t) * w;
    }
    for (final c in (d['lab'] ?? []) as List) {
      final w = ((c['weight'] ?? 0.0) as num).toDouble();
      final t = ((c['total']  ?? 0.0) as num).toDouble();
      final o = ((c['obtained'] ?? 0.0) as num).toDouble();
      if (t > 0) lScore += (o / t) * w;
    }
    return (tScore * (tW / 100)) + (lScore * (lW / 100));
  }

  // ── init ───────────────────────────────────────────────────
  @override
  void initState() { super.initState(); _fetchAcademicData(); }

  // ─────────────────────────────────────────────────────────
  // Helper: get(source: cache) first, fall back to server.
  // This makes every read instant on revisit (offline cache
  // is already enabled via Settings in main.dart).
  // ─────────────────────────────────────────────────────────
  Future<DocumentSnapshot<Map<String, dynamic>>> _getCached(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return ref.get(const GetOptions(source: Source.server));
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _getQueryCached(
      Query<Map<String, dynamic>> query) async {
    try {
      return await query.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return query.get(const GetOptions(source: Source.server));
    }
  }

  Future<void> _fetchAcademicData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final db = FirebaseFirestore.instance;

      // ── Step 1: student doc (needed to build other query paths) ─
      final sd = (await _getCached(
              db.collection('students').doc(user.uid))).data();
      if (sd == null) { setState(() => _isLoading = false); return; }

      final rollNo = (sd['rollNo'] ?? '2401cs80') as String;
      final branch = (sd['branch'] ?? 'CSE') as String;
      _currentSemester = _calculateCurrentSemester(rollNo);

      // ── Step 2: fire remaining 3 reads IN PARALLEL ─────────────
      final results = await Future.wait([
        // [0] saved grading structures for current courses
        _getQueryCached(
          db.collection('students').doc(user.uid).collection('course_grades')
              as Query<Map<String, dynamic>>,
        ),
        // [1] curriculum for current semester
        _getCached(
          db.collection('curriculum')
              .doc('${branch.toUpperCase()}_Sem$_currentSemester'),),
        // [2] sem_credits — small doc, rarely changes, but wrong credits are
        //     highly visible. Use serverAndCache so it always fetches fresh
        //     data but also caches it for subsequent offline use.
        db.collection('sem_credits')
            .doc(branch.toUpperCase())
            .get(const GetOptions(source: Source.serverAndCache)),
      ]);

      final gradesSnap  = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final currSnap    = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final creditsSnap = results[2] as DocumentSnapshot<Map<String, dynamic>>;

      final savedGrades = { for (final d in gradesSnap.docs) d.id: d.data() };

      // ── sem_credits lookup ──────────────────────────────────────
      // DB structure (from screenshot):
      //   sem_credits/CSE → { Credits: { "Semester 1": 24, "Semester 2": 22, ... } }
      // Falls back to 21 if the document or field is missing.
      final rawCreditsDoc = creditsSnap.data() ?? {};

      // The credits are nested inside a "Credits" map field
      final Map<String, dynamic> creditsMap =
          (rawCreditsDoc['Credits'] as Map<String, dynamic>?) ?? {};

      // Also support flat top-level keys as a secondary fallback
      int _creditForSem(int sem) {
        // Primary: nested Credits map with "Semester N" key (your DB format)
        final nested = creditsMap['Semester $sem'];
        if (nested != null) return (nested as num).toInt();
        // Secondary: flat top-level "Semester N" key
        final flat = rawCreditsDoc['Semester $sem'];
        if (flat != null) return (flat as num).toInt();
        // Tertiary: legacy "sem_N" key (old format)
        final legacy = rawCreditsDoc['sem_$sem'] ?? creditsMap['sem_$sem'];
        if (legacy != null) return (legacy as num).toInt();
        // Final fallback
        return 21;
      }

      // ── past semesters: DB pastSemesters array ──────────────────
      // Priority: DB SGPA > placeholder 8.0
      // The spi field in Firestore has a trailing space ("spi ") — handle both.
      final rawPast = ((sd['pastSemesters'] as List?) ?? [])
          .cast<Map<String, dynamic>>();

      // Build a lookup map: semesterNumber → DB row
      final Map<int, Map<String, dynamic>> dbSemMap = {
        for (final m in rawPast)
          (m['semester'] ?? 0) as int: m
      };

      final List<PastSemester> pastSems = [];
      for (int sem = 1; sem < _currentSemester; sem++) {
        final dbRow = dbSemMap[sem];
        // sem_credits is always the authoritative credit source.
        // pastSemesters.credit from DB is only used if sem_credits has no entry.
        final authorativeCredit = _creditForSem(sem);
        if (dbRow != null) {
          // ✅ DB has SGPA data for this semester — use it, but always prefer sem_credits for credit
          pastSems.add(PastSemester(
            semester: sem,
            credit:   authorativeCredit,   // from sem_credits, not from pastSemesters.credit
            spi:      ((dbRow['spi'] ?? dbRow['spi '] ?? 8.0) as num).toDouble(),
            cpi:      ((dbRow['cpi'] ?? 0.0) as num).toDouble(),
          ));
        } else {
          // ⚠️ Semester missing from DB — placeholder with default SGPA 8.0
          pastSems.add(PastSemester(
            semester: sem,
            credit:   authorativeCredit,
            spi:      8.0,
            cpi:      0.0,
          ));
        }
      }
      pastSems.sort((a, b) => a.semester.compareTo(b.semester));

      // ── current semester courses ────────────────────────────────
      final List<CourseGrade> courses = [];
      if (currSnap.exists) {
        final marks = (sd['marks'] as Map<String, dynamic>?) ?? {};
        for (final raw in (currSnap.data()?['courses'] ?? []) as List) {
          final code   = (raw['code']   ?? '') as String;
          final name   = (raw['name']   ?? '') as String;
          final credit = ((raw['credit'] ?? 0) as num).toDouble();
          final saved  = savedGrades[code];

          double obt;
          String grade;

          if (saved != null) {
            obt   = _calcPredictedScore(saved);
            grade = _marksToGrade(obt);
          } else {
            // No saved structure: use DB marks if present, else default AA
            final dbMarks = ((marks[name] ?? -1.0) as num).toDouble();
            obt   = dbMarks >= 0 ? dbMarks : 100.0;
            grade = _marksToGrade(obt);
          }

          courses.add(CourseGrade(
            id: code, name: name, credit: credit,
            marksObtained: obt, expectedGrade: grade,
            advancedGrading: saved,
          ));
        }
      }

      setState(() {
        _pastSemesters  = pastSems;
        _currentCourses = courses;
        _isLoading      = false;
      });

      // Build one editable controller per past semester.
      // On change: update model, recompute CGPA, and persist to Firestore.
      final uid = user.uid;
      for (final s in pastSems) {
        _spiCtrls[s.semester] =
            TextEditingController(text: s.spi.toStringAsFixed(2))
              ..addListener(() {
                final v = double.tryParse(_spiCtrls[s.semester]!.text);
                if (v != null) {
                  final clamped = v.clamp(0.0, 10.0);
                  s.spi = clamped;
                  _recomputePastCGPA();
                  setState(() {});
                  // ✅ Persist updated SGPA to Firestore
                  _saveSpiToDb(uid, s.semester, clamped);
                }
              });
      }
      _recomputePastCGPA();

    } catch (e) {
      debugPrint('GradeCalculator fetch error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _openDialog(CourseGrade course) {
    showDialog(
      context: context,
      builder: (_) => _WeightageDialog(
        course: course,
        onSave: (predicted, grade, data) async {
          setState(() { course.marksObtained = predicted; course.expectedGrade = grade; course.advancedGrading = data; });
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await FirebaseFirestore.instance
                .collection('students').doc(user.uid)
                .collection('course_grades').doc(course.id)
                .set(data, SetOptions(merge: false));
          }
        },
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── bubble background (original theme) ────────────
          Positioned(top: -60, right: -40,
              child: CircleAvatar(radius: 140, backgroundColor: _yellow.withOpacity(0.35))),
          Positioned(top: 150, left: -80,
              child: CircleAvatar(radius: 100, backgroundColor: const Color(0xFFE2E5E9))),
          Positioned(bottom: -30, right: -20,
              child: CircleAvatar(radius: 130, backgroundColor: _yellow.withOpacity(0.15))),

          SafeArea(
            bottom: false,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _yellow))
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader()),
                      SliverToBoxAdapter(child: _statsRow()),
                      SliverToBoxAdapter(child: _sectionLabel('Current Semester', 'Tap a course to set marks')),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        sliver: SliverList(delegate: SliverChildBuilderDelegate(
                          (_, i) => _courseRow(_currentCourses[i]),
                          childCount: _currentCourses.length,
                        )),
                      ),
                      SliverToBoxAdapter(child: _sectionLabel('Academic History', 'Tap on SGPA to edit')),
                      SliverToBoxAdapter(child: _historyTable()),
                      const SliverToBoxAdapter(child: SizedBox(height: 120)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left: title block with subtitle
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Grade',
              style: TextStyle(
                fontSize: 31,
                fontWeight: FontWeight.w900,
                color: _ink,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Calculator',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: _yellow,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Track your academic progress',
              style: TextStyle(
                fontSize: 13,
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        // Right: notification + profile buttons stacked at top
        const TopActionButtons(unreadCount: 3),
      ],
    ),
  );

  Widget _statsRow() {
    final cgpa = _calculatedCGPA;
    final spi  = _currentSPI;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: [
          Expanded(child: _StatCard(label: 'CGPA', sub: 'Cumulative', value: cgpa.toStringAsFixed(2), dark: false)),
          const SizedBox(width: 12),
          Expanded(child: _StatCard(label: 'SGPA', sub: 'Sem $_currentSemester', value: spi > 0 ? spi.toStringAsFixed(2) : '--', dark: true)),
          const SizedBox(width: 12),
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _yellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _yellow.withOpacity(0.4), width: 1.5),
            ),
            child: Column(
              children: [
                Text('${_totalCredits()}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -0.8, height: 1.0)),
                const SizedBox(height: 4),
                const Text('Credits', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _muted)),
                const Text('earned',  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String title, String sub) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
        const SizedBox(width: 8),
        Text(sub,   style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _muted)),
      ],
    ),
  );

  Widget _courseRow(CourseGrade course) {
    final gp = _gradeToPoint(course.expectedGrade);
    final hasGrade = course.expectedGrade != '-';
    Color gc = _muted;
    if (hasGrade) gc = gp >= 8 ? _green : (gp >= 6 ? _darkYellow : _red);

    return GestureDetector(
      onTap: () => _openDialog(course),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(
                course.credit % 1 == 0 ? course.credit.toInt().toString() : course.credit.toString(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _muted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink, letterSpacing: -0.2)),
                  if (course.advancedGrading != null)
                    Text('${course.marksObtained.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _muted)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: gc.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(hasGrade ? course.expectedGrade : '--',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: gc, letterSpacing: 0.5)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _historyTable() {
    if (_pastSemesters.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Text('No past records', style: TextStyle(color: _muted, fontSize: 14))),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            // ── header row ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: ['Sem', 'Credit', 'SGPA', 'CGPA'].map((h) =>
                  Expanded(child: Text(h, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                          color: _muted, letterSpacing: 0.6)))).toList(),
              ),
            ),
            const Divider(height: 1, color: _bg),

            // ── past semester rows (SGPA editable) ─────────
            ..._pastSemesters.asMap().entries.map((e) {
              final s = e.value;
              final isLast = e.key == _pastSemesters.length - 1;
              final ctrl = _spiCtrls[s.semester];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        // Sem badge
                        Expanded(child: Center(child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: _yellow.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(s.semester.toString(), textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w800, color: _darkYellow)),
                        ))),
                        // Credit
                        Expanded(child: Text(s.credit.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14,
                                fontWeight: FontWeight.w600, color: _muted))),
                        // SGPA — editable TextField, aligned same as other columns
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: SizedBox(
                              height: 32,
                              child: TextField(
                                controller: ctrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w800, color: _ink),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                  isDense: true,
                                  filled: true,
                                  fillColor: _yellow.withOpacity(0.12),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // CGPA — auto-derived, read-only
                        Expanded(child: Text(s.cpi.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15,
                                fontWeight: FontWeight.w900, color: _ink))),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16, color: _bg),
                ],
              );
            }),

            // ── current semester row (dark, read-only) ─────
            const Divider(height: 1, color: _bg),
            Container(
              decoration: const BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Expanded(child: Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(6)),
                    child: Text('$_currentSemester', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _ink)),
                  ))),
                  Expanded(child: Text(
                    _currentCourses.fold(0.0, (s, c) => s + c.credit).toInt().toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54),
                  )),
                  Expanded(child: Text(
                    _currentSPI > 0 ? _currentSPI.toStringAsFixed(2) : '--',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                  )),
                  Expanded(child: Text(
                    _calculatedCGPA > 0 ? _calculatedCGPA.toStringAsFixed(2) : '--',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _yellow),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, sub, value;
  final bool dark;
  const _StatCard({required this.label, required this.sub, required this.value, required this.dark});

  static const _yellow = Color(0xFFFFD166);
  static const _ink    = Color(0xFF0F1117);

  @override
  Widget build(BuildContext context) {
    final bg   = dark ? _ink : Colors.white;
    final fg   = dark ? Colors.white : _ink;
    final sfg  = dark ? Colors.white54 : const Color(0xFF8A8F9D);
    final acc  = dark ? _yellow : _ink;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(dark ? 0.15 : 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: acc, letterSpacing: 1.0)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: acc.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(sub, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: acc)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: fg, letterSpacing: -1.0, height: 1.0)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WEIGHTAGE DIALOG
// ─────────────────────────────────────────────────────────────
class _WeightageDialog extends StatefulWidget {
  final CourseGrade course;
  final Function(double, String, Map<String, dynamic>) onSave;
  const _WeightageDialog({required this.course, required this.onSave});
  @override
  State<_WeightageDialog> createState() => _WeightageDialogState();
}

class _WeightageDialogState extends State<_WeightageDialog> {
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF4F5F7);
  static const Color _ink        = Color(0xFF0F1117);
  static const Color _muted      = Color(0xFF8A8F9D);
  static const Color _green      = Color(0xFF34C759);
  static const Color _red        = Color(0xFFFF3B30);

  late TextEditingController _tWCtrl, _lWCtrl;
  List<Map<String, dynamic>> _theory = [], _lab = [];
  final Map<String, TextEditingController> _wC = {}, _tC = {};

  @override
  void initState() { super.initState(); _init(); }

  void _init() {
    final d = widget.course.advancedGrading ?? {
      'theory_weight': 70.0, 'lab_weight': 30.0,
      'theory': [
        {'name': 'Quiz 1',    'weight': 10.0, 'total': 10.0, 'obtained': 0.0},
        {'name': 'Midsem',   'weight': 30.0, 'total': 30.0, 'obtained': 0.0},
        {'name': 'Quiz 2',   'weight': 10.0, 'total': 10.0, 'obtained': 0.0},
        {'name': 'Endsem',   'weight': 50.0, 'total': 50.0, 'obtained': 0.0},
        {'name': 'Assignment','weight': 0.0,  'total': 10.0, 'obtained': 0.0},
        {'name': 'Project',  'weight': 0.0,  'total': 10.0, 'obtained': 0.0},
      ],
      'lab': [
        {'name': 'Regular Labs','weight': 50.0,'total': 50.0,'obtained': 0.0},
        {'name': 'Midsem Lab', 'weight': 20.0,'total': 20.0,'obtained': 0.0},
        {'name': 'Endsem Lab', 'weight': 30.0,'total': 30.0,'obtained': 0.0},
        {'name': 'Lab Project','weight': 0.0, 'total': 10.0,'obtained': 0.0},
      ],
    };
    _tWCtrl = TextEditingController(text: (d['theory_weight'] as double).toStringAsFixed(0));
    _lWCtrl = TextEditingController(text: (d['lab_weight']   as double).toStringAsFixed(0));
    _theory = (d['theory'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    _lab    = (d['lab']    as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    _tWCtrl.addListener(() => setState(() {}));
    _lWCtrl.addListener(() => setState(() {}));
    _initCtrls(_theory, 't');
    _initCtrls(_lab, 'l');
  }

  void _initCtrls(List<Map<String, dynamic>> items, String pfx) {
    for (int i = 0; i < items.length; i++) {
      final k = '${pfx}_$i';
      _wC[k] = TextEditingController(text: (items[i]['weight'] as double).toStringAsFixed(0));
      _tC[k] = TextEditingController(text: (items[i]['total']  as double).toStringAsFixed(0));
      _wC[k]!.addListener(() { items[i]['weight'] = double.tryParse(_wC[k]!.text) ?? 0.0; setState(() {}); });
      _tC[k]!.addListener(() {
        items[i]['total'] = double.tryParse(_tC[k]!.text) ?? 0.0;
        if ((items[i]['obtained'] as double) > (items[i]['total'] as double)) items[i]['obtained'] = items[i]['total'];
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tWCtrl.dispose(); _lWCtrl.dispose();
    _wC.forEach((_, c) => c.dispose());
    _tC.forEach((_, c) => c.dispose());
    super.dispose();
  }

  double get _tW => double.tryParse(_tWCtrl.text) ?? 0.0;
  double get _lW => double.tryParse(_lWCtrl.text) ?? 0.0;
  double get _tSum => _theory.fold(0.0, (s, i) => s + (i['weight'] as double));
  double get _lSum => _lab.fold(0.0, (s, i) => s + (i['weight'] as double));
  bool get _tOk => (_tSum - 100.0).abs() < 0.01;
  bool get _lOk => (_lSum - 100.0).abs() < 0.01;
  bool get _overallOk => ((_tW + _lW) - 100.0).abs() < 0.01;
  bool get _canSave => _tOk && _lOk && _overallOk;

  double get _predicted {
    double tScore = 0, lScore = 0;
    for (final c in _theory) {
      final w = c['weight'] as double; final t = c['total'] as double; final o = c['obtained'] as double;
      if (t > 0) tScore += (o / t) * w;
    }
    for (final c in _lab) {
      final w = c['weight'] as double; final t = c['total'] as double; final o = c['obtained'] as double;
      if (t > 0) lScore += (o / t) * w;
    }
    return (tScore * (_tW / 100)) + (lScore * (_lW / 100));
  }

  String get _predGrade => _marksToGrade(_predicted);
  Color get _gradeColor {
    final gp = _gradeToPoint(_predGrade);
    if (gp >= 8) return _green;
    if (gp >= 6) return _darkYellow;
    return _red;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(
          children: [
            _header(),
            if (!_overallOk || !_tOk || !_lOk) _errorBanner(),
            const Divider(height: 1, color: _bg),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
                child: Column(
                  children: [
                    _sectionHead('Theory', _tWCtrl, _tOk, _tSum),
                    ..._compList(_theory, 't'),
                    const SizedBox(height: 24),
                    _sectionHead('Lab', _lWCtrl, _lOk, _lSum),
                    ..._compList(_lab, 'l'),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.course.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.3, height: 1.2)),
              const SizedBox(height: 2),
              const Text('Dynamic Grade Prediction',
                  style: TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Live grade badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _gradeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _gradeColor.withOpacity(0.3), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_predGrade, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _gradeColor, height: 1.0)),
              const SizedBox(height: 2),
              Text('${_predicted.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _gradeColor)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(color: _bg, shape: BoxShape.circle),
            child: const Icon(Icons.close_rounded, size: 16, color: _ink),
          ),
        ),
      ],
    ),
  );

  Widget _errorBanner() {
    final msgs = <String>[];
    if (!_overallOk) msgs.add('Theory + Lab = ${(_tW + _lW).toStringAsFixed(0)}% (must be 100%)');
    if (!_tOk) msgs.add('Theory Σ = ${_tSum.toStringAsFixed(0)} (must be 100)');
    if (!_lOk) msgs.add('Lab Σ = ${_lSum.toStringAsFixed(0)} (must be 100)');
    return Container(
      color: _red.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: msgs.map((m) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 12, color: _red),
            const SizedBox(width: 6),
            Expanded(child: Text(m, style: const TextStyle(fontSize: 11, color: _red, fontWeight: FontWeight.w700))),
          ]),
        )).toList(),
      ),
    );
  }

  Widget _sectionHead(String title, TextEditingController ctrl, bool valid, double sum) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -0.4)),
          const SizedBox(width: 8),
          // ── WEIGHTAGE CHIP — now very prominent ────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: valid ? _yellow : _red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32, height: 22,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900, color: valid ? _ink : _red, fontSize: 13),
                    decoration: const InputDecoration(contentPadding: EdgeInsets.zero, border: InputBorder.none, isDense: true),
                  ),
                ),
                Text('%', style: TextStyle(fontWeight: FontWeight.w900, color: valid ? _ink : _red, fontSize: 13)),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: valid ? _green.withOpacity(0.1) : _red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Σ ${sum.toStringAsFixed(0)}/100',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: valid ? _green : _red)),
          ),
        ],
      ),
    );
  }

  List<Widget> _compList(List<Map<String, dynamic>> items, String pfx) {
    return List.generate(items.length, (i) {
      final k = '${pfx}_$i';
      final item = items[i];
      final t = item['total'] as double;
      final o = item['obtained'] as double;
      final w = item['weight'] as double;
      final enabled = w > 0 && t > 0;
      final pct = t > 0 ? (o / t) * 100 : 0.0;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: w > 0 ? _yellow.withOpacity(0.35) : _bg, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(item['name'] as String,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink))),
                _miniField('Wt',  _wC[k]!, w > 0 ? _yellow.withOpacity(0.2) : _bg),
                const SizedBox(width: 8),
                _miniField('Max', _tC[k]!, _bg),
              ],
            ),
            if (enabled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(width: 34,
                      child: Text(o.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _yellow))),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: o.clamp(0, t), min: 0, max: t,
                        divisions: (t * 2).toInt().clamp(1, 9999),
                        activeColor: _yellow, inactiveColor: _bg,
                        onChanged: (v) => setState(() => item['obtained'] = v),
                      ),
                    ),
                  ),
                  Text('${pct.toStringAsFixed(0)}%', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: pct >= 80 ? _green : (pct >= 60 ? _darkYellow : _red))),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              Text(w == 0 ? 'Set weight > 0 to enable' : 'Set total > 0 to enable',
                  style: const TextStyle(fontSize: 10, color: _muted, fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      );
    });
  }

  Widget _miniField(String label, TextEditingController ctrl, Color fill) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 9, color: _muted, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      SizedBox(width: 42, height: 28,
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _ink),
          decoration: InputDecoration(
            contentPadding: EdgeInsets.zero, isDense: true,
            filled: true, fillColor: fill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ),
    ],
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, -3))],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canSave) Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.check_circle_outline_rounded, size: 13, color: _green),
              SizedBox(width: 4),
              Text('All weights valid', style: TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _canSave ? _ink : _bg,
              foregroundColor: _canSave ? Colors.white : _muted,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: _canSave ? 2 : 0,
            ),
            onPressed: _canSave ? () {
              final data = {
                'theory_weight': _tW, 'lab_weight': _lW,
                'theory': _theory.map((x) => {'name': x['name'], 'weight': x['weight'], 'total': x['total'], 'obtained': x['obtained']}).toList(),
                'lab':    _lab.map(   (x) => {'name': x['name'], 'weight': x['weight'], 'total': x['total'], 'obtained': x['obtained']}).toList(),
              };
              widget.onSave(_predicted, _predGrade, data);
              Navigator.pop(context);
            } : null,
            child: Text(_canSave ? 'Save Grading Structure' : 'Fix Errors to Save',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ),
      ],
    ),
  );
}