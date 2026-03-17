import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import your navigation target screens
import 'smart_reminder_screen.dart';
import 'profile_section/profile_screen.dart';
import 'grade_calculator_screen.dart';
import 'planner_screen.dart';
import 'document_manager_screen.dart';
import 'timetable_attendance_screen.dart'; // Ensure this matches your file name

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  // Ordered exactly as you requested: Dashboard -> Timetable -> Grades -> Planner -> Docs
  final List<Widget> _pages = [
    const DashboardView(),
    const TimetableScreen(), 
    const GradeCalculatorScreen(),
    const PlannerScreen(),
    const DocumentManagerScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, 
      backgroundColor: const Color(0xFFF0F2F5), // Universal clean grey background
      
      // The parent shell ONLY renders the current page.
      body: _pages[_currentIndex],

      // Custom Glowing Navigation Island
      bottomNavigationBar: _buildGlowingIsland(),
    );
  }

  // --- CUSTOM "LIGHT SOURCE" FLOATING ISLAND ---
  Widget _buildGlowingIsland() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95), // Clean white theme
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 25, offset: const Offset(0, 10))
        ],
        border: Border.all(color: const Color(0xFF6C757D).withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem(Icons.dashboard_rounded, 0),
          _buildNavItem(Icons.event_note_rounded, 1), // Timetable
          _buildNavItem(Icons.analytics_rounded, 2),  // Grades
          _buildNavItem(Icons.calendar_today_rounded, 3), // Planner
          _buildNavItem(Icons.description_rounded, 4), // Docs
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index) {
    bool isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutQuart,
        padding: EdgeInsets.all(isSelected ? 14.0 : 10.0),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD166) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isSelected 
              ? [BoxShadow(color: const Color(0xFFFFD166).withOpacity(0.6), blurRadius: 15, spreadRadius: 2)] 
              : [],
        ),
        child: Icon(
          icon,
          color: isSelected ? const Color(0xFF1A1D20) : const Color(0xFF6C757D).withOpacity(0.6), 
          size: isSelected ? 26 : 24,
        ),
      ),
    );
  }
}

// --- ACTUAL DASHBOARD CONTENT VIEW ---
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  // Theme Colors
  final Color primaryYellow = const Color(0xFFFFD166);
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Stack(
      children: [
        // 1. Background Bubbles 
        Positioned(top: -60, right: -40, child: CircleAvatar(radius: 140, backgroundColor: primaryYellow.withOpacity(0.35))),
        Positioned(top: 150, left: -80, child: CircleAvatar(radius: 100, backgroundColor: const Color(0xFFE2E5E9))),
        Positioned(bottom: -30, right: -20, child: CircleAvatar(radius: 130, backgroundColor: primaryYellow.withOpacity(0.15))),
        Positioned(bottom: 100, left: 20, child: CircleAvatar(radius: 90, backgroundColor: const Color(0xFFD3D6DA))),
        
        // 2. Main Content
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Side: Welcome Text
                    Expanded(
                      child: FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('students').doc(user?.uid).get(),
                        builder: (context, snapshot) {
                          String firstName = "Student";
                          if (snapshot.hasData && snapshot.data!.exists) {
                            String fullName = snapshot.data!['name'] ?? "Student";
                            firstName = fullName.split(' ')[0]; 
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Welcome back,",
                                style: TextStyle(color: textGrey, fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                firstName,
                                style: TextStyle(
                                  color: textBlack,
                                  fontSize: 32, 
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Right Side: Using the newly extracted Reusable Buttons!
                    const TopActionButtons(unreadCount: 3),
                  ],
                ),
              ),
            ),

            // Quick Stats Grid
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 15, crossAxisSpacing: 15, childAspectRatio: 1.1,
                ),
                delegate: SliverChildListDelegate([
                  _statCard('Current GPA', '3.85', Icons.auto_graph_rounded, Colors.purpleAccent),
                  _statCard('Attendance', '88%', Icons.fact_check_rounded, Colors.greenAccent),
                  _statCard('Today\'s Classes', '4', Icons.school_rounded, Colors.orangeAccent),
                  _statCard('Library Items', '2', Icons.menu_book_rounded, Colors.blueAccent),
                ]),
              ),
            ),

            // Reminder Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Text("Smart Reminders", style: TextStyle(color: textBlack, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ),

            SliverList(
              delegate: SliverChildListDelegate([
                _reminderTile('System Design Quiz', '10:30 AM - Room 402', Icons.timer_rounded),
                _reminderTile('Submit Lab Report', 'Before 5:00 PM', Icons.upload_file_rounded),
                const SizedBox(height: 140), // Clearing the floating island
              ]),
            ),
          ],
        ),
      ],
    );
  }

  // --- REBUILT UI COMPONENTS ---
  Widget _statCard(String title, String val, IconData icon, Color col) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: col.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: col, size: 28),
          ),
          const SizedBox(height: 10),
          Text(val, style: TextStyle(color: textBlack, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(title, style: TextStyle(color: textGrey, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _reminderTile(String title, String sub, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8), 
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFFD166).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: const Color(0xFFD4A33B), size: 24), 
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: textBlack, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: textGrey, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          Icon(Icons.arrow_forward_ios_rounded, color: textGrey.withOpacity(0.5), size: 14),
        ],
      ),
    );
  }
}

// =====================================================================
// 🌟 REUSABLE WIDGET: Drop this in ANY file to get your top-right icons!
// =====================================================================
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
            Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartReminderScreen()));
          },
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded, color: Color(0xFF1A1D20), size: 24),
                if (unreadCount > 0)
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                      child: Text(
                        unreadCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1),
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
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          },
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD166), 
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(8),
                bottomLeft: Radius.circular(8), bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFFFFD166).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))
              ],
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF1A1D20), size: 26),
          ),
        ),
      ],
    );
  }
}