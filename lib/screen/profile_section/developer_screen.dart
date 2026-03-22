// lib/screen/profile_section/developers_page.dart
//
// Developer Panel — visible only to accounts where isDeveloper == true.
// Allows pushing admin_reminders to the admin_reminders Firestore collection
// so all users see them in the SmartReminderScreen.
//
// Firestore path written:
//   admin_reminders/{autoId}
//   {
//     title:       String,
//     description: String,
//     priority:    'high' | 'medium' | 'low',
//     createdAt:   Timestamp,
//     timestamp:   Timestamp,
//   }
//
// NO bell icon or profile button in the header (as requested).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DevelopersPage extends StatefulWidget {
  const DevelopersPage({super.key});

  @override
  State<DevelopersPage> createState() => _DevelopersPageState();
}

class _DevelopersPageState extends State<DevelopersPage> {
  // ── palette (same as rest of app) ───────────────────────────
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _darkYellow = Color(0xFFE5A91A);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _green      = Color(0xFF34C759);
  static const Color _red        = Color(0xFFFF3B30);
  static const Color _purple     = Color(0xFFA78BFA);

  // ── form state ───────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();
  String _priority = 'medium'; // 'high' | 'medium' | 'low'
  bool   _isSending = false;

  // ── recent reminders sent ────────────────────────────────────
  // Shown as a live list so the developer can see what was pushed.
  final _db  = FirebaseFirestore.instance;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ── push reminder ────────────────────────────────────────────
  Future<void> _sendReminder() async {
    final title = _titleCtrl.text.trim();
    final desc  = _bodyCtrl.text.trim();
    if (title.isEmpty) {
      _showSnack('Title is required.', isError: true);
      return;
    }
    setState(() => _isSending = true);
    HapticFeedback.mediumImpact();

    try {
      final now = FieldValue.serverTimestamp();
      await _db.collection('admin_reminders').add({
        'title':       title,
        'description': desc,
        'priority':    _priority,
        'createdAt':   now,
        'timestamp':   now,
        'pushedBy':    FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
      });

      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() => _priority = 'medium');
      _showSnack('Reminder pushed to all users!', isError: false);
    } catch (e) {
      _showSnack('Failed to send: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: isError ? _red : _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── delete a reminder ────────────────────────────────────────
  Future<void> _deleteReminder(String id) async {
    try {
      await _db.collection('admin_reminders').doc(id).delete();
      _showSnack('Reminder deleted.', isError: false);
    } catch (_) {
      _showSnack('Could not delete reminder.', isError: true);
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
          // Bubble background — same as all other screens
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
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Compose card ────────────────────────
                        _composeCard(),
                        const SizedBox(height: 28),

                        // ── Recent pushes ────────────────────────
                        _sectionLabel('Recent Announcements',
                            'tap to delete'),
                        const SizedBox(height: 12),
                        _recentList(),
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
  }

  // ── Header — back button + title only, NO bell or profile ────
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
              const Text('Developer',
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      letterSpacing: -0.5)),
              const Text('Panel',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _yellow)),
              const SizedBox(height: 6),
              Text('Push announcements to all students',
                  style: TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          // Back button only — no bell or profile
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

  // ── Compose card ─────────────────────────────────────────────
  Widget _composeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // card header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: _purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.campaign_rounded, color: _purple, size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Push Announcement',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900, color: _ink)),
              Text('Sent to all students instantly',
                  style: TextStyle(
                      fontSize: 12, color: _muted, fontWeight: FontWeight.w500)),
            ]),
          ]),

          const SizedBox(height: 20),

          // Title field
          _fieldLabel('Title'),
          const SizedBox(height: 6),
          _textField(
            controller: _titleCtrl,
            hint:       'e.g. Library closed tomorrow',
            maxLines:   1,
          ),
          const SizedBox(height: 16),

          // Description field
          _fieldLabel('Description (optional)'),
          const SizedBox(height: 6),
          _textField(
            controller: _bodyCtrl,
            hint:       'Add more details here...',
            maxLines:   4,
          ),
          const SizedBox(height: 16),

          // Priority selector
          _fieldLabel('Priority'),
          const SizedBox(height: 8),
          _prioritySelector(),

          const SizedBox(height: 20),

          // Send button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _isSending ? null : _sendReminder,
              child: _isSending
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.send_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Send to All Students',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: _muted));

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9ECEF)),
        ),
        child: TextField(
          controller: controller,
          maxLines:   maxLines,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: _muted.withOpacity(0.6), fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      );

  Widget _prioritySelector() {
    const options = [
      ('high',   'High',   _red),
      ('medium', 'Medium', Color(0xFFE5A91A)),
      ('low',    'Low',    _green),
    ];
    return Row(
      children: options.map((o) {
        final active = _priority == o.$1;
        return GestureDetector(
          onTap: () => setState(() => _priority = o.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color:  active ? o.$3.withOpacity(0.12) : _bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? o.$3 : const Color(0xFFE9ECEF),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                    color: active ? o.$3 : _muted.withOpacity(0.3),
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(o.$2,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? o.$3 : _muted)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  // ── Section label ─────────────────────────────────────────────
  Widget _sectionLabel(String title, String sub) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w800, color: _ink,
              letterSpacing: -0.4)),
      const SizedBox(width: 8),
      Text(sub,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500, color: _muted)),
    ],
  );

  // ── Recent list — live stream of admin_reminders ─────────────
  Widget _recentList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('admin_reminders')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: _yellow)),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18)),
            child: Center(
              child: Column(children: [
                const Text('📢', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 8),
                Text('No announcements yet',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 4),
                Text('Push one above to get started',
                    style: TextStyle(
                        fontSize: 12, color: _muted, fontWeight: FontWeight.w500)),
              ]),
            ),
          );
        }
        return Column(
          children: docs.asMap().entries.map((e) {
            final doc  = e.value;
            final data = doc.data();
            final pri  = (data['priority'] ?? 'medium') as String;
            final priColor = pri == 'high'
                ? _red
                : (pri == 'low' ? _green : _darkYellow);
            final ts   = data['createdAt'];
            String timeStr = '';
            if (ts != null) {
              try {
                final dt = (ts as dynamic).toDate() as DateTime;
                final h  = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
                final m  = dt.minute.toString().padLeft(2, '0');
                final p  = dt.hour >= 12 ? 'PM' : 'AM';
                const months = ['Jan','Feb','Mar','Apr','May','Jun',
                                'Jul','Aug','Sep','Oct','Nov','Dec'];
                timeStr = '${months[dt.month-1]} ${dt.day},  $h:$m $p';
              } catch (_) {}
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  // priority dot
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: priColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['title'] ?? '',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800,
                                color: _ink)),
                        if ((data['description'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(data['description'],
                              style: TextStyle(
                                  fontSize: 12, color: _muted,
                                  fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 4),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: priColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(pri.toUpperCase(),
                                style: TextStyle(
                                    fontSize: 9, fontWeight: FontWeight.w800,
                                    color: priColor, letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 8),
                          if (timeStr.isNotEmpty)
                            Text(timeStr,
                                style: TextStyle(
                                    fontSize: 10, color: _muted,
                                    fontWeight: FontWeight.w500)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // delete
                  GestureDetector(
                    onTap: () => _confirmDelete(doc.id, data['title'] ?? ''),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: _red, size: 18),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ── Delete confirmation ──────────────────────────────────────
  void _confirmDelete(String id, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: _muted.withOpacity(0.1))),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: _red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: _red, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Delete Announcement',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900, color: _ink)),
              ]),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: _bg, borderRadius: BorderRadius.circular(10)),
                child: Text('"$title"',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _ink,
                        fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 10),
              Text('This will remove the announcement for all students.',
                  style: TextStyle(fontSize: 12, color: _muted,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _muted,
                    side: BorderSide(color: _muted.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteReminder(id);
                  },
                  child: const Text('Delete',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}