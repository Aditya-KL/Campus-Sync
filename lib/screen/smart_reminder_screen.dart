import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:ui';
import 'profile_section/profile_screen.dart';

// --- Notification Types ---
enum ReminderType { task, attendance, library, admin }

class ReminderItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final ReminderType type;
  bool isRead;
  bool isDeleting;
  bool isTogglingRead;

  ReminderItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.type,
    this.isRead = false,
    this.isDeleting = false,
    this.isTogglingRead = false,
  });
}

class SmartReminderScreen extends StatefulWidget {
  const SmartReminderScreen({super.key});

  @override
  State<SmartReminderScreen> createState() => _SmartReminderScreenState();
}

class _SmartReminderScreenState extends State<SmartReminderScreen> {
  List<ReminderItem> notifications = [];

  // --- Theme Colors ---
  final Color primaryYellow = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite = Colors.white;
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);

  @override
  void initState() {
    super.initState();
    _loadMockData();
  }

  void _loadMockData() {
    final now = DateTime.now();
    notifications = [
      ReminderItem(
        id: '1',
        type: ReminderType.admin,
        title: "Campus Sync Update",
        message: "Firebase Storage maintenance scheduled for tonight at 11 PM.",
        timestamp: now.subtract(const Duration(minutes: 5)),
      ),
      ReminderItem(
        id: '2',
        type: ReminderType.task,
        title: "Upcoming Deadline",
        message:
            "Your C++ Assembler project is due in 2 hours. Don't forget to submit!",
        timestamp: now.subtract(const Duration(minutes: 45)),
      ),
      ReminderItem(
        id: '3',
        type: ReminderType.attendance,
        title: "Attendance Alert",
        message:
            "Warning: Your Computer Networks attendance has dropped to 72%.",
        timestamp: now.subtract(const Duration(hours: 3)),
      ),
      ReminderItem(
        id: '4',
        type: ReminderType.library,
        title: "Library Book Due",
        message:
            "'Data Structures and Algorithms' must be returned tomorrow to avoid fines.",
        timestamp: now.subtract(const Duration(days: 1)),
        isRead: true,
      ),
    ];
  }

  String _timeAgo(DateTime d) {
    Duration diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return "${(diff.inDays / 365).floor()}y ago";
    if (diff.inDays > 30) return "${(diff.inDays / 30).floor()}mo ago";
    if (diff.inDays > 0) return "${diff.inDays}d ago";
    if (diff.inHours > 0) return "${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
    return "Just now";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGrey,
      body: Stack(
        children: [
          // Clear, clean background bubbles
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
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      return _buildNotificationCard(notifications[index])
                          .animate()
                          .fade(duration: 400.ms, delay: (50 * index).ms)
                          .slideX(
                            begin: 0.1,
                            end: 0,
                            duration: 400.ms,
                            curve: Curves.easeOutCubic,
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Clean Modern Back Button
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceWhite,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Icon(Icons.arrow_back_ios_new_rounded, color: textBlack, size: 20),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text("Smart", style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: textBlack, letterSpacing: -0.5)),
                      const SizedBox(width: 6),
                      Text("Reminders", style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: primaryYellow)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text("Swipe left to toggle read, right to delete", style: TextStyle(fontSize: 12, color: textGrey, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          
          // Dribbble-Shaped, High-Contrast Profile Button
          InkWell(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(20),
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primaryYellow, // High contrast so it never camouflages
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(color: primaryYellow.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(20),
                ),
                // Note: If you add a real user profile picture later, 
                // replace this Center widget with Image.network(...)
                child: Center(
                  child: Icon(Icons.person_rounded, color: textBlack, size: 26),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildNotificationCard(ReminderItem item) {
    IconData icon;
    Color iconColor;
    Color iconBgColor;

    switch (item.type) {
      case ReminderType.task:
        icon = Icons.bolt_rounded;
        iconColor = const Color(0xFFD4A33B);
        iconBgColor = primaryYellow.withOpacity(0.2);
        break;
      case ReminderType.attendance:
        icon = Icons.warning_rounded;
        iconColor = Colors.redAccent;
        iconBgColor = Colors.redAccent.withOpacity(0.1);
        break;
      case ReminderType.library:
        icon = Icons.menu_book_rounded;
        iconColor = Colors.blueAccent;
        iconBgColor = Colors.blueAccent.withOpacity(0.1);
        break;
      case ReminderType.admin:
        icon = Icons.campaign_rounded;
        iconColor = textBlack;
        iconBgColor = textGrey.withOpacity(0.15);
        break;
    }

    Widget cardContent = Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: item.isRead ? Colors.white.withOpacity(0.4) : surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isRead ? Colors.transparent : Colors.white,
        ),
        boxShadow: [
          if (!item.isRead)
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: item.isRead
                              ? FontWeight.w700
                              : FontWeight.w900,
                          fontSize: 15,
                          color: textBlack,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(item.timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: item.isRead
                            ? textGrey.withOpacity(0.6)
                            : primaryYellow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: item.isRead ? textGrey : textBlack.withOpacity(0.8),
                    height: 1.4,
                    fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!item.isRead) ...[
            const SizedBox(width: 12),
            Container(
              margin: const EdgeInsets.only(top: 6),
              height: 10,
              width: 10,
              decoration: BoxDecoration(
                color: primaryYellow,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );

    // 1. Cool Read/Unread Animation (Pulse & Shimmer)
    if (item.isTogglingRead) {
      cardContent = cardContent
          .animate()
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.03, 1.03),
            duration: 200.ms,
            curve: Curves.easeOut,
          )
          .shimmer(duration: 400.ms, color: primaryYellow.withOpacity(0.5))
          .then()
          .scale(
            end: const Offset(1, 1),
            duration: 200.ms,
            curve: Curves.easeIn,
          );
    }

    // 2. The Thanos Snap Animation
    if (item.isDeleting) {
      return cardContent
          .animate()
          .blurXY(begin: 0, end: 20, duration: 800.ms, curve: Curves.easeIn)
          .fadeOut(duration: 800.ms, curve: Curves.easeIn)
          .slideX(begin: 0, end: 0.3, duration: 800.ms, curve: Curves.easeIn)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.1, 1.1),
            duration: 800.ms,
          );
    }

    // Wrap in Dismissible for Swipes
    return Dismissible(
      key: Key(item.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.delete_sweep_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: item.isRead ? textGrey.withOpacity(0.3) : primaryYellow,
          borderRadius: BorderRadius.circular(16),
        ),
        // Dynamic icon: if read, show the unread icon, and vice versa
        child: Icon(
          item.isRead
              ? Icons.mark_email_unread_rounded
              : Icons.mark_email_read_rounded,
          color: Colors.black87,
          size: 30,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // RIGHT SWIPE: Delete
          setState(() => item.isDeleting = true);
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) setState(() => notifications.remove(item));
          });
          return false;
        } else {
          // LEFT SWIPE: Toggle Read/Unread
          setState(() => item.isTogglingRead = true);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) {
              setState(() {
                item.isRead = !item.isRead; // Toggles the state
                item.isTogglingRead = false;
              });
            }
          });
          return false;
        }
      },
      child: cardContent,
    );
  }
}

// --- Stub for Profile Screen ---
// class ProfileScreen extends StatelessWidget {
//   const ProfileScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF0F2F5),
//       appBar: AppBar(
//         backgroundColor: Colors.transparent,
//         elevation: 0,
//         leading: IconButton(
//           icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black),
//           onPressed: () => Navigator.pop(context),
//         ),
//         title: const Text("Profile", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
//       ),
//       body: const Center(
//         child: Text("Profile Page Coming Soon...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
//       ),
//     );
//   }
// }
