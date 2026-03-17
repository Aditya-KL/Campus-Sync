import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final Color primaryYellow = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite = Colors.white;
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _rollNoController = TextEditingController(); // Now Editable!
  
  bool _isLoading = true;
  bool _isSaving = false;
  String email = "";

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      email = user.email ?? "";
      final doc = await FirebaseFirestore.instance.collection('students').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          _nameController.text = doc.data()?['name'] ?? "";
          _phoneController.text = doc.data()?['phone'] ?? "";
          _rollNoController.text = doc.data()?['rollNo'] ?? "";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('students').doc(user.uid).update({
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'rollNo': _rollNoController.text.trim().toLowerCase(), // standardize roll no
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Updated!", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
          Navigator.pop(context); // Go back to profile screen
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error saving: $e"), backgroundColor: Colors.red));
      }
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGrey,
      appBar: AppBar(
        backgroundColor: backgroundGrey, elevation: 0, centerTitle: true,
        iconTheme: IconThemeData(color: textBlack),
        title: Text("Edit Profile", style: TextStyle(color: textBlack, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: primaryYellow))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(radius: 50, backgroundColor: primaryYellow, child: Icon(Icons.person, size: 50, color: textBlack.withOpacity(0.5))),
                      Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16))),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                _buildEditableField("Full Name", _nameController, Icons.person_outline_rounded),
                const SizedBox(height: 16),
                _buildEditableField("Phone Number", _phoneController, Icons.phone_outlined, keyboardType: TextInputType.phone),
                const SizedBox(height: 16),
                _buildEditableField("Roll Number", _rollNoController, Icons.badge_outlined),
                
                const SizedBox(height: 16),
                _buildReadOnlyField("College Email", email),

                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryYellow, foregroundColor: textBlack,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: _isSaving ? null : _saveChanges,
                    child: _isSaving 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Text("Save Changes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller, IconData icon, {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(fontWeight: FontWeight.w700, color: textBlack),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textGrey, fontWeight: FontWeight.w600),
        prefixIcon: Icon(icon, color: textBlack),
        filled: true,
        fillColor: surfaceWhite,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryYellow, width: 2)),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(color: surfaceWhite.withOpacity(0.5), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: textGrey, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value.isEmpty ? "No email found" : value, style: TextStyle(color: textBlack.withOpacity(0.5), fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}