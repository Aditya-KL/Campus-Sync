import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dashboard_screen.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  // --- Theme Colors ---
  final Color primaryYellow = const Color(0xFFFFD166);
  final Color darkYellow = const Color(0xFFE5A91A);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite = Colors.white;
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);
  final Color successGreen = const Color(0xFF4CAF50);
  final Color dangerRed = const Color(0xFFFF5252);

  // --- State Variables ---
  bool _isLoading = true;
  int _selectedDayIndex = DateTime.now().weekday - 1;
  final List<String> _days = ["Mon", "Tue", "Wed", "Thu", "Fri"];

  // Full day names map for Firestore keys
  final List<String> _fullDayNames = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
  ];

  List<dynamic> _todayClasses = [];
  List<Map<String, dynamic>> _myCourses = [];
  int _currentSemester = 1;

  // =========================================================================
  // 🟡 TIMETABLE SYNC LAYER
  // Separate in-memory cache for timetable_attendance UI state.
  // Key: "courseCode" → Value: Map<"Monday"/"Tuesday"/..., int (-1, 0, 1)>
  // =========================================================================
  Map<String, Map<String, int>> _timetableSyncCache = {};

  @override
  void initState() {
    super.initState();
    if (_selectedDayIndex > 4) _selectedDayIndex = 0;
    _initializeCoreDataAndCheckReset();
  }

  int _getTimetableSyncStatus(String courseCode) {
    String dayName = _fullDayNames[_selectedDayIndex];
    return _timetableSyncCache[courseCode]?[dayName] ?? 0;
  }

  // =========================================================================
  // 🟡 ATTENDANCE PATH: timetable_attendance/{uid}/attendance/{courseCode}
  // =========================================================================

  // ── Ref helpers ─────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _attendanceCol(String uid) =>
      FirebaseFirestore.instance
          .collection('timetable_attendance') // 🔥 Root collection!
          .doc(uid)
          .collection('attendance'); // 🔥 Subcollection!

  DocumentReference<Map<String, dynamic>> _attendanceDoc(
    String uid,
    String courseCode,
  ) => _attendanceCol(uid).doc(courseCode);

  // ── Write day-toggle status ───
  Future<void> _writeTimetableSyncStatus(
    String uid,
    String courseCode,
    String dayName,
    int status,
  ) async {
    assert(
      status == -1 || status == 0 || status == 1,
      "Invalid timetable sync status: $status",
    );
    await _attendanceDoc(
      uid,
      courseCode,
    ).set({dayName: status}, SetOptions(merge: true));
  }

  // ── Write attended/total to course doc ──
  Future<void> _writeAttendance(
    String uid,
    String courseCode,
    int attended,
    int total,
  ) async {
    await _attendanceDoc(
      uid,
      courseCode,
    ).set({'attended': attended, 'total': total}, SetOptions(merge: true));
  }

  // =========================================================================
  // 🟡 WEEKLY RESET
  // =========================================================================
  Future<void> _checkAndResetTimetableSyncIfNeeded(String uid) async {
    final db = FirebaseFirestore.instance;
    final metaRef = db
        .collection('timetable_attendance')
        .doc(uid)
        .collection('meta')
        .doc('attendance_prefs');
    final metaDoc = await _getCached(metaRef);

    final now = DateTime.now();
    final int daysSinceMonday = now.weekday - 1;
    final DateTime thisWeekMondayMidnight = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysSinceMonday));

    final Timestamp? lastResetTs = metaDoc.data()?['last_reset_timestamp'];
    final lastReset =
        lastResetTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

    if (lastReset.isBefore(thisWeekMondayMidnight)) {
      final attendanceSnap = await _attendanceCol(
        uid,
      ).get(const GetOptions(source: Source.server));

      final batch = db.batch();
      final Map<String, int> resetDays = {for (final d in _fullDayNames) d: 0};
      for (final doc in attendanceSnap.docs) {
        batch.set(doc.reference, resetDays, SetOptions(merge: true));
      }
      batch.set(metaRef, {
        'last_reset_timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (mounted) setState(() => _timetableSyncCache = {});
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        CustomTopToast.show(
          context,
          "Timetable sync reset for the new week! 📅",
          primaryYellow,
        );
      });
    }
  }

  // =========================================================================
  // 🚀 CACHE-FIRST HELPERS
  // =========================================================================
  Future<DocumentSnapshot<Map<String, dynamic>>> _getCached(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return ref.get(const GetOptions(source: Source.server));
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _getQueryCached(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      return await query.get(const GetOptions(source: Source.cache));
    } catch (_) {
      return query.get(const GetOptions(source: Source.server));
    }
  }

  // =========================================================================
  // 🔴 1. INITIALIZATION & STRICT WEEKLY RESET
  // =========================================================================
  int _calculateCurrentSemester(String roll) {
    if (roll.length < 4) return 1;
    int joinYear = 2000 + (int.tryParse(roll.substring(0, 2)) ?? 24);
    DateTime now = DateTime.now();
    int yearsDifference = now.year - joinYear;
    int semester;
    if (now.month >= 7) {
      semester = (yearsDifference * 2) + 1;
    } else {
      semester = (yearsDifference * 2);
    }
    return semester < 1 ? 1 : semester;
  }

  String _extractCourseCode(String subjectStr) =>
      subjectStr.split(":")[0].trim();
  String _extractCourseName(String subjectStr) {
    List<String> parts = subjectStr.split(":");
    return parts.length > 1 ? parts[1].trim() : subjectStr;
  }

  Future<void> _initializeCoreDataAndCheckReset() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final db = FirebaseFirestore.instance;

      // Note: We still need to read the student doc once just to get their Branch and Roll Number!
      final userDocRef = db.collection('students').doc(user.uid);

      // ── Step 1: student doc (cache-first) ──
      final userDoc = await _getCached(userDocRef);
      if (!userDoc.exists) return;

      final String branch = userDoc.data()?['branch'] ?? "CSE";
      final String rollNo = userDoc.data()?['rollNo'] ?? "2401cs80";
      _currentSemester = _calculateCurrentSemester(rollNo);

      // ── Weekly reset check ──
      await _checkAndResetTimetableSyncIfNeeded(user.uid);

      // ── Step 2: build paths, fire IN PARALLEL ──
      final int startYear = 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24);
      final int duration =
          (rollNo.length >= 4 &&
              (rollNo.substring(2, 4) == '02' ||
                  rollNo.substring(2, 4) == '03'))
          ? 5
          : 4;
      final String batchId = "$startYear-${startYear + duration}";
      final String timetableDocId = "${branch.toUpperCase()}_$batchId";
      final String curriculumDocId =
          "${branch.toUpperCase()}_Sem$_currentSemester";

      final results = await Future.wait([
        // [0] timetable doc (cache-first)
        _getCached(db.collection('timetables').doc(timetableDocId)),
        // [1] curriculum doc (cache-first)
        _getCached(db.collection('curriculum').doc(curriculumDocId)),
        // [2] attendance subcollection
        _getQueryCached(_attendanceCol(user.uid)),
      ]);

      final timetableDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final currDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final attendanceSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;

      if (timetableDoc.exists) {
        _todayClasses =
            timetableDoc.data()?[_fullDayNames[_selectedDayIndex]] ??
            timetableDoc.data()?["Monday"] ??
            [];
      }

      if (currDoc.exists) {
        _myCourses = List<Map<String, dynamic>>.from(
          currDoc.data()?['courses'] ?? [],
        );
      }

      // ── 🔥 THE SMART SKELETON BUILDER FOR FIRST-TIME USERS ──
      if (attendanceSnap.docs.isEmpty && _myCourses.isNotEmpty) {
        debugPrint("First time user detected! Building smart attendance skeleton...");
        final batch = db.batch();
        
        // 1. Analyze the timetable to see which courses happen on which days
        Map<String, Set<String>> courseSchedule = {};
        if (timetableDoc.exists && timetableDoc.data() != null) {
          final ttData = timetableDoc.data()!;
          for (String day in _fullDayNames) {
            final dayClasses = (ttData[day] as List<dynamic>?) ?? [];
            for (var cls in dayClasses) {
              String subject = cls['subject'] as String? ?? '';
              String code = _extractCourseCode(subject);
              if (code.isNotEmpty) {
                courseSchedule.putIfAbsent(code, () => {}).add(day);
              }
            }
          }
        }

        Map<String, Map<String, int>> freshCache = {};
        
        // 2. Build tailored documents based on the schedule
        for (var course in _myCourses) {
          String code = course['code'] ?? 'UNK';
          if (code != 'UNK') {
            final docRef = _attendanceCol(user.uid).doc(code);
            
            // Check which days this specific course is taught
            Set<String> daysForThisCourse = courseSchedule[code] ?? {};
            
            Map<String, dynamic> initialData = {
              'attended': 0,
              'total': 0,
            };
            Map<String, int> initialCache = {};

            // Only create day fields if the class actually happens on that day
            for (String day in daysForThisCourse) {
              initialData[day] = 0;
              initialCache[day] = 0;
            }

            batch.set(docRef, initialData);
            freshCache[code] = initialCache;
          }
        }
        
        await batch.commit(); 
        debugPrint("✅ Smart skeleton profile created successfully.");
        
        setState(() {
          _timetableSyncCache = freshCache;
          _isLoading = false;
        });
        
        return; 
      }
      // ────────────────────────────────────────────────────────

      // ── Build timetable sync cache from existing attendance snapshot ──
      Map<String, Map<String, int>> syncCache = {};
      for (final doc in attendanceSnap.docs) {
        final data = doc.data();
        Map<String, int> dayMap = {};
        for (final day in _fullDayNames) {
          final raw = (data[day] ?? 0) as int;
          dayMap[day] = (raw == 1 || raw == -1) ? raw : 0;
        }
        syncCache[doc.id] = dayMap;
      }

      setState(() {
        _timetableSyncCache = syncCache;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Timetable Init Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchClassesForDay() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;
    final userDoc = await _getCached(db.collection('students').doc(user.uid));
    if (!userDoc.exists) return;

    final String branch = userDoc.data()?['branch'] ?? "CSE";
    final String rollNo = userDoc.data()?['rollNo'] ?? "2401cs80";
    final int startYear = 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24);
    final int duration =
        (rollNo.length >= 4 &&
            (rollNo.substring(2, 4) == '02' || rollNo.substring(2, 4) == '03'))
        ? 5
        : 4;
    final String batchId = "$startYear-${startYear + duration}";
    final String timetableDocId = "${branch.toUpperCase()}_$batchId";

    final timetableDoc = await _getCached(
      db.collection('timetables').doc(timetableDocId),
    );

    setState(() {
      _todayClasses = timetableDoc.exists
          ? (timetableDoc.data()?[_fullDayNames[_selectedDayIndex]] ?? [])
          : [];
      _isLoading = false;
    });
  }

  // =========================================================================
  // 🔴 2. REAL-TIME CLOUD SYNC LOGIC
  // =========================================================================
  void _handleAttendanceToggle(
    Map<String, dynamic> currentAttendanceData,
    String subjectStr,
    String time,
    String action,
  ) {
    // FIREWALL: Block Future Dates
    int currentRealDayIndex = DateTime.now().weekday - 1;
    if (currentRealDayIndex < 5 && _selectedDayIndex > currentRealDayIndex) {
      CustomTopToast.show(
        context,
        "Cannot mark attendance for future dates! 🚫",
        dangerRed,
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String code = _extractCourseCode(subjectStr);
    String dayName = _fullDayNames[_selectedDayIndex];

    int currentSyncStatus = _getTimetableSyncStatus(code);
    int newSyncStatus;

    if (action == 'present') {
      newSyncStatus = currentSyncStatus == 1 ? 0 : 1;
    } else {
      newSyncStatus = currentSyncStatus == -1 ? 0 : -1;
    }

    Map<String, dynamic> courseAtt =
        currentAttendanceData[code] ?? {'attended': 0, 'total': 0};
    int att = (courseAtt['attended'] ?? 0) as int;
    int tot = (courseAtt['total'] ?? 0) as int;

    if (action == 'present') {
      if (currentSyncStatus == 1) {
        att--;
        tot--;
        CustomTopToast.show(context, "Removed 'Present' mark.", textGrey);
      } else if (currentSyncStatus == -1) {
        att++;
        CustomTopToast.show(context, "Changed to Present! 🎉", successGreen);
      } else {
        att++;
        tot++;
        CustomTopToast.show(context, "Marked Present! 🎉", successGreen);
      }
    } else if (action == 'absent') {
      if (currentSyncStatus == -1) {
        tot--;
        CustomTopToast.show(context, "Removed 'Absent' mark.", textGrey);
      } else if (currentSyncStatus == 1) {
        att--;
        CustomTopToast.show(context, "Changed to Absent. 📉", dangerRed);
      } else {
        tot++;
        CustomTopToast.show(context, "Marked Absent. 📉", dangerRed);
      }
    }

    if (att < 0) att = 0;
    if (tot < att) tot = att;

    setState(() {
      _timetableSyncCache[code] ??= {};
      _timetableSyncCache[code]![dayName] = newSyncStatus;
    });

    _attendanceDoc(user.uid, code).set({
      'attended': att,
      'total': tot,
      dayName: newSyncStatus,
    }, SetOptions(merge: true));
  }

  // =========================================================================
  // 🔴 3. THE REAL-TIME UI BUILDER
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: backgroundGrey,
      body: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: CircleAvatar(
              radius: 140,
              backgroundColor: primaryYellow.withOpacity(0.35),
            ),
          ),
          Positioned(
            bottom: -30,
            right: -20,
            child: CircleAvatar(
              radius: 130,
              backgroundColor: primaryYellow.withOpacity(0.15),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(),
                _buildDaySelector(),
                const SizedBox(height: 16),
                if (_isLoading || user == null)
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: primaryYellow),
                    ),
                  )
                else
                  Expanded(
                    // 🔥 Stream from the new Attendance subcollection
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _attendanceCol(user.uid).snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: primaryYellow,
                            ),
                          );
                        }

                        final Map<String, dynamic> liveAttendance = {};
                        for (final doc in snapshot.data!.docs) {
                          final d = doc.data();
                          liveAttendance[doc.id] = {
                            'attended': (d['attended'] ?? 0) as int,
                            'total': (d['total'] ?? 0) as int,
                          };
                        }

                        return Column(
                          children: [
                            Expanded(
                              flex: 5,
                              child: _todayClasses.isEmpty
                                  ? Center(
                                      child: Text(
                                        "No classes scheduled today! 🎉",
                                        style: TextStyle(
                                          color: textGrey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                      ),
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: _todayClasses.length,
                                      itemBuilder: (context, index) {
                                        final cls = _todayClasses[index];
                                        return _buildClassCard(
                                          liveAttendance,
                                          cls['subject'],
                                          cls['time'],
                                          cls['room'],
                                        );
                                      },
                                    ),
                            ),
                            Expanded(
                              flex: 5,
                              child: _buildAttendanceSection(liveAttendance),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Components ---

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
              Text(
                "Weekly",
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  color: textBlack,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                "Schedule",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: primaryYellow,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Manage your attendance",
                style: TextStyle(
                  fontSize: 13,
                  color: textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const TopActionButtons(),
        ],
      ),
    );
  }

  Widget _buildDaySelector() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        itemCount: _days.length,
        itemBuilder: (context, index) {
          bool isSelected = _selectedDayIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDayIndex = index;
                _isLoading = true;
              });
              _fetchClassesForDay();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? primaryYellow : surfaceWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: primaryYellow.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Center(
                child: Text(
                  _days[index],
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isSelected ? textBlack : textGrey,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildClassCard(
    Map<String, dynamic> liveAttendance,
    String subject,
    String time,
    String room,
  ) {
    String code = _extractCourseCode(subject);
    String name = _extractCourseName(subject);

    int syncStatus = _getTimetableSyncStatus(code);
    bool isPresent = syncStatus == 1;
    bool isAbsent = syncStatus == -1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: primaryYellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  time.split(" - ")[0],
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textBlack,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Icon(Icons.arrow_downward_rounded, size: 12, color: darkYellow),
                const SizedBox(height: 2),
                Text(
                  time.split(" - ")[1],
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textBlack,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: darkYellow,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: textBlack,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 14, color: textGrey),
                    const SizedBox(width: 4),
                    Text(
                      room,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: backgroundGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _handleAttendanceToggle(
                    liveAttendance,
                    subject,
                    time,
                    'present',
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPresent ? successGreen : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: isPresent ? Colors.white : textGrey,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _handleAttendanceToggle(
                    liveAttendance,
                    subject,
                    time,
                    'absent',
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isAbsent ? dangerRed : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: isAbsent ? Colors.white : textGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSection(Map<String, dynamic> liveAttendance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFDFDFD), const Color(0xFFF5F6F8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(36),
          topRight: Radius.circular(36),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Live Attendance",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: textBlack,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: primaryYellow,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryYellow.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.edit_note_rounded,
                    size: 22,
                    color: textBlack,
                  ),
                  onPressed: () => _openEditAttendanceDialog(liveAttendance),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: _myCourses.isEmpty
                ? Center(
                    child: Text(
                      "No courses found.",
                      style: TextStyle(
                        color: textGrey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 100,
                      barTouchData: BarTouchData(
                        enabled: false,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 4,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            String val = rod.toY == 0
                                ? "0%"
                                : "${rod.toY.round()}%";
                            return BarTooltipItem(
                              val,
                              TextStyle(
                                color: textBlack,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: 25,
                            getTitlesWidget: (value, meta) {
                              if (value % 25 == 0) {
                                return Text(
                                  "${value.toInt()}",
                                  style: TextStyle(
                                    color: textGrey,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              if (value.toInt() >= 0 &&
                                  value.toInt() < _myCourses.length) {
                                String code =
                                    _myCourses[value.toInt()]['code'] ?? "UNK";
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    code,
                                    style: TextStyle(
                                      color: darkYellow,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 9,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: const Color(0xFFE2E5E9),
                          strokeWidth: 1.5,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: _myCourses.asMap().entries.map((entry) {
                        int index = entry.key;
                        String code = entry.value['code'] ?? "UNK";

                        Map<String, dynamic> courseAtt =
                            liveAttendance[code] ?? {'attended': 0, 'total': 0};
                        int att = (courseAtt['attended'] ?? 0) as int;
                        int tot = (courseAtt['total'] ?? 0) as int;
                        double percentage = tot > 0 ? (att / tot) * 100 : 0.0;

                        Color barColor = percentage >= 80
                            ? successGreen
                            : (percentage >= 70 ? primaryYellow : dangerRed);
                        if (tot == 0) barColor = textGrey.withOpacity(0.3);

                        return BarChartGroupData(
                          x: index,
                          showingTooltipIndicators: [0],
                          barRods: [
                            BarChartRodData(
                              toY: percentage,
                              color: barColor,
                              width: 16,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                topRight: Radius.circular(6),
                              ),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: 100,
                                color: surfaceWhite,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // --- Manual Edit Dialog ---
  void _openEditAttendanceDialog(Map<String, dynamic> liveAttendance) {
    if (_myCourses.isEmpty) return;
    String selectedCourseCode = _myCourses.first['code'] ?? "UNK";

    Map<String, dynamic> courseAtt =
        liveAttendance[selectedCourseCode] ?? {'attended': 0, 'total': 0};
    int localTotal = (courseAtt['total'] ?? 0) as int;
    int localAttended = (courseAtt['attended'] ?? 0) as int;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double percentage = localTotal > 0
                ? (localAttended / localTotal) * 100
                : 0.0;
            if (percentage > 100) percentage = 100;

            Color pctColor = percentage >= 80
                ? successGreen
                : (percentage >= 70 ? primaryYellow : dangerRed);
            if (localTotal == 0) pctColor = textGrey;

            return Dialog(
              backgroundColor: surfaceWhite,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Manual Edit",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: textBlack,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Update your attendance",
                              style: TextStyle(
                                fontSize: 13,
                                color: textGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: backgroundGrey,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: textBlack,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: backgroundGrey,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedCourseCode,
                          isExpanded: true,
                          dropdownColor: surfaceWhite,
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: textBlack,
                          ),
                          items: _myCourses.map((course) {
                            String code = course['code'] ?? "UNK";
                            return DropdownMenuItem<String>(
                              value: code,
                              child: Text(
                                code,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: textBlack,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedCourseCode = val;
                                Map<String, dynamic> cAtt =
                                    liveAttendance[val] ??
                                    {'attended': 0, 'total': 0};
                                localTotal = (cAtt['total'] ?? 0) as int;
                                localAttended = (cAtt['attended'] ?? 0) as int;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildCounterControl(
                            "Attended",
                            localAttended,
                            () {
                              if (localAttended > 0)
                                setDialogState(() => localAttended--);
                            },
                            () {
                              if (localAttended < localTotal)
                                setDialogState(() => localAttended++);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildCounterControl(
                            "Total",
                            localTotal,
                            () {
                              if (localTotal > 0 && localTotal > localAttended)
                                setDialogState(() => localTotal--);
                            },
                            () {
                              setDialogState(() => localTotal++);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        localTotal == 0
                            ? "--%"
                            : "${percentage.toStringAsFixed(1)}%",
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          color: pctColor,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: textBlack,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            _attendanceDoc(user.uid, selectedCourseCode).set({
                              'attended': localAttended,
                              'total': localTotal,
                            }, SetOptions(merge: true));
                          }
                          CustomTopToast.show(
                            context,
                            "Attendance Saved!",
                            successGreen,
                          );
                        },
                        child: const Text(
                          "Save Record",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCounterControl(
    String label,
    int value,
    VoidCallback onDecrement,
    VoidCallback onIncrement,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textBlack,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: primaryYellow.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onDecrement,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.remove_rounded, color: textBlack, size: 20),
                ),
              ),
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textBlack,
                ),
              ),
              InkWell(
                onTap: onIncrement,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.add_rounded, color: textBlack, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =========================================================================
// 🔴 STRICT OVERLAY TOAST: Always on top, drops from ceiling, 1.5s lifespan
// =========================================================================
class CustomTopToast {
  static void show(BuildContext context, String message, Color bgColor) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _TopToastWidget(
        message: message,
        bgColor: bgColor,
        onDismissed: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final Color bgColor;
  final VoidCallback onDismissed;

  const _TopToastWidget({
    required this.message,
    required this.bgColor,
    required this.onDismissed,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: widget.bgColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
