import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'edit_profile_screen.dart';
import 'app_guide_screen.dart';
import 'developers_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color primaryYellow = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite = Colors.white;
  final Color textBlack = const Color(0xFF1A1D20);
  final Color textGrey = const Color(0xFF6C757D);

  bool _isLoading = true;
  String userName = "Loading...";
  String rollNo = "";
  String branch = "";
  String email = "";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // --- Fetch Data ---
  Future<void> _fetchUserData() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        email = user.email ?? "";
        final doc = await FirebaseFirestore.instance.collection('students').doc(user.uid).get();
        
        if (doc.exists) {
          setState(() {
            userName = doc.data()?['name'] ?? "Student";
            rollNo = doc.data()?['rollNo'] ?? "";
            branch = doc.data()?['branch'] ?? "";
            if (email.isEmpty) email = doc.data()?['email'] ?? "";
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // --- Smart Formatting Logic ---
  String _getFullBranchName(String shortName) {
    if (shortName.isEmpty) return "Branch Not Set";
    String normalized = shortName.toLowerCase().trim();
    if (normalized.contains('cs') || normalized == 'cse') return "Computer Science & Engineering";
    if (normalized.contains('ec') || normalized == 'ece') return "Electronics & Communication";
    if (normalized.contains('ee') || normalized == 'eee') return "Electrical Engineering";
    if (normalized.contains('me') || normalized == 'mech') return "Mechanical Engineering";
    if (normalized.contains('ce') || normalized == 'civil') return "Civil Engineering";
    if (normalized.contains('it')) return "Information Technology";
    return shortName.toUpperCase();
  }

  String _calculateDegreeAndBatch(String roll) {
    if (roll.length < 4) return "Batch Unknown";
    int startYear = 2000 + (int.tryParse(roll.substring(0, 2)) ?? 24);
    String degreeType = roll[2] == '1' ? "M.Tech" : "B.Tech";
    String courseCode = roll.substring(2, 4);
    int duration = (courseCode == '02' || courseCode == '03') ? 5 : (courseCode.startsWith('1') ? 2 : 4);
    return "$degreeType $startYear-${startYear + duration}";
  }

  // --- Actions ---
  Future<void> _openBugReportForm() async {
    final Uri url = Uri.parse('https://forms.gle/YOUR_FORM_LINK_HERE'); 
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the form.')));
    }
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w900)),
        content: const Text("Are you sure you want to securely log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: textGrey, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, elevation: 0),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                // This routes the user all the way back to the first screen (Login)
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            child: const Text("Logout", style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGrey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(top: 250, right: -40, child: CircleAvatar(radius: 140, backgroundColor: primaryYellow.withOpacity(0.2))),
          Positioned(bottom: -30, right: -20, child: CircleAvatar(radius: 130, backgroundColor: primaryYellow.withOpacity(0.1))),
          
          if (_isLoading)
            Center(child: CircularProgressIndicator(color: primaryYellow))
          else
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Images
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 200, width: double.infinity,
                        color: textGrey.withOpacity(0.2),
                        child: Image.asset('assets/images/cover_pic.jpg', fit: BoxFit.cover, errorBuilder: (_,__,___) => Center(child: Icon(Icons.image, color: textGrey))),
                      ),
                      Positioned(
                        bottom: -40, left: 24,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: backgroundGrey, shape: BoxShape.circle),
                          child: CircleAvatar(radius: 46, backgroundColor: primaryYellow, child: Icon(Icons.person_rounded, size: 50, color: textBlack.withOpacity(0.7))),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 50),

                  // User Info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textBlack, letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        
                        // YELLOW BOX ON BRANCH FULL NAME
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: primaryYellow.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: primaryYellow.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school_rounded, size: 16, color: const Color(0xFFD4A33B)),
                              const SizedBox(width: 8),
                              Text(_getFullBranchName(branch), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textBlack)),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        Text("${_calculateDegreeAndBatch(rollNo)}  •  ${rollNo.toUpperCase()}", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textGrey)),
                        
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.email_rounded, size: 14, color: textGrey),
                            const SizedBox(width: 6),
                            Text(email, style: TextStyle(fontSize: 14, color: textGrey, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Menus
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle("Account Settings"),
                        _buildMenuGroup([
                          _buildMenuItem(
                            icon: Icons.edit_rounded, title: "Edit Profile", 
                            onTap: () async {
                              // Wait for edit screen to pop, then refresh data
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                              setState(() => _isLoading = true);
                              _fetchUserData();
                            },
                          ),
                        ]),

                        const SizedBox(height: 24),
                        
                        _buildSectionTitle("Support & About"),
                        _buildMenuGroup([
                          _buildMenuItem(icon: Icons.menu_book_rounded, title: "App Guide & FAQ", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppGuideScreen()))),
                          _buildDivider(),
                          _buildMenuItem(icon: Icons.bug_report_rounded, title: "Report a Bug", onTap: _openBugReportForm),
                          _buildDivider(),
                          _buildMenuItem(icon: Icons.code_rounded, title: "Meet the Developers", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevelopersScreen()))),
                        ]),

                        const SizedBox(height: 24),

                        _buildMenuGroup([
                          _buildMenuItem(icon: Icons.logout_rounded, title: "Logout", textColor: Colors.redAccent, iconColor: Colors.redAccent, showChevron: false, onTap: _handleLogout),
                        ]),
                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(padding: const EdgeInsets.only(left: 4, bottom: 10), child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textBlack)));
  Widget _buildMenuGroup(List<Widget> children) => Container(decoration: BoxDecoration(color: surfaceWhite, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]), child: Column(children: children));
  Widget _buildMenuItem({required IconData icon, required String title, required VoidCallback onTap, Color? textColor, Color? iconColor, bool showChevron = true}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: (iconColor ?? primaryYellow).withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 20, color: iconColor ?? const Color(0xFFD4A33B))),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor ?? textBlack))),
              if (showChevron) Icon(Icons.chevron_right_rounded, color: textGrey.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildDivider() => Divider(height: 1, thickness: 1, color: backgroundGrey, indent: 64, endIndent: 20);
}