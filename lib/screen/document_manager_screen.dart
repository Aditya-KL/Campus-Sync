import 'package:flutter/material.dart';

class DocumentManagerScreen extends StatelessWidget {
  const DocumentManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
      crossAxisCount: 2,
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      children: [
        _buildDocCard("ID Card", Icons.badge),
        _buildDocCard("Fee Receipt", Icons.receipt_long),
        _buildDocCard("Semester Marksheet", Icons.description),
        _buildDocCard("Admit Card", Icons.assignment_ind),
      ],
    );
  }

  Widget _buildDocCard(String name, IconData icon) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.blueAccent, size: 40),
          const SizedBox(height: 10),
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}