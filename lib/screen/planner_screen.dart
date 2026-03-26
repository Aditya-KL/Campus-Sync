import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dashboard_screen.dart'; // TopActionButtons lives here


// ─────────────────────────────────────────────────────────────
// PLANNER TASK MODEL
// ─────────────────────────────────────────────────────────────
class PlannerTask {
  String   id;
  String   title;
  DateTime dateTime;
  String   description;
  bool     isSmartReminder;
  bool     isCompleted;
  DateTime? completedAt;
  bool     isDeleting;

  PlannerTask({
    required this.id,
    required this.title,
    required this.dateTime,
    this.description    = '',
    this.isSmartReminder = false,
    this.isCompleted    = false,
    this.completedAt,
    this.isDeleting     = false,
  });

  // ── Firestore serialisation ─────────────────────────────────
  Map<String, dynamic> toMap() => {
    'title':           title,
    'dateTime':        Timestamp.fromDate(dateTime),
    'description':     description,
    'isSmartReminder': isSmartReminder,
    'isCompleted':     isCompleted,
    'completedAt':     completedAt != null
        ? Timestamp.fromDate(completedAt!)
        : null,
    'updatedAt':       FieldValue.serverTimestamp(),
  };

  factory PlannerTask.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return PlannerTask(
      id:              doc.id,
      title:           d['title']       ?? '',
      dateTime:        (d['dateTime']   as Timestamp).toDate(),
      description:     d['description'] ?? '',
      isSmartReminder: d['isSmartReminder'] ?? false,
      isCompleted:     d['isCompleted']     ?? false,
      completedAt:     d['completedAt'] != null
          ? (d['completedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PLANNER SCREEN
// ─────────────────────────────────────────────────────────────
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});
  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  // ── palette ─────────────────────────────────────────────────
  static const Color _yellow = Color(0xFFFFD166);
  static const Color _bg     = Color(0xFFF0F2F5);
  static const Color _white  = Colors.white;
  static const Color _ink    = Color(0xFF1A1D20);
  static const Color _muted  = Color(0xFF6C757D);
  static const Color _red    = Color(0xFFFF3B30);
  static const Color _green  = Color(0xFF34C759);

  String? _expandedTaskId;
  // IDs of tasks currently playing their delete animation.
  // Stored here (not on the model) so StreamBuilder rebuilds don't wipe the flag.
  final Set<String> _deletingIds = {};
  late ConfettiController _confetti;

  // ── Firestore refs ──────────────────────────────────────────
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _plannerCol =>
      _db.collection('students').doc(_uid).collection('planner');

  CollectionReference<Map<String, dynamic>> get _remindersCol =>
      _db.collection('students').doc(_uid).collection('reminders');

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // CRUD HELPERS
  // ─────────────────────────────────────────────────────────────

  Future<void> _addTask(PlannerTask task) async {
    if (_uid == null) return;
    final ref = await _plannerCol.add(task.toMap());

    // If smart reminder → also write to reminders subcollection so
    // SmartReminderScreen reflects it immediately
    if (task.isSmartReminder) {
      await _remindersCol.doc(ref.id).set({
        'title':    task.title,
        'time':     _formatTime(task.dateTime),
        'dateTime': Timestamp.fromDate(task.dateTime),
        'isRead':   false,
        'source':   'planner',
        'plannerTaskId': ref.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _updateTask(PlannerTask task) async {
    if (_uid == null) return;
    await _plannerCol.doc(task.id).update(task.toMap());

    // Sync smart reminder: upsert or delete from reminders collection
    if (task.isSmartReminder) {
      await _remindersCol.doc(task.id).set({
        'title':    task.title,
        'time':     _formatTime(task.dateTime),
        'dateTime': Timestamp.fromDate(task.dateTime),
        'isRead':   false,
        'source':   'planner',
        'plannerTaskId': task.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // Smart reminder was turned off — remove from reminders
      await _remindersCol.doc(task.id).delete().catchError((_) {});
    }
  }

  Future<void> _toggleComplete(PlannerTask task) async {
    if (_uid == null) return;
    final wasCompleted = task.isCompleted;
    final now = DateTime.now();

    setState(() {
      task.isCompleted = !wasCompleted;
      task.completedAt = task.isCompleted ? now : null;
      if (task.isCompleted) {
        _expandedTaskId = null;
        _confetti.play();
      }
    });

    await _plannerCol.doc(task.id).update({
      'isCompleted': task.isCompleted,
      'completedAt': task.isCompleted ? Timestamp.fromDate(now) : null,
      'updatedAt':   FieldValue.serverTimestamp(),
    });

    // Mark reminder as read when task is completed
    if (task.isCompleted && task.isSmartReminder) {
      await _remindersCol.doc(task.id)
          .update({'isRead': true}).catchError((_) {});
    }
  }

  // Shows a confirmation dialog, then plays the delete animation,
  // then removes from Firestore once the animation completes.
  void _confirmAndDeleteTask(PlannerTask task) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: _muted.withOpacity(0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: _red, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Delete Task',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _ink)),
              ]),
              const SizedBox(height: 16),
              // task title preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '"${task.title}"',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This task will be permanently removed and cannot be undone.',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                    height: 1.4),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _muted,
                        side: BorderSide(color: _muted.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx); // close dialog
                        _runDeleteAnimation(task);
                      },
                      child: const Text('Delete',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Plays the delete animation then removes from Firestore.
  Future<void> _runDeleteAnimation(PlannerTask task) async {
    if (_uid == null) return;
    setState(() {
      _deletingIds.add(task.id);
      // collapse expanded panel so the animation is clean
      if (_expandedTaskId == task.id) _expandedTaskId = null;
    });

    // Wait for animation to finish
    await Future.delayed(const Duration(milliseconds: 820));

    await _plannerCol.doc(task.id).delete();
    // Also remove from reminders if it had one
    await _remindersCol.doc(task.id).delete().catchError((_) {});

    if (mounted) setState(() => _deletingIds.remove(task.id));
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final p = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  // ─────────────────────────────────────────────────────────────
  // GROUPING
  // ─────────────────────────────────────────────────────────────
  Map<String, List<PlannerTask>> _group(List<PlannerTask> tasks) {
    final now      = DateTime.now();
    final today    = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final endOfWeek = today.add(
        Duration(days: DateTime.sunday - today.weekday + 7));

    final grouped = <String, List<PlannerTask>>{
      'Pending Tasks':   [],
      'Today':           [],
      'Tomorrow':        [],
      'This Week':       [],
      'Next Week':       [],
      'Completed Tasks': [],
    };

    tasks.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    for (final task in tasks) {
      final taskDate = DateTime(
          task.dateTime.year, task.dateTime.month, task.dateTime.day);

      if (task.isCompleted && task.completedAt != null) {
        final compDate = DateTime(task.completedAt!.year,
            task.completedAt!.month, task.completedAt!.day);
        if (compDate == today) grouped['Completed Tasks']!.add(task);
        continue;
      }

      if (task.dateTime.isBefore(now) && !task.isCompleted) {
        grouped['Pending Tasks']!.add(task);
      } else if (taskDate == today) {
        grouped['Today']!.add(task);
      } else if (taskDate == tomorrow) {
        grouped['Tomorrow']!.add(task);
      } else if (taskDate.isAfter(tomorrow) && taskDate.isBefore(endOfWeek)) {
        grouped['This Week']!.add(task);
      } else {
        grouped['Next Week']!.add(task);
      }
    }
    return grouped;
  }

  // ─────────────────────────────────────────────────────────────
  // ADD / EDIT DIALOG
  // ─────────────────────────────────────────────────────────────
  void _showTaskDialog({PlannerTask? taskToEdit}) {
    final isEditing       = taskToEdit != null;
    final titleCtrl       = TextEditingController(text: taskToEdit?.title ?? '');
    final descCtrl        = TextEditingController(text: taskToEdit?.description ?? '');
    DateTime selDate      = taskToEdit?.dateTime ?? DateTime.now();
    TimeOfDay selTime     = taskToEdit != null
        ? TimeOfDay.fromDateTime(taskToEdit.dateTime)
        : TimeOfDay.now();
    bool isSmartReminder  = taskToEdit?.isSmartReminder ?? false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          void showError(String msg) {
            setDS(() => errorMsg = msg);
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) setDS(() { if (errorMsg == msg) errorMsg = null; });
            });
          }

          return Dialog(
            backgroundColor: _white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: _muted.withOpacity(0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // title
                    Text(isEditing ? 'Edit Task' : 'New Task',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: _ink)),
                    const SizedBox(height: 16),

                    // error banner
                    if (errorMsg != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline,
                              color: _red, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(errorMsg!,
                                style: const TextStyle(
                                    color: _red,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                        ]),
                      ).animate().fadeIn(duration: 200.ms)
                          .slideY(begin: -0.1, end: 0, duration: 200.ms),

                    // task title field
                    _dialogField(titleCtrl, 'Task Title', maxLines: 1),
                    const SizedBox(height: 12),

                    // date + time row
                    Row(children: [
                      Expanded(child: _dateTimeBtn(
                        icon: Icons.calendar_today,
                        label: '${selDate.day}/${selDate.month}/${selDate.year}',
                        onTap: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: selDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 1)),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) setDS(() => selDate = d);
                        },
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _dateTimeBtn(
                        icon: Icons.access_time,
                        label: selTime.format(ctx),
                        onTap: () async {
                          final t = await showTimePicker(
                              context: ctx, initialTime: selTime);
                          if (t != null) setDS(() => selTime = t);
                        },
                      )),
                    ]),
                    const SizedBox(height: 12),

                    // description
                    _dialogField(descCtrl, 'Short Description',
                        maxLines: 2, maxLength: 80),
                    const SizedBox(height: 16),

                    // smart reminder toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Smart Reminder',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _ink,
                                      fontSize: 15)),
                              SizedBox(height: 2),
                              Text('Appears on Reminders page',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFD4A33B),
                                      fontSize: 12)),
                            ],
                          ),
                          Switch(
                            value: isSmartReminder,
                            activeColor: _yellow,
                            activeTrackColor: _yellow.withOpacity(0.45),
                            inactiveThumbColor: _muted,
                            inactiveTrackColor: Colors.grey.shade300,
                            onChanged: (v) =>
                                setDS(() => isSmartReminder = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Cancel',
                              style: TextStyle(
                                  color: _muted,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _yellow,
                            foregroundColor: _ink,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (titleCtrl.text.trim().isEmpty) {
                              showError('Please enter a task title!');
                              return;
                            }
                            final newDT = DateTime(
                              selDate.year, selDate.month, selDate.day,
                              selTime.hour, selTime.minute,
                            );
                            if (newDT.isBefore(DateTime.now()) && !isEditing) {
                              showError('Cannot schedule tasks in the past!');
                              return;
                            }

                            if (isEditing) {
                              taskToEdit.title           = titleCtrl.text.trim();
                              taskToEdit.dateTime        = newDT;
                              taskToEdit.description     = descCtrl.text.trim();
                              taskToEdit.isSmartReminder = isSmartReminder;
                              _updateTask(taskToEdit);
                            } else {
                              _addTask(PlannerTask(
                                id:              '',
                                title:           titleCtrl.text.trim(),
                                dateTime:        newDT,
                                description:     descCtrl.text.trim(),
                                isSmartReminder: isSmartReminder,
                              ));
                            }
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            isEditing ? 'Save' : 'Add Task',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── dialog helpers ──────────────────────────────────────────
  Widget _dialogField(TextEditingController ctrl, String hint,
      {int maxLines = 1, int? maxLength}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(
          color: _ink, fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _muted),
        filled: true,
        fillColor: _bg,
        counterText: '',
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      ),
    );
  }

  Widget _dateTimeBtn(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 16, color: _muted),
      label: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      onPressed: onTap,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // bubbles
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
                  // ── REAL-TIME stream from Firestore ──────────
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _plannerCol
                        .orderBy('dateTime')
                        .snapshots(),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: _yellow));
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('Error loading tasks',
                                style: TextStyle(color: _muted)));
                      }

                      // Build task list from snapshot
                      final tasks = snap.data?.docs
                              .map(PlannerTask.fromDoc)
                              .toList() ??
                          [];

                      // Preserve isDeleting flag across rebuilds
                      for (final t in tasks) {
                        // nothing extra needed — Firestore deletes
                        // remove docs from stream automatically
                      }

                      final grouped = _group(tasks);
                      final hasAny =
                          grouped.values.any((l) => l.isNotEmpty);

                      if (!hasAny) {
                        return _emptyState();
                      }

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
                        children: grouped.entries.map((entry) {
                          if (entry.value.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          Color headerColor = _muted;
                          if (entry.key == 'Pending Tasks') {
                            headerColor = _red;
                          }
                          if (entry.key == 'Completed Tasks') {
                            headerColor = _green;
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    top: 18, bottom: 8, left: 4),
                                child: Text(
                                  entry.key.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: headerColor,
                                      letterSpacing: 1.5),
                                ),
                              ),
                              ...entry.value
                                  .map((t) => _buildTaskCard(t))
                                  .toList(),
                            ],
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // confetti
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              maxBlastForce: 20,
              minBlastForce: 10,
              colors: const [
                _yellow,
                Colors.white,
                Colors.greenAccent,
                Colors.blueAccent,
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Productivity',
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      letterSpacing: -0.5)),
              Text('Tracker',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _yellow)),
              SizedBox(height: 6),
              Text('Manage your timeline',
                  style: TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const TopActionButtons(),
              const SizedBox(height: 18),
              // Add task button
              GestureDetector(
                onTap: () => _showTaskDialog(),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _yellow,
                    borderRadius: const BorderRadius.only(
                      topLeft:     Radius.circular(20),
                      topRight:    Radius.circular(8),
                      bottomLeft:  Radius.circular(8),
                      bottomRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: _yellow.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Icon(Icons.add, color: _ink, size: 26),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── EMPTY STATE ─────────────────────────────────────────────
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('📋', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text('No tasks yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _ink)),
          const SizedBox(height: 6),
          Text('Tap + to add your first task',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted)),
        ],
      ),
    );
  }

  // ── TASK CARD ───────────────────────────────────────────────
  Widget _buildTaskCard(PlannerTask task) {
    final isExpanded  = _expandedTaskId == task.id;
    final isPending   = task.dateTime.isBefore(DateTime.now()) && !task.isCompleted;
    final timeStr     = _formatTime(task.dateTime);

    Widget card = GestureDetector(
      onTap: () {
        if (!task.isCompleted) {
          setState(() =>
              _expandedTaskId = isExpanded ? null : task.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? _white.withOpacity(0.5)
                    : _white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPending
                      ? _red.withOpacity(0.5)
                      : Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── row: checkbox + title + time ───────────
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleComplete(task),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 24, height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: task.isCompleted
                                ? _green
                                : Colors.transparent,
                            border: Border.all(
                              color: task.isCompleted
                                  ? _green
                                  : _muted.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: task.isCompleted
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: task.isCompleted ? _muted : _ink,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Colors.black87,
                            decorationThickness: 2.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Smart reminder badge
                      if (task.isSmartReminder && !task.isCompleted)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _yellow.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.bolt,
                              size: 12, color: Color(0xFFD4A33B)),
                        ),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: isPending
                              ? _red
                              : (task.isCompleted
                                  ? _muted
                                  : _ink.withOpacity(0.8)),
                        ),
                      ),
                    ],
                  ),

                  // ── expanded panel ──────────────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutQuart,
                    child: (isExpanded && !task.isCompleted)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Divider(
                                  color: _muted.withOpacity(0.15), height: 1),
                              const SizedBox(height: 12),

                              if (task.isSmartReminder) ...[
                                Row(children: const [
                                  Icon(Icons.bolt,
                                      color: _yellow, size: 16),
                                  SizedBox(width: 6),
                                  Text('Smart Reminder Active',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: _ink,
                                          fontSize: 12)),
                                ]),
                                const SizedBox(height: 10),
                              ],

                              if (task.description.isNotEmpty)
                                Text(
                                  task.description,
                                  style: TextStyle(
                                      color: _muted,
                                      fontSize: 14,
                                      height: 1.4,
                                      fontWeight: FontWeight.w500),
                                ),

                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _confirmAndDeleteTask(task),
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent, size: 16),
                                    label: const Text('Delete',
                                        style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _ink,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      elevation: 0,
                                    ),
                                    onPressed: () =>
                                        _showTaskDialog(taskToEdit: task),
                                    icon: const Icon(Icons.edit, size: 14),
                                    label: const Text('Edit',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Delete animation — driven by _deletingIds (persists across StreamBuilder rebuilds)
    if (_deletingIds.contains(task.id)) {
      return card
          .animate()
          .blurXY(begin: 0, end: 25, duration: 800.ms, curve: Curves.easeIn)
          .fadeOut(duration: 800.ms, curve: Curves.easeIn)
          .slideX(begin: 0, end: 0.3, duration: 800.ms, curve: Curves.easeIn)
          .scale(
              begin: const Offset(1, 1),
              end: const Offset(1.1, 1.1),
              duration: 800.ms);
    }
    return card;
  }
}