// ── COLLECTION OVERVIEW ──────────────────────────────────────
//   students/{uid}                          main student doc
//   students/{uid}/pastSemesters/{sem}      one doc per finished semester
//   students/{uid}/smart_reminders/{id}     unified reminder mirror
//   students/{uid}/library/{id}             library books
//   students/{uid}/planner/{id}             planner tasks
//   students/{uid}/focus_stats/summary      Pomodoro stats
//   students/{uid}/meta/{admin_prefs}       dismissed broadcast reminders
//   admin_reminders/{id}                    broadcast to all users
//   timetables/{branch_batch}               weekly schedule
//   curriculum/{branch_semN}                course list per semester
//   sem_credits/{branch}                    credits per semester (flat: "Semester 1": 22)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────
// TYPED EXCEPTION
// ─────────────────────────────────────────────────────────────
class FirebaseServiceException implements Exception {
  final String message;
  final String code;
  const FirebaseServiceException(this.message, {this.code = 'unknown'});
  @override
  String toString() => 'FirebaseServiceException[$code]: $message';
}

// ─────────────────────────────────────────────────────────────
// SERVICE  (singleton)
// ─────────────────────────────────────────────────────────────
class FirebaseService {
  static final FirebaseService instance = FirebaseService._();
  FirebaseService._();

  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── Auth ──────────────────────────────────────────────────────
  User?   get currentUser => _auth.currentUser;

  String get uid {
    final u = _auth.currentUser?.uid;
    if (u == null){ throw const FirebaseServiceException(
        'No authenticated user.', code: 'no_user');}
    return u;
  }

  // ── Document / collection refs ────────────────────────────────
  DocumentReference<Map<String, dynamic>> _studentDoc(String uid) =>
      _db.collection('students').doc(uid);

  CollectionReference<Map<String, dynamic>> _pastSemsCol(String uid) =>
      _studentDoc(uid).collection('pastSemesters');

  DocumentReference<Map<String, dynamic>> _pastSemDoc(String uid, int sem) =>
      _pastSemsCol(uid).doc('Semester $sem');

  CollectionReference<Map<String, dynamic>> _remindersCol(String uid) =>
      _studentDoc(uid).collection('reminders');

  CollectionReference<Map<String, dynamic>> _libraryCol(String uid) =>
      _studentDoc(uid).collection('library');

  CollectionReference<Map<String, dynamic>> _plannerCol(String uid) =>
      _studentDoc(uid).collection('planner');

  CollectionReference<Map<String, dynamic>> _focusCol(String uid) =>
      _studentDoc(uid).collection('focus_stats');

  DocumentReference<Map<String, dynamic>> _dismissedCol(String uid) =>
      _studentDoc(uid).collection('meta').doc('admin_prefs');

  // ── smart_reminders subcollection ────────────────────────────
  // Schema of each document:
  //   id          — planner task id  OR  'lib_{bookId}'
  //   source      — 'planner' | 'library'
  //   title       — display title
  //   dateTime    — Timestamp (task due / book due)
  //   description — optional String
  //   isRead      — bool  (toggled by left-swipe in SmartReminderScreen)
  //   createdAt   — server timestamp  (used for Today / This Week / Earlier grouping)
  //
  // Lifecycle:
  //   • Created/updated when a planner task with isSmartReminder=true is saved,
  //     or when a library book is added.
  //   • Deleting a task or returning a book does NOT touch this collection.
  //   • Only SmartReminderScreen's right-swipe deletes the document.
  CollectionReference<Map<String, dynamic>> _smartRemindersCol(String uid) =>
      _studentDoc(uid).collection('smart_reminders');

