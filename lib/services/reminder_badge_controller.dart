import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReminderBadgeController {
  static final ReminderBadgeController instance = ReminderBadgeController._();
  ReminderBadgeController._();

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  StreamSubscription? _smartSub;
  StreamSubscription? _adminSub;
  StreamSubscription? _adminPrefSub;
  Timer? _debounce;

  int _smartCount = 0;
  int _adminCount = 0;

  void _updateCount() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      unreadCount.value = _smartCount + _adminCount;
    });
  }

  void init() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final creationTime = user.metadata.creationTime;
    final db = FirebaseFirestore.instance;

    List<QueryDocumentSnapshot> adminDocs = [];
    Set<String> readIds = {};
    Set<String> dismissedIds = {};
    bool prefsLoaded = false;

    void recompute() {
      if (!prefsLoaded) return;
      int count = 0;
      for (final doc in adminDocs) {
        final data = doc.data() as Map<String, dynamic>;
        if (dismissedIds.contains(doc.id)) continue;
        if (readIds.contains(doc.id)) continue;
        final raw = data['createdAt'] ?? data['timestamp'];
        if (raw == null) continue;
        final createdAt = (raw as Timestamp).toDate();
        if (creationTime != null && createdAt.isBefore(creationTime)) continue;
        count++;
      }
      _adminCount = count;
      _updateCount();
    }

    _smartSub?.cancel();
    _smartSub = db
        .collection('students')
        .doc(uid)
        .collection('smart_reminders')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      _smartCount = snap.docs.length;
      _updateCount();
    });

    _adminPrefSub?.cancel();
    _adminPrefSub = db
        .collection('students')
        .doc(uid)
        .collection('admin_msg')
        .doc('admin_reminders')
        .snapshots()
        .listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        readIds = (data['read_ids'] as List<dynamic>? ?? [])
            .cast<String>()
            .toSet();
        dismissedIds = (data['dismissed_ids'] as List<dynamic>? ?? [])
            .cast<String>()
            .toSet();
      } else {
        readIds = {};
        dismissedIds = {};
      }
      prefsLoaded = true;
      recompute();
    });

    _adminSub?.cancel();
    _adminSub = db
        .collection('admin_reminders')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snap) {
      adminDocs = snap.docs;
      recompute();
    });
  }

  void dispose() {
    _debounce?.cancel();
    _smartSub?.cancel();
    _adminSub?.cancel();
    _adminPrefSub?.cancel();
    unreadCount.value = 0;
  }
}