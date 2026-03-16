import 'package:flutter/material.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Upcoming Deadlines", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        _buildTaskItem("Project Submission", "March 20, 2026", true),
        _buildTaskItem("Mid-Term Exam", "March 25, 2026", false),
        _buildTaskItem("Lab Viva", "March 28, 2026", false),
        const SizedBox(height: 120),
      ],
    );
  }

  Widget _buildTaskItem(String task, String date, bool isUrgent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.redAccent.withOpacity(0.1) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isUrgent ? Colors.redAccent.withOpacity(0.3) : Colors.transparent),
      ),
      child: ListTile(
        leading: Icon(Icons.calendar_today, color: isUrgent ? Colors.redAccent : Colors.white70),
        title: Text(task, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(date, style: const TextStyle(color: Colors.white60)),
      ),
    );
  }
}