import 'package:campus_sync/services/firebase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_refresher.dart';
// import '../services/notification_services.dart';

// ─────────────────────────────────────────────────────────────
// REMINDER MODEL
// Two live sources from smart_reminders subcollection:
//   planner  → source == 'planner'
//   library  → source == 'library'
// Plus admin broadcasts from admin_reminders (unchanged).
// ─────────────────────────────────────────────────────────────
enum ReminderSource { planner, library, admin }

class SmartReminder {
  final String         id;
  final String         title;
  final String         subtitle;
  final DateTime       dateTime;
  final DateTime       createdAt;  // used for Today / This Week / Earlier
  final ReminderSource source;
  final bool           isRead;
  final bool           isUrgent;
  final String?        description;
  final String?        priority; // admin only

  SmartReminder({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.dateTime,
    required this.createdAt,
    required this.source,
    required this.isRead,
    required this.isUrgent,
    this.description,
    this.priority,
  });

  SmartReminder copyWith({bool? isRead}) => SmartReminder(
    id:          id,
    title:       title,
    subtitle:    subtitle,
    dateTime:    dateTime,
    createdAt:   createdAt,
    source:      source,
    isRead:      isRead ?? this.isRead,
    isUrgent:    isUrgent,
    description: description,
    priority:    priority,
  );
}

// ─────────────────────────────────────────────────────────────
// SMART REMINDER SCREEN
// ─────────────────────────────────────────────────────────────
class SmartReminderScreen extends StatefulWidget {
  const SmartReminderScreen({super.key});
  @override
  State<SmartReminderScreen> createState() => _SmartReminderScreenState();
}

class _SmartReminderScreenState extends State<SmartReminderScreen> {
  // ── palette ─────────────────────────────────────────────────
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _green      = Color(0xFF34C759);
  static const Color _red        = Color(0xFFFF3B30);

  // ── source styling ──────────────────────────────────────────
  static const Map<ReminderSource, Color> _srcColor = {
    ReminderSource.planner: Color(0xFFFFD166),
    ReminderSource.library: Color(0xFF007AFF),
    ReminderSource.admin:   Color(0xFFA78BFA),
  };
  static const Map<ReminderSource, IconData> _srcIcon = {
    ReminderSource.planner: Icons.bolt_rounded,
    ReminderSource.library: Icons.menu_book_rounded,
    ReminderSource.admin:   Icons.campaign_rounded,
  };
  static const Map<ReminderSource, String> _srcLabel = {
    ReminderSource.planner: 'Task',
    ReminderSource.library: 'Library',
    ReminderSource.admin:   'Admin',
  };

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _db  = FirebaseFirestore.instance;
  final _userCreationTime = FirebaseAuth.instance.currentUser?.metadata.creationTime;

  // ── animation / optimistic state ────────────────────────────
  final Set<String>      _deletingIds     = {};
  final Set<String>      _togglingReadIds = {};
  final Map<String, bool> _localRead      = {};

  // ── admin state (unchanged) ──────────────────────────────────
  final Set<String> _dismissedAdminIds = {};
  final Set<String> _readAdminIds      = {};

  // ── streams ─────────────────────────────────────────────────
  late Stream<QuerySnapshot<Map<String, dynamic>>> _smartRemindersStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _adminStream;

  @override
  void initState() {
    super.initState();

    // Single stream from smart_reminders subcollection (newest first)
    _smartRemindersStream = _db
        .collection('students')
        .doc(_uid)
        .collection('smart_reminders')
        .orderBy('createdAt', descending: true)
        .snapshots();

    // Admin broadcasts — unchanged
    _adminStream = _db
        .collection('admin_reminders')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();

    _loadAdminStates();
  }

  Future<void> _loadAdminStates() async {
    if (_uid.isEmpty) return;
    final states = await FirebaseService.instance.getAdminStates(_uid);
    if (mounted) {
      setState(() {
        _readAdminIds
          ..clear()
          ..addAll(states['read']!);
        _dismissedAdminIds
          ..clear()
          ..addAll(states['dismissed']!);
      });
    }
  }

