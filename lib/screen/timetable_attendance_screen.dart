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
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"
  ];

  List<dynamic> _todayClasses = [];
  List<Map<String, dynamic>> _myCourses = [];
  int _currentSemester = 1;

  // =========================================================================
  // 🟡 TIMETABLE SYNC LAYER
  // Separate in-memory cache for timetable_attendance UI state.
  // Key: "courseCode" → Value: Map<"Monday"/"Tuesday"/..., int (-1, 0, 1)>
  // This is populated from Firestore on init and updated on every toggle.
  // It NEVER touches the main 'attendance' collection.
  // =========================================================================
  Map<String, Map<String, int>> _timetableSyncCache = {};

  @override
  void initState() {
    super.initState();
    if (_selectedDayIndex > 4) _selectedDayIndex = 0;
    _initializeCoreDataAndCheckReset();
  }

  // =========================================================================
  // 🟡 HELPER: Get the current UI status for a course on the selected day
  // Returns: 1 (Present), -1 (Absent), 0 (Not Marked)
  // =========================================================================
  int _getTimetableSyncStatus(String courseCode) {
    String dayName = _fullDayNames[_selectedDayIndex];
    return _timetableSyncCache[courseCode]?[dayName] ?? 0;
  }

  // =========================================================================
  // 🟡 HELPER: Write a single status update to the timetable_attendance
  // collection. This is completely isolated from the main attendance data.
  // Path: timetable_attendance/{uid}/{courseCode} → {dayName: status}
  // =========================================================================
  Future<void> _writeTimetableSyncStatus(
      String uid, String courseCode, String dayName, int status) async {
    // Clamp to valid values only: -1, 0, 1
    assert(status == -1 || status == 0 || status == 1,
        "Invalid timetable sync status: $status");

    await FirebaseFirestore.instance
        .collection('timetable_attendance')
        .doc(uid)
        .collection('courses')
        .doc(courseCode)
        .set({dayName: status}, SetOptions(merge: true));
  }

  // =========================================================================
  // 🟡 LOAD: Read the full timetable_attendance doc for this user into cache.
  // Called once during init (after weekly reset check).
  // =========================================================================
  Future<void> _loadTimetableSyncCache(String uid) async {
    final coursesSnap = await FirebaseFirestore.instance
        .collection('timetable_attendance')
        .doc(uid)
        .collection('courses')
        .get();

    Map<String, Map<String, int>> cache = {};
    for (final doc in coursesSnap.docs) {
      final data = doc.data();
      Map<String, int> dayMap = {};
      for (final day in _fullDayNames) {
        int raw = (data[day] ?? 0) as int;
        // Sanitize: only allow -1, 0, 1
        dayMap[day] = (raw == 1 || raw == -1) ? raw : 0;
      }
      cache[doc.id] = dayMap;
    }

    if (mounted) setState(() => _timetableSyncCache = cache);
  }

  // =========================================================================
  // 🟡 WEEKLY RESET (Timetable Sync ONLY)
  // Runs every Sunday midnight → sets all course/day values to 0.
  // Does NOT touch the main 'attendance' field on the student document.
  // =========================================================================
  Future<void> _checkAndResetTimetableSyncIfNeeded(String uid) async {
    final tsDocRef = FirebaseFirestore.instance
        .collection('timetable_attendance')
        .doc(uid);
    final tsDoc = await tsDocRef.get();

    DateTime now = DateTime.now();
    int daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
    DateTime lastSundayMidnight = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: daysSinceSunday));

    Timestamp? lastResetTs = tsDoc.data()?['last_reset_timestamp'];
    DateTime lastReset =
        lastResetTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

    if (lastReset.isBefore(lastSundayMidnight)) {
      // New week detected → wipe all course/day statuses to 0
      final coursesSnap = await tsDocRef.collection('courses').get();

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      Map<String, int> resetDayMap = {
        for (var d in _fullDayNames) d: 0,
      };
      for (final doc in coursesSnap.docs) {
        batch.set(doc.reference, resetDayMap, SetOptions(merge: false));
      }

      // Update the reset timestamp on the parent document
      batch.set(tsDocRef, {
        'last_reset_timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      // Clear local cache immediately
      if (mounted) setState(() => _timetableSyncCache = {});

      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          CustomTopToast.show(
              context, "Timetable sync reset for the new week! 📅", primaryYellow);
        });
      }
    }
  }

  // =========================================================================
  // 🔴 1. INITIALIZATION & STRICT WEEKLY RESET (Main Attendance)
  // =========================================================================
  int _calculateCurrentSemester(String roll) {
    if (roll.length < 4) return 1;
    int joinYear = 2000 + (int.tryParse(roll.substring(0, 2)) ?? 24);
    DateTime joinDate = DateTime(joinYear, 7, 1);
    DateTime now = DateTime.now();
    int monthsElapsed =
        (now.year - joinDate.year) * 12 + now.month - joinDate.month;
    return monthsElapsed < 0 ? 1 : (monthsElapsed / 6).floor() + 1;
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

      final userDocRef =
          FirebaseFirestore.instance.collection('students').doc(user.uid);
      final userDoc = await userDocRef.get();

      if (userDoc.exists) {
        String branch = userDoc.data()?['branch'] ?? "CSE";
        String rollNo = userDoc.data()?['rollNo'] ?? "2401cs80";
        _currentSemester = _calculateCurrentSemester(rollNo);

        // --- MAIN ATTENDANCE WEEKLY RESET (unchanged) ---
        DateTime now = DateTime.now();
        int daysSinceSunday = now.weekday == 7 ? 0 : now.weekday;
        DateTime lastSundayMidnight = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: daysSinceSunday));

        Timestamp? lastResetTs = userDoc.data()?['last_reset_timestamp'];
        DateTime lastReset =
            lastResetTs?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);

        if (lastReset.isBefore(lastSundayMidnight)) {
          Map<String, dynamic> rawAtt =
              userDoc.data()?['attendance'] ?? {};
          Map<String, Map<String, int>> resetStats = {};
          rawAtt.forEach((key, _) {
            resetStats[key] = {'attended': 0, 'total': 0};
          });

          await userDocRef.update({
            'attendance': resetStats,
            'last_reset_timestamp': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            Future.delayed(const Duration(milliseconds: 500), () {
              CustomTopToast.show(
                  context, "Attendance reset for the new week! 📅", primaryYellow);
            });
          }
        }

        // --- 🟡 TIMETABLE SYNC: Weekly reset check (independent) ---
        await _checkAndResetTimetableSyncIfNeeded(user.uid);

        // --- FETCH STATIC DATA (Timetable & Courses) ---
        int startYear = 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24);
        int duration = (rollNo.length >= 4 &&
                (rollNo.substring(2, 4) == '02' ||
                    rollNo.substring(2, 4) == '03'))
            ? 5
            : 4;
        String batch = "$startYear-${startYear + duration}";

        String timetableDocId = "${branch.toUpperCase()}_$batch";
        final timetableDoc = await FirebaseFirestore.instance
            .collection('timetables')
            .doc(timetableDocId)
            .get();
        if (timetableDoc.exists) {
          _todayClasses = timetableDoc.data()?[_fullDayNames[_selectedDayIndex]] ??
              timetableDoc.data()?["Monday"] ??
              [];
        }

        String curriculumDocId =
            "${branch.toUpperCase()}_Sem$_currentSemester";
        final currDoc = await FirebaseFirestore.instance
            .collection('curriculum')
            .doc(curriculumDocId)
            .get();
        if (currDoc.exists) {
          _myCourses = List<Map<String, dynamic>>.from(
              currDoc.data()?['courses'] ?? []);
        }

        // --- 🟡 TIMETABLE SYNC: Load cache into memory ---
        await _loadTimetableSyncCache(user.uid);

        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Init Error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchClassesForDay() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('students')
        .doc(user.uid)
        .get();
    if (!userDoc.exists) return;

    String branch = userDoc.data()?['branch'] ?? "CSE";
    String rollNo = userDoc.data()?['rollNo'] ?? "2401cs80";
    int startYear = 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24);
    int duration = (rollNo.length >= 4 &&
            (rollNo.substring(2, 4) == '02' ||
                rollNo.substring(2, 4) == '03'))
        ? 5
        : 4;
    String batch = "$startYear-${startYear + duration}";

    String timetableDocId = "${branch.toUpperCase()}_$batch";
    final timetableDoc = await FirebaseFirestore.instance
        .collection('timetables')
        .doc(timetableDocId)
        .get();

    setState(() {
      if (timetableDoc.exists) {
        _todayClasses =
            timetableDoc.data()?[_fullDayNames[_selectedDayIndex]] ?? [];
      } else {
        _todayClasses = [];
      }
      _isLoading = false;
    });
  }

  // =========================================================================
  // 🔴 2. FUTURE FIREWALL & REAL-TIME CLOUD SYNC LOGIC
  // Now also syncs timetable_attendance as a separate, non-interfering layer.
  // =========================================================================
  void _handleAttendanceToggle(Map<String, dynamic> currentAttendanceData,
      String subjectStr, String time, String action) {
    // FIREWALL: Block Future Dates
    int currentRealDayIndex = DateTime.now().weekday - 1;
    if (currentRealDayIndex < 5 && _selectedDayIndex > currentRealDayIndex) {
      CustomTopToast.show(
          context, "Cannot mark attendance for future dates! 🚫", dangerRed);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String code = _extractCourseCode(subjectStr);
    String dayName = _fullDayNames[_selectedDayIndex];

    // --- Read current timetable sync status from local cache ---
    int currentSyncStatus = _getTimetableSyncStatus(code);

    // --- Determine new timetable sync status ---
    int newSyncStatus;
    if (action == 'present') {
      newSyncStatus = currentSyncStatus == 1 ? 0 : 1;
    } else {
      // action == 'absent'
      newSyncStatus = currentSyncStatus == -1 ? 0 : -1;
    }

    // --- 1. UPDATE MAIN ATTENDANCE DATABASE (original logic, unchanged) ---
    Map<String, dynamic> courseAtt =
        currentAttendanceData[code] ?? {'attended': 0, 'total': 0};
    int att = (courseAtt['attended'] ?? 0) as int;
    int tot = (courseAtt['total'] ?? 0) as int;

    if (action == 'present') {
      if (currentSyncStatus == 1) {
        // Was present → undo
        att--;
        tot--;
        CustomTopToast.show(context, "Removed 'Present' mark.", textGrey);
      } else if (currentSyncStatus == -1) {
        // Was absent → switch to present
        att++;
        CustomTopToast.show(context, "Changed to Present! 🎉", successGreen);
      } else {
        // Was unmarked → mark present
        att++;
        tot++;
        CustomTopToast.show(context, "Marked Present! 🎉", successGreen);
      }
    } else if (action == 'absent') {
      if (currentSyncStatus == -1) {
        // Was absent → undo
        tot--;
        CustomTopToast.show(context, "Removed 'Absent' mark.", textGrey);
      } else if (currentSyncStatus == 1) {
        // Was present → switch to absent
        att--;
        CustomTopToast.show(context, "Changed to Absent. 📉", dangerRed);
      } else {
        // Was unmarked → mark absent
        tot++;
        CustomTopToast.show(context, "Marked Absent. 📉", dangerRed);
      }
    }

    // Safety Bounds
    if (att < 0) att = 0;
    if (tot < att) tot = att;

    // Push main attendance update
    FirebaseFirestore.instance
        .collection('students')
        .doc(user.uid)
        .update({
      'attendance.$code': {'attended': att, 'total': tot},
      'last_updated_timestamp': FieldValue.serverTimestamp(),
    });

    // --- 2. UPDATE TIMETABLE SYNC LAYER (separate, isolated write) ---
    // Update local cache first for instant UI response
    setState(() {
      _timetableSyncCache[code] ??= {};
      _timetableSyncCache[code]![dayName] = newSyncStatus;
    });

    // Persist to Firestore timetable_attendance (fire-and-forget, non-blocking)
    _writeTimetableSyncStatus(user.uid, code, dayName, newSyncStatus);
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
                  backgroundColor: primaryYellow.withOpacity(0.35))),
          Positioned(
              bottom: -30,
              right: -20,
              child: CircleAvatar(
                  radius: 130,
                  backgroundColor: primaryYellow.withOpacity(0.15))),
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
                          child: CircularProgressIndicator(
                              color: primaryYellow)))
                else
                  Expanded(
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('students')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Center(
                              child: CircularProgressIndicator(
                                  color: primaryYellow));
                        }

                        Map<String, dynamic> liveAttendance =
                            snapshot.data?.get('attendance') ?? {};

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
                                              fontWeight: FontWeight.bold)))
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      physics:
                                          const BouncingScrollPhysics(),
                                      itemCount: _todayClasses.length,
                                      itemBuilder: (context, index) {
                                        final cls = _todayClasses[index];
                                        return _buildClassCard(
                                            liveAttendance,
                                            cls['subject'],
                                            cls['time'],
                                            cls['room']);
                                      },
                                    ),
                            ),
                            Expanded(
                                flex: 5,
                                child: _buildAttendanceSection(
                                    liveAttendance)),
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
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Weekly",
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      color: textBlack)),
              Text("Schedule",
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: primaryYellow)),
            ],
          ),
          const TopActionButtons(unreadCount: 2),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                  color: isSelected ? primaryYellow : surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: primaryYellow.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 4))
                        ]
                      : []),
              child: Center(
                  child: Text(_days[index],
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: isSelected ? textBlack : textGrey,
                          fontSize: 14))),
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // 🟡 TIMETABLE SYNC: _buildClassCard reads from _timetableSyncCache
  // instead of _sessionMarkedStatus. The UI reflects:
  //   1  → present button highlighted green
  //  -1  → absent button highlighted red
  //   0  → both buttons neutral
  // =========================================================================
  Widget _buildClassCard(Map<String, dynamic> liveAttendance, String subject,
      String time, String room) {
    String code = _extractCourseCode(subject);
    String name = _extractCourseName(subject);

    // 🟡 Read from timetable sync cache (not session map)
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
                offset: const Offset(0, 4))
          ]),
      child: Row(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
                color: primaryYellow.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                Text(time.split(" - ")[0],
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textBlack,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Icon(Icons.arrow_downward_rounded,
                    size: 12, color: darkYellow),
                const SizedBox(height: 2),
                Text(time.split(" - ")[1],
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textBlack,
                        fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: darkYellow,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textBlack,
                        height: 1.1)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded,
                        size: 14, color: textGrey),
                    const SizedBox(width: 4),
                    Text(room,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textGrey)),
                  ],
                ),
              ],
            ),
          ),
          // 🟡 Buttons driven by timetable sync status (-1, 0, 1)
          Container(
            padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
                color: backgroundGrey,
                borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _handleAttendanceToggle(
                      liveAttendance, subject, time, 'present'),
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: isPresent
                              ? successGreen
                              : Colors.transparent,
                          shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded,
                          size: 18,
                          color: isPresent ? Colors.white : textGrey)),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _handleAttendanceToggle(
                      liveAttendance, subject, time, 'absent'),
                  child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color:
                              isAbsent ? dangerRed : Colors.transparent,
                          shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded,
                          size: 18,
                          color: isAbsent ? Colors.white : textGrey)),
                ),
              ],
            ),
          )
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
            colors: [
              const Color(0xFFFDFDFD),
              const Color(0xFFF5F6F8)
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(36), topRight: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, -4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Live Attendance",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: textBlack)),
              Container(
                decoration: BoxDecoration(
                    color: primaryYellow,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: primaryYellow.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4))
                    ]),
                child: IconButton(
                    icon: Icon(Icons.edit_note_rounded,
                        size: 22, color: textBlack),
                    onPressed: () =>
                        _openEditAttendanceDialog(liveAttendance)),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: _myCourses.isEmpty
                ? Center(
                    child: Text("No courses found.",
                        style: TextStyle(
                            color: textGrey,
                            fontWeight: FontWeight.bold)))
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 100,
                      barTouchData: BarTouchData(
                        enabled: false,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) =>
                              Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 4,
                          getTooltipItem:
                              (group, groupIndex, rod, rodIndex) {
                            String val = rod.toY == 0
                                ? "0%"
                                : "${rod.toY.round()}%";
                            return BarTooltipItem(
                                val,
                                TextStyle(
                                    color: textBlack,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11));
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 36,
                                interval: 25,
                                getTitlesWidget: (value, meta) {
                                  if (value % 25 == 0) {
                                    return Text("${value.toInt()}",
                                        style: TextStyle(
                                            color: textGrey,
                                            fontSize: 11,
                                            fontWeight:
                                                FontWeight.w800));
                                  }
                                  return const SizedBox.shrink();
                                })),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget:
                                    (double value, TitleMeta meta) {
                                  if (value.toInt() >= 0 &&
                                      value.toInt() <
                                          _myCourses.length) {
                                    String code =
                                        _myCourses[value.toInt()]
                                                ['code'] ??
                                            "UNK";
                                    return Padding(
                                        padding: const EdgeInsets.only(
                                            top: 8.0),
                                        child: Text(code,
                                            style: TextStyle(
                                                color: darkYellow,
                                                fontWeight:
                                                    FontWeight.w900,
                                                fontSize: 9)));
                                  }
                                  return const SizedBox.shrink();
                                })),
                      ),
                      gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 25,
                          getDrawingHorizontalLine: (value) => FlLine(
                              color: const Color(0xFFE2E5E9),
                              strokeWidth: 1.5)),
                      borderData: FlBorderData(show: false),
                      barGroups: _myCourses.asMap().entries.map((entry) {
                        int index = entry.key;
                        String code = entry.value['code'] ?? "UNK";

                        Map<String, dynamic> courseAtt =
                            liveAttendance[code] ??
                                {'attended': 0, 'total': 0};
                        int att =
                            (courseAtt['attended'] ?? 0) as int;
                        int tot = (courseAtt['total'] ?? 0) as int;
                        double percentage =
                            tot > 0 ? (att / tot) * 100 : 0.0;

                        Color barColor = percentage >= 80
                            ? successGreen
                            : (percentage >= 70
                                ? primaryYellow
                                : dangerRed);
                        if (tot == 0)
                          barColor = textGrey.withOpacity(0.3);

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
                                      topRight: Radius.circular(6)),
                                  backDrawRodData:
                                      BackgroundBarChartRodData(
                                          show: true,
                                          toY: 100,
                                          color: surfaceWhite))
                            ]);
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
        return StatefulBuilder(builder: (context, setDialogState) {
          double percentage =
              localTotal > 0 ? (localAttended / localTotal) * 100 : 0.0;
          if (percentage > 100) percentage = 100;

          Color pctColor = percentage >= 80
              ? successGreen
              : (percentage >= 70 ? primaryYellow : dangerRed);
          if (localTotal == 0) pctColor = textGrey;

          return Dialog(
            backgroundColor: surfaceWhite,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                          Text("Manual Edit",
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: textBlack)),
                          const SizedBox(height: 4),
                          Text("Update your attendance",
                              style: TextStyle(
                                  fontSize: 13,
                                  color: textGrey,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: backgroundGrey, shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              size: 20, color: textBlack),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                        color: backgroundGrey,
                        borderRadius: BorderRadius.circular(16)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCourseCode,
                        isExpanded: true,
                        dropdownColor: surfaceWhite,
                        icon: Icon(Icons.keyboard_arrow_down_rounded,
                            color: textBlack),
                        items: _myCourses.map((course) {
                          String code = course['code'] ?? "UNK";
                          return DropdownMenuItem<String>(
                              value: code,
                              child: Text(code,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: textBlack)));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedCourseCode = val;
                              Map<String, dynamic> cAtt =
                                  liveAttendance[val] ??
                                      {'attended': 0, 'total': 0};
                              localTotal = (cAtt['total'] ?? 0) as int;
                              localAttended =
                                  (cAtt['attended'] ?? 0) as int;
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
                              })),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildCounterControl(
                              "Total",
                              localTotal,
                              () {
                                if (localTotal > 0 &&
                                    localTotal > localAttended)
                                  setDialogState(() => localTotal--);
                              },
                              () {
                                setDialogState(() => localTotal++);
                              })),
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
                              letterSpacing: -1))),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: textBlack,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      onPressed: () {
                        Navigator.pop(context);
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          // Only writes to main attendance (manual edit does NOT touch timetable sync)
                          FirebaseFirestore.instance
                              .collection('students')
                              .doc(user.uid)
                              .update({
                            'attendance.$selectedCourseCode': {
                              'attended': localAttended,
                              'total': localTotal
                            },
                            'last_updated_timestamp':
                                FieldValue.serverTimestamp(),
                          });
                        }
                        CustomTopToast.show(
                            context, "Attendance Saved!", successGreen);
                      },
                      child: const Text("Save Record",
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  )
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildCounterControl(String label, int value,
      VoidCallback onDecrement, VoidCallback onIncrement) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: TextStyle(
                color: textBlack,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
              color: primaryYellow.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                  onTap: onDecrement,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.remove_rounded,
                          color: textBlack, size: 20))),
              Text(value.toString(),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: textBlack)),
              InkWell(
                  onTap: onIncrement,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.add_rounded,
                          color: textBlack, size: 20))),
            ],
          ),
        )
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

  const _TopToastWidget(
      {required this.message,
      required this.bgColor,
      required this.onDismissed});

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
        vsync: this, duration: const Duration(milliseconds: 350));

    _offsetAnimation =
        Tween<Offset>(begin: const Offset(0, -1.0), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeIn));

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
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: BoxDecoration(
                color: widget.bgColor,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Text(
                widget.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}