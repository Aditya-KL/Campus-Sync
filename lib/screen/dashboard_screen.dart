import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Import your navigation target screens
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'grade_calculator_screen.dart';
import 'planner_screen.dart';
import 'document_manager_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  // The 4 main sections
  final List<Widget> _pages = [
    const DashboardView(),
    const GradeCalculatorScreen(),
    const PlannerScreen(),
    const DocumentManagerScreen(),
  ];

  // Dynamic Titles for the Top Bar
  final List<String> _titles = [
    'Dashboard',
    'Grade Scale',
    'Planner',
    'Important Documents',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Allows background to flow under the floating island
      backgroundColor: Colors.transparent,
      
      // --- RESTORED TOP BAR (Opacity 0.3 & Font Size 22) ---
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.black.withOpacity(0.3), 
        centerTitle: false,
        title: Text(
          _titles[_currentIndex], 
          style: const TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: 22, 
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, size: 30, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          const SizedBox(width: 10),
        ],
      ),

      // --- MAIN BODY WITH PERSISTENT BACKGROUND ---
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/background.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.4)),
          ),
          
          // Current Page Content
          _pages[_currentIndex],
        ],
      ),

      // --- FLOATING ISLAND NAVIGATION BAR ---
      bottomNavigationBar: _buildFloatingIsland(),
    );
  }

  Widget _buildFloatingIsland() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withOpacity(0.9), 
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))
        ],
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BottomNavigationBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: Colors.deepPurpleAccent,
          unselectedItemColor: Colors.white54,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics_rounded), label: 'Grades'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded), label: 'Planner'),
            BottomNavigationBarItem(icon: Icon(Icons.description_rounded), label: 'Documents'),
          ],
        ),
      ),
    );
  }
}

// --- ACTUAL DASHBOARD CONTENT VIEW ---
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // --- UPDATED PERSONALIZED HEADER ---
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 25, 24, 10),
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('students').doc(user?.uid).get(),
              builder: (context, snapshot) {
                String firstName = "Student";
                if (snapshot.hasData && snapshot.data!.exists) {
                  String fullName = snapshot.data!['name'] ?? "Student";
                  firstName = fullName.split(' ')[0]; 
                }
                return Text(
                  "Welcome back, $firstName",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28, 
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
        ),

        // Quick Stats Grid
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, 
              mainAxisSpacing: 15, 
              crossAxisSpacing: 15, 
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildListDelegate([
              _statCard('Current GPA', '3.85', Icons.auto_graph, Colors.purpleAccent),
              _statCard('Attendance', '88%', Icons.fact_check, Colors.greenAccent),
              _statCard('Today\'s Classes', '4', Icons.school, Colors.orangeAccent),
              _statCard('Library Items', '2', Icons.menu_book, Colors.blueAccent),
            ]),
          ),
        ),

        // Reminder Section
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: const Text(
              "Smart Reminders", 
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
            ),
          ),
        ),

        SliverList(
          delegate: SliverChildListDelegate([
            _reminderTile('System Design Quiz', '10:30 AM - Room 402', Icons.timer),
            _reminderTile('Submit Lab Report', 'Before 5:00 PM', Icons.upload_file),
            const SizedBox(height: 140), // Clearing the floating island
          ]),
        ),
      ],
    );
  }

  // --- UI COMPONENTS ---

  Widget _statCard(String title, String val, IconData icon, Color col) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: col, size: 30),
          const SizedBox(height: 10),
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _reminderTile(String title, String sub, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05), 
        borderRadius: BorderRadius.circular(20)
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
        ],
      ),
    );
  }
}