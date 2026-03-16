import 'package:flutter/material.dart';

class GradeCalculatorScreen extends StatelessWidget {
  const GradeCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildInfoCard("Current CGPA", "3.85", Icons.trending_up),
        const SizedBox(height: 20),
        const Text("Semester Grades", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _buildGradeRow("Mathematics", "A"),
        _buildGradeRow("Data Structures", "A-"),
        _buildGradeRow("Digital Logic", "B+"),
        const SizedBox(height: 120), // Space for Floating Island
      ],
    );
  }

  Widget _buildInfoCard(String title, String val, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(width: 15),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white70)),
            Text(val, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ]),
        ],
      ),
    );
  }

  Widget _buildGradeRow(String subject, String grade) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(subject, style: const TextStyle(color: Colors.white)),
          Text(grade, style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}