  // ── Server-first fetch helper ─────────────────────────────────
  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchDoc(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } catch (_) {
      return ref.get(const GetOptions(source: Source.cache));
    }
  }

  // ─────────────────────────────────────────────────────────────
  // STUDENT DOCUMENT
  // ─────────────────────────────────────────────────────────────

  Future<DocumentSnapshot<Map<String, dynamic>>> getStudentDoc(
      String uid) async {
    try {
      return await _fetchDoc(_studentDoc(uid));
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to load student data: $e', code: 'student_fetch');
    }
  }

  Future<void> updateStudentDoc(String uid,
      Map<String, dynamic> data) async {
    try {
      await _studentDoc(uid).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to update student doc: $e', code: 'student_update');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // FIRST-OPEN INITIALISATION
  // ─────────────────────────────────────────────────────────────
  Future<int> initializeFirstOpen(String uid, {
    required String rollNo,
    required String branch,
  }) async {
    final currentSem = semesterFromRollNo(rollNo);

    if (currentSem > 1) {
      double runningCP = 0, runningC = 0;

      for (int sem = 1; sem < currentSem; sem++) {
        try {
          final existing = await _pastSemDoc(uid, sem)
              .get(const GetOptions(source: Source.server));
          if (existing.exists) {
            final d = existing.data()!;
            final existSpi = ((d['spi'] ?? 8.0) as num).toDouble();
            final existCr  = ((d['credit'] ?? 21) as num).toInt();
            runningCP += existSpi * existCr;
            runningC  += existCr;
            continue;
          }
        } catch (_) {}

        final credit = await _creditForSemFromCurriculum(
            branch: branch, semester: sem);

        const defaultSpi = 8.0;
        runningCP += defaultSpi * credit;
        runningC  += credit;
        final cpi = runningC > 0 ? runningCP / runningC : defaultSpi;

        await _pastSemDoc(uid, sem).set({
          'semester': sem,
          'spi':      defaultSpi,
          'spi ':     defaultSpi,
          'cpi':      double.parse(cpi.toStringAsFixed(2)),
          'credit':   credit,
          'lockedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    try {
      await _studentDoc(uid).update({
        'currentSemester': currentSem,
        'lastSemRollDate': Timestamp.fromDate(DateTime(2000)),
      });
    } catch (_) {
      await _studentDoc(uid).set({
        'currentSemester': currentSem,
        'lastSemRollDate': Timestamp.fromDate(DateTime(2000)),
      }, SetOptions(merge: true));
    }

    return currentSem;
  }

  Future<void> updateCurrentSemester(String uid, int sem) async {
    await _db.collection('students').doc(uid).update({
      'currentSemester': sem,
    });
  }

  static int semesterFromRollNo(String rollNo) {
    if (rollNo.length < 2) return 1;
    final startYear = 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24);
    final joinDate  = DateTime(startYear, 7, 1);
    final now       = DateTime.now();
    final months    = (now.year - joinDate.year) * 12
                    + now.month - joinDate.month;
    if (months < 0) return 1;
    return (months / 6).floor() + 1;
  }

  Future<int> _creditForSemFromCurriculum({
    required String branch,
    required int    semester,
  }) async {
    try {
      final creditsDoc = await getSemCredits(branch);
      final cr = creditForSem(creditsDoc, semester);
      if (cr > 0) return cr;
    } catch (_) {}

    try {
      final snap = await _db
          .collection('curriculum')
          .doc('${branch.toUpperCase()}_Sem$semester')
          .get(const GetOptions(source: Source.serverAndCache));
      if (snap.exists) {
        final courses = (snap.data()?['courses'] as List?) ?? [];
        if (courses.isNotEmpty) {
          final total = courses.fold<double>(
            0, (sum, c) => sum + ((c['credit'] ?? 0) as num).toDouble());
          if (total > 0) return total.toInt();
        }
      }
    } catch (_) {}

    return 21;
  }

  // ─────────────────────────────────────────────────────────────
  // PAST SEMESTERS SUBCOLLECTION
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPastSemesters(String uid) async {
    try {
      final snap = await _pastSemsCol(uid)
          .orderBy('semester')
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.docs.map((d) => d.data()).toList();
    } catch (_) {
      try {
        final snap = await _pastSemsCol(uid)
            .orderBy('semester')
            .get(const GetOptions(source: Source.server));
        return snap.docs.map((d) => d.data()).toList();
      } catch (e) {
        throw FirebaseServiceException(
            'Failed to load past semesters: $e', code: 'past_sem_fetch');
      }
    }
  }

  Future<void> archiveSemester(String uid, {
    required int    semester,
    required double spi,
    required double cpi,
    required int    credit,
  }) async {
    final ref = _pastSemDoc(uid, semester);
    try {
      final existing = await ref.get(const GetOptions(source: Source.server));
      if (existing.exists) {
        debugPrint('Semester $semester already archived — skipping.');
        return;
      }
      await ref.set({
        'semester': semester,
        'spi':      spi,
        'spi ':     spi,
        'cpi':      cpi,
        'credit':   credit,
        'lockedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to archive semester $semester: $e',
          code: 'past_sem_archive');
    }
  }

  Future<void> updatePastSemesterSpi(String uid, {
    required int    semester,
    required double spi,
    required double cpi,
  }) async {
    try {
      await _pastSemDoc(uid, semester).update({
        'spi':  spi,
        'spi ': spi,
        'cpi':  cpi,
      });
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to update SGPA for semester $semester: $e',
          code: 'past_sem_update');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SEMESTER ROLL-OVER
  // ─────────────────────────────────────────────────────────────

  Future<int> checkAndRollSemester(String uid, {
    required int    currentSem,
    required double spiForCurrentSem,
    required double cpiForCurrentSem,
    required int    creditForCurrentSem,
  }) async {
    final now = DateTime.now();

    DateTime _boundaryForSem(int sem, int startYear) {
      if (sem.isOdd) {
        final semYear = startYear + (sem - 1) ~/ 2;
        return DateTime(semYear + 1, 1, 1);
      } else {
        final semYear = startYear + sem ~/ 2;
        return DateTime(semYear, 6, 1);
      }
    }

    try {
      final snap = await getStudentDoc(uid);
      final d    = snap.data() ?? {};

      final rollNo    = (d['rollNo']   ?? '') as String;
      final startYear = rollNo.length >= 2
          ? 2000 + (int.tryParse(rollNo.substring(0, 2)) ?? 24)
          : 2024;

      final boundary = _boundaryForSem(currentSem, startYear);

      if (now.isBefore(boundary)) return currentSem;

      final lastRollRaw = d['lastSemRollDate'];
      if (lastRollRaw != null) {
        final lastRoll = (lastRollRaw as Timestamp).toDate();
        if (!lastRoll.isBefore(boundary)) return currentSem;
      }

      debugPrint(
          'Rolling semester $currentSem → ${currentSem + 1}  '
          '(boundary was ${boundary.toIso8601String()})');

      await archiveSemester(uid,
        semester: currentSem,
        spi:      spiForCurrentSem,
        cpi:      cpiForCurrentSem,
        credit:   creditForCurrentSem,
      );

      await _studentDoc(uid).update({
        'currentSemester': currentSem + 1,
        'lastSemRollDate': FieldValue.serverTimestamp(),
      });

      return currentSem + 1;

    } catch (e) {
      debugPrint('Semester rollover error: $e');
      return currentSem;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CGPA HELPERS
  // ─────────────────────────────────────────────────────────────

  static double computeCgpaFromList(List<Map<String, dynamic>> past) {
    double sumCP = 0, sumC = 0;
    for (final s in past) {
      final spi    = ((s['spi'] ?? s['spi '] ?? 0.0) as num).toDouble();
      final credit = ((s['credit'] ?? 21) as num).toInt();
      sumCP += spi * credit;
      sumC  += credit;
    }
    return sumC > 0 ? sumCP / sumC : 0.0;
  }

  static double computeCgpa(Map<String, dynamic> studentData) {
    final rawPast = ((studentData['pastSemesters'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    if (rawPast.isEmpty) return 0.0;
    final sorted = List<Map<String, dynamic>>.from(rawPast)
      ..sort((a, b) =>
          ((a['semester'] ?? 0) as int).compareTo((b['semester'] ?? 0) as int));
    for (final row in sorted.reversed) {
      final c = row['cpi'];
      if (c != null && (c as num).toDouble() > 0) return (c as num).toDouble();
    }
    return 0.0;
  }

  // ─────────────────────────────────────────────────────────────
  // TIMETABLE
  // ─────────────────────────────────────────────────────────────

  Future<DocumentSnapshot<Map<String, dynamic>>?> getTimetableDoc({
    required String branch,
    required int semester,
  }) async {
    final id = '${branch.toUpperCase()}_Sem$semester';
    try {
      final doc = await _db
          .collection('timetables')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (doc.exists) return doc;
    } catch (_) {
      try {
        final doc = await _db
            .collection('timetables')
            .doc(id)
            .get(const GetOptions(source: Source.cache));
        if (doc.exists) return doc;
      } catch (_) {}
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────
  // CURRICULUM
  // ─────────────────────────────────────────────────────────────

  Future<DocumentSnapshot<Map<String, dynamic>>?> getCurriculumDoc({
    required String branch,
    required int    semester,
  }) async {
    final id = '${branch.toUpperCase()}_Sem$semester';
    try {
      final snap = await _fetchDoc(_db.collection('curriculum').doc(id));
      return snap.exists ? snap : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getSemCredits(String branch) async {
    try {
      final snap = await _db
          .collection('sem_credits')
          .doc(branch.toUpperCase())
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.data() ?? {};
    } catch (_) {
      return {};
    }
  }

  static int creditForSem(Map<String, dynamic> creditsDoc, int sem) {
    final flat = creditsDoc['Semester $sem'];
    if (flat != null) return (flat as num).toInt();
    final legacy = creditsDoc['sem_$sem'];
    if (legacy != null) return (legacy as num).toInt();
    return 21;
  }

  // ─────────────────────────────────────────────────────────────
  // ATTENDANCE
  // ─────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _attCoursesCol(String uid) =>
      _db.collection('timetable_attendance').doc(uid).collection('courses');

  Future<Map<String, Map<String, int>>> getAttendance(String uid) async {
    try {
      final snap = await _attCoursesCol(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      final result = <String, Map<String, int>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        result[doc.id] = {
          'attended': ((d['attended'] ?? 0) as num).toInt(),
          'total':    ((d['total']    ?? 0) as num).toInt(),
        };
      }
      return result;
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to load attendance: $e', code: 'attendance_fetch');
    }
  }

  Future<void> updateCourseAttendance(
      String uid, String courseCode, int attended, int total) async {
    try {
      await _attCoursesCol(uid).doc(courseCode).set({
        'attended': attended,
        'total':    total,
      }, SetOptions(merge: true));
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to update attendance: $e', code: 'attendance_update');
    }
  }

  static double computeAverageAttendance(
      Map<String, Map<String, int>> attendance) {
    int totalAtt = 0, totalCls = 0;
    for (final v in attendance.values) {
      totalAtt += v['attended'] ?? 0;
      totalCls += v['total']    ?? 0;
    }
    return totalCls > 0 ? totalAtt / totalCls * 100 : 0.0;
  }

  // ─────────────────────────────────────────────────────────────
  // REMINDERS (legacy subcollection — kept for compatibility)
  // ─────────────────────────────────────────────────────────────

  Stream<int> unreadCountStream(String uid) =>
      _remindersCol(uid)
          .where('isRead', isEqualTo: false)
          .snapshots()
          .map((s) => s.size);

  Stream<QuerySnapshot<Map<String, dynamic>>> remindersStream(String uid) =>
      _remindersCol(uid).orderBy('dateTime').snapshots();

  Future<void> markReminderRead(String uid, String id) async =>
      _remindersCol(uid).doc(id).update({'isRead': true}).catchError((_) {});

  Future<void> deleteReminder(String uid, String id) async =>
      _remindersCol(uid).doc(id).delete().catchError((_) {});

  // ─────────────────────────────────────────────────────────────
  // SMART REMINDERS subcollection
  //
  // Document id convention:
  //   planner task  →  same as planner doc id
  //   library book  →  'lib_{bookId}'
  //
  // Fields:
  //   source      'planner' | 'library'
  //   title       display title
  //   dateTime    Timestamp — task due / book due date
  //   description optional String (planner only)
  //   isRead      bool — toggled by SmartReminderScreen left-swipe
  //   createdAt   server timestamp — used for Today/This Week/Earlier grouping
  //
  // Rules:
  //   • upsertPlannerReminder — called on task create/edit
  //   • upsertLibraryReminder — called on book issue
  //   • Deleting a task OR returning a book does NOT touch smart_reminders
  //   • Only SmartReminderScreen right-swipe deletes the doc
  // ─────────────────────────────────────────────────────────────

  /// Stream of all smart reminders ordered by creation time (newest first).
  /// SmartReminderScreen uses this as its single source of truth.
  Stream<QuerySnapshot<Map<String, dynamic>>> smartRemindersStream(String uid) =>
      _smartRemindersCol(uid)
          .orderBy('createdAt', descending: true)
          .snapshots();

  /// Unread count for the bell badge — reads from smart_reminders only.
  Stream<int> smartReminderUnreadCountStream(String uid) =>
      _smartRemindersCol(uid)
          .where('isRead', isEqualTo: false)
          .snapshots()
          .map((s) => s.size);

  /// Upsert a smart reminder for a planner task.
  /// Safe to call on every create/edit — preserves existing [isRead] state.
  Future<void> upsertPlannerReminder(
    String uid, {
    required String reminderId,
    required String title,
    required DateTime dateTime,
    String? description,
  }) async {
    try {
      final ref = _smartRemindersCol(uid).doc(reminderId);

      // Preserve read state if doc already exists
      bool existingIsRead = false;
      try {
        final existing = await ref.get(const GetOptions(source: Source.cache));
        if (existing.exists) {
          existingIsRead = (existing.data()?['isRead'] ?? false) as bool;
        }
      } catch (_) {
        try {
          final existing = await ref.get(const GetOptions(source: Source.server));
          if (existing.exists) {
            existingIsRead = (existing.data()?['isRead'] ?? false) as bool;
          }
        } catch (_) {}
      }

      await ref.set({
        'source':      'planner',
        'title':       title,
        'dateTime':    Timestamp.fromDate(dateTime),
        'description': description ?? '',
        'isRead':      existingIsRead,
        'createdAt':   FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('upsertPlannerReminder error: $e');
    }
  }

  /// Upsert a smart reminder for a library book.
  /// Safe to call on every book issue — preserves existing [isRead] state.
  Future<void> upsertLibraryReminder(
    String uid, {
    required String bookId,
    required String bookTitle,
    required DateTime dueDate,
  }) async {
    final reminderId = 'lib_$bookId';
    try {
      final ref = _smartRemindersCol(uid).doc(reminderId);

      bool existingIsRead = false;
      try {
        final existing = await ref.get(const GetOptions(source: Source.cache));
        if (existing.exists) {
          existingIsRead = (existing.data()?['isRead'] ?? false) as bool;
        }
      } catch (_) {
        try {
          final existing = await ref.get(const GetOptions(source: Source.server));
          if (existing.exists) {
            existingIsRead = (existing.data()?['isRead'] ?? false) as bool;
          }
        } catch (_) {}
      }

      await ref.set({
        'source':    'library',
        'title':     'Return "$bookTitle"',
        'dateTime':  Timestamp.fromDate(dueDate),
        'description': '',
        'isRead':    existingIsRead,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('upsertLibraryReminder error: $e');
    }
  }

  /// Toggle read state on a smart reminder.
  /// Called by SmartReminderScreen left-swipe.
  Future<void> toggleSmartReminderRead(
      String uid, String reminderId, bool isRead) async {
    try {
      await _smartRemindersCol(uid).doc(reminderId).update({'isRead': isRead});
    } catch (e) {
      debugPrint('toggleSmartReminderRead error: $e');
    }
  }

  /// Permanently delete a smart reminder.
  /// Called by SmartReminderScreen right-swipe.
  /// Does NOT touch the source planner task or library book.
  Future<void> deleteSmartReminder(String uid, String reminderId) async {
    try {
      await _smartRemindersCol(uid).doc(reminderId).delete();
    } catch (e) {
      debugPrint('deleteSmartReminder error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // LIBRARY
  // ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getLibraryBooks(String uid) async {
    try {
      final snap = await _libraryCol(uid)
          .orderBy('dueDate')
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> addLibraryBook(String uid,
      {required String title, required DateTime dueDate}) async {
    try {
      final ref = await _libraryCol(uid).add({
        'title':   title,
        'dueDate': Timestamp.fromDate(dueDate),
        'addedAt': FieldValue.serverTimestamp(),
        'isNotified': false,
        'isRead': false,
        'isDeleted': false,
      });

      // Mirror to smart_reminders immediately on issue
      await upsertLibraryReminder(
        uid,
        bookId:    ref.id,
        bookTitle: title,
        dueDate:   dueDate,
      );

      return ref.id;
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to add book: $e', code: 'library_add');
    }
  }

  /// Delete (return) a library book.
  /// Does NOT touch smart_reminders — the notification persists until
  /// the user dismisses it from SmartReminderScreen.
  Future<void> deleteLibraryBook(String uid, String bookId) async {
    try {
      await _libraryCol(uid).doc(bookId).delete();
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to delete book: $e', code: 'library_delete');
    }
  }

  Future<void> updateSmartReminderStatus(
    String uid,
    String bookId, {
    bool? isNotified,
    bool? isRead,
    bool? isDeleted,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      if (isNotified != null) updates['isNotified'] = isNotified;
      if (isRead != null) updates['isRead'] = isRead;
      if (isDeleted != null) updates['isDeleted'] = isDeleted;
      if (updates.isNotEmpty) {
        await _libraryCol(uid).doc(bookId).update(updates);
      }
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to update reminder status: $e', code: 'library_update');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // FOCUS STATS
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getFocusStats(String uid) async {
    try {
      final snap = await _focusCol(uid)
          .doc('summary')
          .get(const GetOptions(source: Source.serverAndCache));
      return snap.data() ?? {};
    } catch (_) {
      return {};
    }
  }

  Future<void> saveFocusSession(String uid, int minutes) async {
    if (minutes <= 0) return;
    final now     = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final ref = _focusCol(uid).doc('summary');
    try {
      await _db.runTransaction((tx) async {
        final snap     = await tx.get(ref);
        final old      = snap.data() ?? {};
        final rawLog   = (old['dailyLog'] as Map<String, dynamic>?) ?? {};
        final newLog   = Map<String, dynamic>.from(rawLog)
          ..[dateKey]  = ((rawLog[dateKey] ?? 0) as num).toInt() + minutes;
        tx.set(ref, {
          'todayMinutes':  ((old['todayMinutes']  ?? 0) as num).toInt() + minutes,
          'weekMinutes':   ((old['weekMinutes']   ?? 0) as num).toInt() + minutes,
          'monthMinutes':  ((old['monthMinutes']  ?? 0) as num).toInt() + minutes,
          'dailyLog':      newLog,
          'updatedAt':     FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to save focus session: $e', code: 'focus_save');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ADMIN REMINDERS  (untouched)
  // ─────────────────────────────────────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> adminRemindersStream() =>
      _db.collection('admin_reminders')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots();

  DocumentReference _adminStateDoc(String uid) =>
      _db.collection('students').doc(uid).collection('admin_msg').doc('admin_reminders');

  Future<Map<String, Set<String>>> getAdminStates(String uid) async {
    try {
      final doc = await _adminStateDoc(uid).get();
      if (!doc.exists || doc.data() == null) {
        return {'read': {}, 'dismissed': {}};
      }
      final data = doc.data() as Map<String, dynamic>;
      return {
        'read': (data['read_ids'] as List<dynamic>? ?? []).cast<String>().toSet(),
        'dismissed': (data['dismissed_ids'] as List<dynamic>? ?? []).cast<String>().toSet(),
      };
    } catch (_) {
      return {'read': {}, 'dismissed': {}};
    }
  }

  Future<void> toggleAdminReminderRead(String uid, String id, bool isRead) async {
    try {
      await _adminStateDoc(uid).set({
        'read_ids': isRead
            ? FieldValue.arrayUnion([id])
            : FieldValue.arrayRemove([id])
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to toggle read state: $e');
    }
  }

  Future<void> dismissAdminReminder(String uid, String id) async {
    try {
      await _adminStateDoc(uid).set({
        'dismissed_ids': FieldValue.arrayUnion([id])
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to dismiss reminder: $e');
    }
  }

  Future<String> pushAdminReminder({
    required String title,
    required String description,
    required String priority,
    required String pushedByUid,
  }) async {
    try {
      final ref = await _db.collection('admin_reminders').add({
        'title':       title,
        'description': description,
        'priority':    priority,
        'pushedBy':    pushedByUid,
        'createdAt':   FieldValue.serverTimestamp(),
        'timestamp':   FieldValue.serverTimestamp(),
      });
      return ref.id;
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to push announcement: $e', code: 'admin_push');
    }
  }

  Future<void> deleteAdminReminder(String id) async {
    try {
      await _db.collection('admin_reminders').doc(id).delete();
    } catch (e) {
      throw FirebaseServiceException(
          'Failed to delete announcement: $e', code: 'admin_delete');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PLANNER TASKS
  // ─────────────────────────────────────────────────────────────

  Future<String> addPlannerTask(String uid, Map<String, dynamic> data) async {
    try {
      data['isReminderRead'] = false;
      data['isReminderDeleted'] = false;
      final ref = await _plannerCol(uid).add(data);

      // Mirror to smart_reminders if isSmartReminder is true
      if (data['isSmartReminder'] == true) {
        final dt = (data['dateTime'] as Timestamp).toDate();
        await upsertPlannerReminder(
          uid,
          reminderId:  ref.id,
          title:       data['title'] ?? 'Task Reminder',
          dateTime:    dt,
          description: data['description'] as String?,
        );
      }

      return ref.id;
    } catch (e) {
      throw FirebaseServiceException('Failed to add task: $e', code: 'planner_add');
    }
  }

  Future<void> updatePlannerTask(String uid, String id, Map<String, dynamic> data) async {
    try {
      await _plannerCol(uid).doc(id).update(data);

      // Keep the smart_reminder mirror in sync
      if (data['isSmartReminder'] == true) {
        final dtRaw = data['dateTime'];
        final dt = dtRaw is Timestamp ? dtRaw.toDate() : dtRaw as DateTime;
        await upsertPlannerReminder(
          uid,
          reminderId:  id,
          title:       data['title'] ?? 'Task Reminder',
          dateTime:    dt,
          description: data['description'] as String?,
        );
      } else if (data.containsKey('isSmartReminder') && data['isSmartReminder'] == false) {
        // User toggled Smart Reminder OFF — remove the mirrored doc
        await deleteSmartReminder(uid, id);
      }
    } catch (e) {
      throw FirebaseServiceException('Failed to update task: $e', code: 'planner_update');
    }
  }

  /// Delete a planner task.
  /// Does NOT touch smart_reminders — notification persists until
  /// the user dismisses it from SmartReminderScreen.
  Future<void> deletePlannerTask(String uid, String id) async {
    try {
      await _plannerCol(uid).doc(id).delete();
    } catch (e) {
      throw FirebaseServiceException('Failed to delete task: $e', code: 'planner_delete');
    }
  }

  Future<void> hidePlannerReminder(String uid, String id) async {
    try {
      await _plannerCol(uid).doc(id).update({'isReminderDeleted': true});
    } catch (e) {
      throw FirebaseServiceException('Failed to hide reminder: $e', code: 'planner_hide');
    }
  }

  Future<void> togglePlannerReminderRead(String uid, String id, bool isRead) async {
    try {
      await _plannerCol(uid).doc(id).update({'isReminderRead': isRead});
    } catch (e) {
      throw FirebaseServiceException('Failed to toggle read: $e', code: 'planner_read');
    }
  }
}