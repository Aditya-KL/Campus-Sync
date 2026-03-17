import 'package:flutter/material.dart';

class AppGuideScreen extends StatelessWidget {
  const AppGuideScreen({super.key});

  final Color primaryYellow = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color textBlack = const Color(0xFF1A1D20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGrey,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F2F5), // backgroundGrey
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1D20)), // textBlack
        title: const Text(
          "Title Here",
          style: TextStyle(
            color: Color(0xFF1A1D20),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        children: [
          // --- Campus Vault Section ---
          _buildSectionHeader(Icons.security_rounded, "Campus Vault"),
          _buildGuideCard(
            "How do I upload my ID Card or Gate QR?",
            "Navigate to the 'Campus Vault' tab. Tap on any empty document slot and select 'Upload File' to choose an image from your gallery. It must be under 1MB.",
          ),
          _buildGuideCard(
            "Can I update a document later?",
            "Yes! Just tap on any saved document and click 'Update File'. The old file will be automatically replaced in the cloud so your storage stays clean.",
          ),
          _buildGuideCard(
            "Are my documents safe?",
            "Absolutely. Only your account can access your uploaded files. They are securely linked to your unique college ID.",
          ),

          const SizedBox(height: 24),

          // --- Productivity Tracker Section ---
          _buildSectionHeader(
            Icons.check_circle_outline_rounded,
            "Productivity Tracker",
          ),
          _buildGuideCard(
            "How do I add a new task or assignment?",
            "Go to the 'Productivity Tracker' tab and tap the yellow '+' button at the top right. You can set the title, date, time, and a short description.",
          ),
          _buildGuideCard(
            "What is a 'Smart Reminder'?",
            "When creating a task, toggling on 'Smart Reminder' ensures the app will send you a push notification before your deadline so you never miss a submission or exam.",
          ),
          _buildGuideCard(
            "How do I mark a task as done?",
            "Simply tap the empty circle next to your task. It will strike through the text and move it to the 'Completed Tasks' section (and you'll get a little confetti celebration!).",
          ),

          const SizedBox(height: 24),

          // --- Timetable & General Section ---
          _buildSectionHeader(
            Icons.calendar_month_rounded,
            "General & Classes",
          ),
          _buildGuideCard(
            "How do I check my class schedule?",
            "Your daily timetable is located in the middle tab of the bottom navigation bar. It automatically syncs to your specific branch and batch.",
          ),
          _buildGuideCard(
            "I found a bug. What should I do?",
            "Go to your Profile (top right of the dashboard) and tap 'Report a Bug'. This will open a form where you can directly alert the developer team.",
          ),
        ],
      ),
    );
  }

  // Helper for Section Titles
  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: primaryYellow, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textBlack,
            ),
          ),
        ],
      ),
    );
  }

  // Helper for the Dropdown Cards
  Widget _buildGuideCard(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData().copyWith(
          dividerColor: Colors.transparent,
        ), // Removes the border line
        child: ExpansionTile(
          iconColor: primaryYellow,
          collapsedIconColor: textBlack,
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: textBlack,
              fontSize: 14,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                content,
                style: const TextStyle(
                  color: Color(0xFF6C757D),
                  height: 1.5,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
