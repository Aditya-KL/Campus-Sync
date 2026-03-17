import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:confetti/confetti.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'profile_section/profile_screen.dart';
import 'smart_reminder_screen.dart';

// --- Task Model ---
class PlannerTask {
  String id;
  String title;
  DateTime dateTime;
  String description;
  bool isSmartReminder;
  bool isCompleted;
  DateTime? completedAt;
  bool isDeleting;

  PlannerTask({
    required this.id,
    required this.title,
    required this.dateTime,
    this.description = '',
    this.isSmartReminder = false,
    this.isCompleted = false,
    this.completedAt,
    this.isDeleting = false,
  });
}

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  List<PlannerTask> tasks = [];
  String? expandedTaskId;

  late ConfettiController _confettiController;

  // --- Light Theme Colors ---
  final Color primaryYellow = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite = Colors.white;
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 800),
    );

    final now = DateTime.now();
    tasks.addAll([
      PlannerTask(
        id: '1',
        title: "Project Submission",
        dateTime: now.add(const Duration(hours: 2)),
        description: "Submit the final C++ assembler project files.",
        isSmartReminder: true,
      ),
      PlannerTask(
        id: '2',
        title: "Mid-Term Exam",
        dateTime: now.add(const Duration(days: 1)),
        description: "Revise all chapters before the exam.",
      ),
    ]);
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  // --- Categorization Logic ---
  Map<String, List<PlannerTask>> _getGroupedTasks() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final endOfWeek = today.add(
      Duration(days: DateTime.sunday - today.weekday + 7),
    );

    Map<String, List<PlannerTask>> grouped = {
      "Pending Tasks": [],
      "Today": [],
      "Tomorrow": [],
      "This Week": [],
      "Next Week": [],
      "Completed Tasks": [],
    };

    tasks.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    for (var task in tasks) {
      final taskDate = DateTime(
        task.dateTime.year,
        task.dateTime.month,
        task.dateTime.day,
      );

      if (task.isCompleted && task.completedAt != null) {
        final compDate = DateTime(
          task.completedAt!.year,
          task.completedAt!.month,
          task.completedAt!.day,
        );
        if (compDate == today) grouped["Completed Tasks"]!.add(task);
        continue;
      }

      if (task.dateTime.isBefore(now) && !task.isCompleted) {
        grouped["Pending Tasks"]!.add(task);
      } else if (taskDate == today) {
        grouped["Today"]!.add(task);
      } else if (taskDate == tomorrow) {
        grouped["Tomorrow"]!.add(task);
      } else if (taskDate.isAfter(tomorrow) && taskDate.isBefore(endOfWeek)) {
        grouped["This Week"]!.add(task);
      } else {
        grouped["Next Week"]!.add(task);
      }
    }
    return grouped;
  }

  void _toggleComplete(PlannerTask task) {
    setState(() {
      task.isCompleted = !task.isCompleted;
      task.completedAt = task.isCompleted ? DateTime.now() : null;
      if (task.isCompleted) {
        expandedTaskId = null;
        _confettiController.play();
      }
    });
  }

  void _deleteTask(PlannerTask task) {
    setState(() => task.isDeleting = true);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          tasks.removeWhere((t) => t.id == task.id);
          if (expandedTaskId == task.id) expandedTaskId = null;
        });
      }
    });
  }

  // --- Add/Edit Dialog ---
  void _showTaskDialog({PlannerTask? taskToEdit}) {
    final isEditing = taskToEdit != null;
    final titleController = TextEditingController(
      text: taskToEdit?.title ?? '',
    );
    final descController = TextEditingController(
      text: taskToEdit?.description ?? '',
    );

    DateTime selectedDate = taskToEdit?.dateTime ?? DateTime.now();
    TimeOfDay selectedTime = taskToEdit != null
        ? TimeOfDay.fromDateTime(taskToEdit.dateTime)
        : TimeOfDay.now();
    bool isSmartReminder = taskToEdit?.isSmartReminder ?? false;

    String? errorMessage;

    // Helper to show error and auto-clear after 4 seconds
    void showError(String msg, StateSetter setDialogState) {
      setDialogState(() => errorMessage = msg);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setDialogState(() {
            if (errorMessage == msg)
              errorMessage = null; // Only clear if it hasn't been overwritten
          });
        }
      });
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: surfaceWhite, // Clean solid white background
              elevation: 0, // Absolutely flat, no shadow
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: textGrey.withOpacity(0.1),
                  width: 1,
                ), // Extremely subtle border instead of shadow
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? "Edit Task" : "New Task",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: textBlack,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Auto-dismissing Warning Message Box
                      if (errorMessage != null)
                        Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      errorMessage!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .animate()
                            .fadeIn(duration: 200.ms)
                            .slideY(begin: -0.1, end: 0, duration: 200.ms),

                      TextField(
                        controller: titleController,
                        style: TextStyle(
                          color: textBlack,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: "Task Title",
                          hintStyle: TextStyle(color: textGrey),
                          filled: true,
                          fillColor: backgroundGrey,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: backgroundGrey,
                                foregroundColor: textBlack,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: textGrey,
                              ),
                              label: Text(
                                "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2030),
                                );
                                if (date != null)
                                  setDialogState(() => selectedDate = date);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: backgroundGrey,
                                foregroundColor: textBlack,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: Icon(
                                Icons.access_time,
                                size: 16,
                                color: textGrey,
                              ),
                              label: Text(
                                selectedTime.format(context),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onPressed: () async {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: selectedTime,
                                );
                                if (time != null)
                                  setDialogState(() => selectedTime = time);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descController,
                        maxLines: 2,
                        maxLength: 40,
                        style: TextStyle(color: textBlack, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: "Short Description",
                          hintStyle: TextStyle(color: textGrey),
                          filled: true,
                          fillColor: backgroundGrey,
                          counterText: "",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundGrey,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Smart Reminder",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: textBlack,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "Get notified before",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFD4A33B),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: isSmartReminder,
                              activeColor: primaryYellow,
                              activeTrackColor: primaryYellow.withOpacity(0.5),
                              inactiveThumbColor: textGrey,
                              inactiveTrackColor: Colors.grey.shade300,
                              onChanged: (val) =>
                                  setDialogState(() => isSmartReminder = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              "Cancel",
                              style: TextStyle(
                                color: textGrey,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryYellow,
                              foregroundColor: textBlack,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              if (titleController.text.trim().isEmpty) {
                                showError(
                                  "Please enter a task title!",
                                  setDialogState,
                                );
                                return;
                              }

                              final newDateTime = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                selectedTime.hour,
                                selectedTime.minute,
                              );

                              if (newDateTime.isBefore(DateTime.now()) &&
                                  !isEditing) {
                                showError(
                                  "Cannot schedule tasks in the past!",
                                  setDialogState,
                                );
                                return;
                              }

                              setDialogState(() => errorMessage = null);

                              setState(() {
                                if (isEditing) {
                                  taskToEdit.title = titleController.text;
                                  taskToEdit.dateTime = newDateTime;
                                  taskToEdit.description = descController.text;
                                  taskToEdit.isSmartReminder = isSmartReminder;
                                } else {
                                  tasks.add(
                                    PlannerTask(
                                      id: DateTime.now().millisecondsSinceEpoch
                                          .toString(),
                                      title: titleController.text,
                                      dateTime: newDateTime,
                                      description: descController.text,
                                      isSmartReminder: isSmartReminder,
                                    ),
                                  );
                                }
                              });
                              Navigator.pop(context);
                            },
                            child: Text(
                              isEditing ? "Save" : "Add Task",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final groupedTasks = _getGroupedTasks();

    return Scaffold(
      backgroundColor: backgroundGrey,
      body: Stack(
        children: [
          // Reduced to exactly 4 distinct background bubbles to eliminate clutter
          Positioned(
            top: -60,
            right: -40,
            child: CircleAvatar(
              radius: 140,
              backgroundColor: primaryYellow.withOpacity(0.35),
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
              backgroundColor: primaryYellow.withOpacity(0.15),
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
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    children: groupedTasks.entries.map((entry) {
                      if (entry.value.isEmpty) return const SizedBox.shrink();
                      Color headerColor = textGrey;
                      if (entry.key == "Pending Tasks")
                        headerColor = Colors.redAccent;
                      if (entry.key == "Completed Tasks")
                        headerColor = Colors.green.shade700;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 18,
                              bottom: 8,
                              left: 4,
                            ),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: headerColor,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          ...entry.value
                              .map((task) => _buildTaskCard(task, entry.key))
                              .toList(),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              maxBlastForce: 20,
              minBlastForce: 10,
              colors: const [
                Color(0xFFFFD166),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start, // Aligns everything to the top
        children: [
          // Left Side: Titles
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Productivity",
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.w900,
                  color: textBlack,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                "Tracker",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: primaryYellow,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Manage your timeline",
                style: TextStyle(
                  fontSize: 13,
                  color: textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          
          // Right Side: Top Icons + Add Button Stacked
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 1. The Reusable Top Action Buttons (Notification & Profile)
              const TopActionButtons(unreadCount: 3), 
              
              const SizedBox(height: 18), // Spacing between top icons and add button
              
              // 2. The Add Task Button
              InkWell(
                onTap: () => _showTaskDialog(),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: primaryYellow,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryYellow.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.add, color: textBlack, size: 26),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(PlannerTask task, String category) {
    final isExpanded = expandedTaskId == task.id;
    final timeString = TimeOfDay.fromDateTime(task.dateTime).format(context);
    bool isPending = category == "Pending Tasks";

    Widget cardContent = GestureDetector(
      onTap: () {
        if (!task.isCompleted)
          setState(() => expandedTaskId = isExpanded ? null : task.id);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: task.isCompleted
                    ? surfaceWhite.withOpacity(0.5)
                    : surfaceWhite.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isPending
                      ? Colors.redAccent.withOpacity(0.5)
                      : Colors.white.withOpacity(0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleComplete(task),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 24,
                          width: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: task.isCompleted
                                ? Colors.green
                                : Colors.transparent,
                            border: Border.all(
                              color: task.isCompleted
                                  ? Colors.green
                                  : textGrey.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: task.isCompleted
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
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
                            color: task.isCompleted ? textGrey : textBlack,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Colors.black87,
                            decorationThickness: 2.5,
                          ),
                        ),
                      ),
                      Text(
                        timeString,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: isPending
                              ? Colors.redAccent
                              : (task.isCompleted
                                    ? textGrey
                                    : textBlack.withOpacity(0.8)),
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutQuart,
                    child: (isExpanded && !task.isCompleted)
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Divider(
                                color: textGrey.withOpacity(0.15),
                                height: 1,
                              ),
                              const SizedBox(height: 12),

                              if (task.isSmartReminder) ...[
                                Row(
                                  children: [
                                    Icon(
                                      Icons.bolt,
                                      color: primaryYellow,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Smart Reminder Active",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: textBlack,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],

                              if (task.description.isNotEmpty)
                                Text(
                                  task.description,
                                  style: TextStyle(
                                    color: textGrey,
                                    fontSize: 14,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),

                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _deleteTask(task),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      "Delete",
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: textBlack,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () =>
                                        _showTaskDialog(taskToEdit: task),
                                    icon: const Icon(Icons.edit, size: 14),
                                    label: const Text(
                                      "Edit",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
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

    if (task.isDeleting) {
      return cardContent
          .animate()
          .blurXY(begin: 0, end: 25, duration: 800.ms, curve: Curves.easeIn)
          .fadeOut(duration: 800.ms, curve: Curves.easeIn)
          .slideX(begin: 0, end: 0.3, duration: 800.ms, curve: Curves.easeIn)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.1, 1.1),
            duration: 800.ms,
          );
    }

    return cardContent;
  }
}

class TopActionButtons extends StatelessWidget {
  final int unreadCount;

  const TopActionButtons({super.key, this.unreadCount = 0});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // White Notification Bell
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SmartReminderScreen()),
            );
          },
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
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF1A1D20),
                  size: 24,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Yellow Dribbble-Shaped Profile Button
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD166),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD166).withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
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