  Future<void> _handleRefresh() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 1200));
    await _loadAdminStates();
    if (mounted) {
      setState(() {});
      HapticFeedback.mediumImpact();
    }
  }


  // ─────────────────────────────────────────────────────────────
  // BUILD REMINDER LIST from smart_reminders + admin snapshots
  // ─────────────────────────────────────────────────────────────
  List<SmartReminder> _buildList(
    QuerySnapshot<Map<String, dynamic>> smartSnap,
    QuerySnapshot<Map<String, dynamic>> adminSnap,
  ) {
    final now    = DateTime.now();
    final result = <SmartReminder>[];
    final seen   = <String>{};

    // ── 1. smart_reminders (planner + library) ────────────────
    for (final doc in smartSnap.docs) {
      if (_deletingIds.contains(doc.id)) continue;
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);

      final d          = doc.data();
      final sourceStr  = (d['source'] ?? 'planner') as String;
      final source     = sourceStr == 'library'
          ? ReminderSource.library
          : ReminderSource.planner;

      final dt        = _toDateTime(d['dateTime']);
      if (dt == null) continue;

      // createdAt drives grouping; fall back to dateTime if missing
      final createdAt = _toDateTime(d['createdAt']) ?? dt;

      final firestoreRead = (d['isRead'] ?? false) as bool;
      final isRead = _localRead.containsKey(doc.id)
          ? _localRead[doc.id]!
          : firestoreRead;

      final diff   = dt.difference(now);
      final isPast = dt.isBefore(now);

      // Urgency: library due within 8h, planner due within 2h
      final bool isUrgent = source == ReminderSource.library
          ? (!isPast && diff.inHours <= 8)
          : (!isPast && diff.inHours <= 2);

      final String subtitle;
      if (source == ReminderSource.library) {
        subtitle = isPast
            ? 'Overdue — please return today'
            : 'Due in ${diff.inHours}h ${diff.inMinutes % 60}m';
      } else {
        subtitle = isPast
            ? '⚠ Overdue — ${_formatDateTime(dt)}'
            : _relativeTime(dt);
      }

      result.add(SmartReminder(
        id:          doc.id,
        title:       (d['title'] ?? '') as String,
        subtitle:    subtitle,
        dateTime:    dt,
        createdAt:   createdAt,
        source:      source,
        isRead:      isRead,
        isUrgent:    isUrgent,
        description: d['description'] as String?,
      ));
    }

    // ── 2. Admin broadcasts (unchanged logic) ─────────────────
    for (final doc in adminSnap.docs) {
      if (_deletingIds.contains(doc.id)) continue;
      if (_dismissedAdminIds.contains(doc.id)) continue;
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);

      final d  = doc.data();
      final ts = _toDateTime(d['timestamp'] ?? d['createdAt']);
      if (_userCreationTime != null &&
          ts != null &&
          ts.isBefore(_userCreationTime!)) {
        continue;
      }
      final dispDt    = ts ?? now;
      final createdAt = ts ?? now;

      final firestoreRead = _readAdminIds.contains(doc.id);
      final isRead = _localRead.containsKey(doc.id)
          ? _localRead[doc.id]!
          : firestoreRead;

      result.add(SmartReminder(
        id:          doc.id,
        title:       (d['title'] ?? 'Notice') as String,
        subtitle:    ts != null ? _relativeTime(ts) : 'Just now',
        dateTime:    dispDt,
        createdAt:   createdAt,
        source:      ReminderSource.admin,
        isRead:      isRead,
        isUrgent:    d['priority'] == 'high',
        description: d['description'] as String?,
        priority:    d['priority']    as String?,
      ));
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // GROUPING — Today / This Week / Earlier
  // Based on createdAt (when the notification was received),
  // NOT on the task due date.
  // ─────────────────────────────────────────────────────────────
  Map<String, List<SmartReminder>> _group(List<SmartReminder> items) {
    final now      = DateTime.now();
    final todayMid = DateTime(now.year, now.month, now.day);
    final weekAgo  = todayMid.subtract(const Duration(days: 7));

    final groups = <String, List<SmartReminder>>{
      'Today':     [],
      'This Week': [],
      'Earlier':   [],
    };

    for (final r in items) {
      final created = DateTime(
        r.createdAt.year,
        r.createdAt.month,
        r.createdAt.day,
      );

      if (!created.isBefore(todayMid)) {
        groups['Today']!.add(r);
      } else if (!created.isBefore(weekAgo)) {
        groups['This Week']!.add(r);
      } else {
        groups['Earlier']!.add(r);
      }
    }

    // Within each group: urgent first, then newest createdAt first
    for (final list in groups.values) {
      list.sort((a, b) {
        if (a.isUrgent && !b.isUrgent) return -1;
        if (!a.isUrgent && b.isUrgent) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return groups;
  }

  // ─────────────────────────────────────────────────────────────
  // SWIPE ACTIONS
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleDelete(SmartReminder r) async {
    setState(() => _deletingIds.add(r.id));
    await Future.delayed(const Duration(milliseconds: 820));
    await _firestoreDelete(r);
    if (mounted) setState(() => _deletingIds.remove(r.id));
  }

  Future<void> _firestoreDelete(SmartReminder r) async {
    switch (r.source) {
      case ReminderSource.planner:
      case ReminderSource.library:
        // Delete the smart_reminder doc only — source docs untouched
        await FirebaseService.instance.deleteSmartReminder(_uid, r.id);
        break;
      case ReminderSource.admin:
        setState(() => _dismissedAdminIds.add(r.id));
        await FirebaseService.instance.dismissAdminReminder(_uid, r.id);
        break;
    }
  }

  void _handleToggleRead(SmartReminder r) {
    HapticFeedback.lightImpact();
    final newRead = !r.isRead;

    setState(() {
      _togglingReadIds.add(r.id);
      _localRead[r.id] = newRead;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _togglingReadIds.remove(r.id));
    });

    _firestoreToggleRead(r, newRead);
  }

  Future<void> _firestoreToggleRead(SmartReminder r, bool newRead) async {
    switch (r.source) {
      case ReminderSource.planner:
      case ReminderSource.library:
        await FirebaseService.instance
            .toggleSmartReminderRead(_uid, r.id, newRead);
        break;
      case ReminderSource.admin:
        await FirebaseService.instance
            .toggleAdminReminderRead(_uid, r.id, newRead);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned(top: -60, right: -40,
              child: CircleAvatar(radius: 140,
                  backgroundColor: _yellow.withOpacity(0.35))),
          Positioned(top: 150, left: -80,
              child: CircleAvatar(radius: 100,
                  backgroundColor: const Color(0xFFE2E5E9))),
          Positioned(bottom: -30, right: -20,
              child: CircleAvatar(radius: 130,
                  backgroundColor: _yellow.withOpacity(0.15))),
          Positioned(bottom: 100, left: 20,
              child: CircleAvatar(radius: 90,
                  backgroundColor: const Color(0xFFD3D6DA))),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
              const Text('Smart',
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      letterSpacing: -0.5)),
              const Text('Reminders',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _yellow)),
              const SizedBox(height: 6),
              Text('Swipe ← read/unread  •  swipe → delete',
                  style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _ink, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ── BODY — 2 nested StreamBuilders ──────────────────────────
  Widget _buildBody() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _smartRemindersStream,
      builder: (_, smartSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _adminStream,
          builder: (_, adminSnap) {
            final loading =
                (smartSnap.connectionState == ConnectionState.waiting &&
                    !smartSnap.hasData) &&
                (adminSnap.connectionState == ConnectionState.waiting &&
                    !adminSnap.hasData);

            if (loading) {
              return const Center(
                  child: CircularProgressIndicator(color: _yellow));
            }

            final all = _buildList(
              smartSnap.data  ?? _emptySnap(),
              adminSnap.data  ?? _emptySnap(),
            );
            final grouped = _group(all);
            final hasAny  = grouped.values.any((l) => l.isNotEmpty);

            if (!hasAny) return _emptyState();

            // Flat list for stagger index calculation
            final flat = <SmartReminder>[];
            for (final g in grouped.values) flat.addAll(g);

            return CustomRefresher(
              onRefresh: _handleRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                children: [
                  _buildLegend(),
                  const SizedBox(height: 8),
                  ...grouped.entries.map((e) {
                    if (e.value.isEmpty) return const SizedBox.shrink();
                    return _buildGroup(e.key, e.value, flat);
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  QuerySnapshot<Map<String, dynamic>> _emptySnap() =>
      _EmptyQuerySnapshot<Map<String, dynamic>>();

  // ── SOURCE LEGEND ────────────────────────────────────────────
  Widget _buildLegend() {
    return Row(
      children: ReminderSource.values.map((src) {
        final color = _srcColor[src]!;
        final icon  = _srcIcon[src]!;
        final label = _srcLabel[src]!;
        return Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
        );
      }).toList(),
    );
  }

  // ── GROUP SECTION ────────────────────────────────────────────
  Widget _buildGroup(String label, List<SmartReminder> items,
      List<SmartReminder> flatAll) {

    Color labelColor = _muted;
    if (label == 'Today')     labelColor = _ink;
    if (label == 'This Week') labelColor = _darkYellow;
    if (label == 'Earlier')   labelColor = _muted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10, left: 2),
          child: Row(
            children: [
              if (label == 'Today') ...[
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                      color: _yellow, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ],
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: labelColor,
                      letterSpacing: 1.4)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: labelColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${items.length}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: labelColor)),
              ),
            ],
          ),
        ),
        ...items.asMap().entries.map((e) {
          final globalIdx = flatAll.indexOf(e.value);
          return _buildReminderCard(e.value, globalIdx);
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // REMINDER CARD
  // ─────────────────────────────────────────────────────────────
  Widget _buildReminderCard(SmartReminder r, int index) {
    final accent = _srcColor[r.source]!;
    final icon   = _srcIcon[r.source]!;

    Color priorityColor = accent;
    if (r.priority == 'high')   priorityColor = _red;
    if (r.priority == 'medium') priorityColor = _darkYellow;
    if (r.priority == 'low')    priorityColor = _green;

    Widget cardContent = GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (r.description != null && r.description!.isNotEmpty) {
          _showDetailSheet(r, accent, icon);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: r.isRead ? Colors.white.withOpacity(0.45) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: r.isUrgent
                  ? _red.withOpacity(0.08)
                  : (r.isRead
                      ? Colors.transparent
                      : Colors.black.withOpacity(0.06)),
              blurRadius: r.isUrgent ? 16 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colour accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: r.isRead
                      ? _muted.withOpacity(0.2)
                      : (r.isUrgent ? _red : accent),
                  borderRadius: const BorderRadius.only(
                    topLeft:    Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                  ),
                ),
              ),
              // Icon bubble
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 10, 16),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: (r.isUrgent ? _red : accent).withOpacity(
                        r.isRead ? 0.06 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    r.isUrgent ? Icons.notifications_active_rounded : icon,
                    color: r.isRead
                        ? _muted
                        : (r.isUrgent ? _red : accent),
                    size: 20,
                  ),
                ),
              ),
              // Text content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: r.isRead
                                    ? FontWeight.w700
                                    : FontWeight.w900,
                                color: r.isRead ? _muted : _ink,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!r.isRead)
                            Container(
                              width: 9, height: 9,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: r.isUrgent ? _red : _yellow,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (r.isUrgent ? _red : _yellow)
                                        .withOpacity(0.5),
                                    blurRadius: 4,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: r.isUrgent
                              ? _red
                              : (r.isRead
                                  ? _muted.withOpacity(0.6)
                                  : _yellow),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _badge(icon, _srcLabel[r.source]!, accent),
                          if (r.priority != null) ...[
                            const SizedBox(width: 6),
                            _badge(Icons.flag_rounded,
                                r.priority!.toUpperCase(), priorityColor),
                          ],
                          if (r.isUrgent) ...[
                            const SizedBox(width: 6),
                            _badge(Icons.bolt_rounded, 'URGENT', _red),
                          ],
                          if (r.isRead) ...[
                            const SizedBox(width: 6),
                            _badge(Icons.done_all_rounded, 'READ',
                                _muted.withOpacity(0.5)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (r.description != null && r.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 18, color: _muted.withOpacity(0.4)),
                )
              else
                const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );

    // Staggered entrance
    cardContent = cardContent
        .animate()
        .fade(duration: 380.ms, delay: Duration(milliseconds: 40 * index))
        .slideX(
          begin: 0.08, end: 0,
          duration: 380.ms,
          delay: Duration(milliseconds: 40 * index),
          curve: Curves.easeOutCubic,
        );

    // Delete animation
    if (_deletingIds.contains(r.id)) {
      return cardContent
          .animate()
          .blurXY(begin: 0, end: 25, duration: 800.ms, curve: Curves.easeIn)
          .fadeOut(duration: 800.ms, curve: Curves.easeIn)
          .slideX(begin: 0, end: 0.3, duration: 800.ms, curve: Curves.easeIn)
          .scale(
              begin: const Offset(1, 1),
              end:   const Offset(1.1, 1.1),
              duration: 800.ms);
    }

    // Read-toggle shimmer
    if (_togglingReadIds.contains(r.id)) {
      cardContent = cardContent
          .animate()
          .scale(
              begin: const Offset(1, 1),
              end:   const Offset(1.03, 1.03),
              duration: 200.ms,
              curve: Curves.easeOut)
          .shimmer(duration: 400.ms, color: _yellow.withOpacity(0.5))
          .then()
          .scale(
              begin: const Offset(1.03, 1.03),
              end:   const Offset(1, 1),
              duration: 200.ms,
              curve: Curves.easeIn);
    }

    // Dismissible wrapper
    return Dismissible(
      key: ValueKey('rem_${r.id}'),
      // Right-to-left → delete
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: _red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_sweep_rounded,
            color: Colors.white, size: 28),
      ),
      // Left-to-right → toggle read
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: r.isRead ? _muted.withOpacity(0.25) : _yellow,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          r.isRead
              ? Icons.mark_email_unread_rounded
              : Icons.mark_email_read_rounded,
          color: r.isRead ? _muted : _ink,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _handleDelete(r);
        } else {
          _handleToggleRead(r);
        }
        return false; // we handle state ourselves
      },
      child: cardContent,
    );
  }

  // ── DETAIL BOTTOM SHEET ──────────────────────────────────────
  void _showDetailSheet(SmartReminder r, Color accent, IconData icon) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.title,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: _ink)),
                      Text(r.subtitle,
                          style: const TextStyle(
                              fontSize: 12,
                              color: _muted,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
            if (r.description != null && r.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bg, borderRadius: BorderRadius.circular(14)),
                child: Text(r.description!,
                    style: const TextStyle(
                        fontSize: 14,
                        color: _ink,
                        fontWeight: FontWeight.w500,
                        height: 1.5)),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _chip(Icons.schedule_rounded, _formatDateTime(r.dateTime), _muted),
                _chip(icon, _srcLabel[r.source]!, accent),
                if (r.priority != null)
                  _chip(Icons.flag_rounded, r.priority!.toUpperCase(),
                      r.priority == 'high' ? _red : _darkYellow),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── EMPTY STATE ──────────────────────────────────────────────
  Widget _emptyState() {
    return CustomRefresher(
      onRefresh: _handleRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🔔',
                    style: TextStyle(fontSize: 52, height: 1.0)),
                const SizedBox(height: 18),
                const Text('All clear!',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _ink)),
                const SizedBox(height: 8),
                Text('No reminders right now.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _muted)),
                const SizedBox(height: 6),
                Text(
                    'Tasks with Smart Reminder and library\ndue dates will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: _muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────
  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  DateTime? _toDateTime(dynamic val) {
    if (val == null) return null;
    if (val is Timestamp) return val.toDate();
    if (val is DateTime)  return val;
    return null;
  }

  String _relativeTime(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.inMinutes < 1)  return 'Right now';
    if (diff.inMinutes < 60) return 'In ${diff.inMinutes}m';
    if (diff.inHours < 24)   return 'In ${diff.inHours}h';
    if (diff.inDays == 1)    return 'Tomorrow';
    if (diff.inDays < 7)     return 'In ${diff.inDays} days';
    return _formatDateTime(dt);
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, $h:$m $p';
  }
}

// ─────────────────────────────────────────────────────────────
// Empty snapshot stub
// ─────────────────────────────────────────────────────────────
class _EmptyQuerySnapshot<T> implements QuerySnapshot<T> {
  @override List<QueryDocumentSnapshot<T>> get docs       => [];
  @override List<DocumentChange<T>>        get docChanges => [];
  @override SnapshotMetadata               get metadata   =>
      throw UnimplementedError();
  @override int get size => 0;
}