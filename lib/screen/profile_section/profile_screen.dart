import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'edit_profile_screen.dart';
import 'app_guide_screen.dart';
import 'developers_screen.dart';
import '../auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color primaryYellow  = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite   = Colors.white;
  final Color textBlack      = const Color(0xFF1A1D20);
  final Color textGrey       = const Color(0xFF6C757D);

  bool   _isLoading = true;
  String userName   = "Loading...";
  String rollNo     = "";
  String branch     = "";
  String email      = "";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        email = user.email ?? "";
        final doc = await FirebaseFirestore.instance
            .collection('students')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache));

        if (doc.exists) {
          setState(() {
            userName = doc.data()?['name']   ?? "Student";
            rollNo   = doc.data()?['rollNo'] ?? "";
            branch   = doc.data()?['branch'] ?? "";
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

  String _getFullBranchName(String shortName) {
    if (shortName.isEmpty) return "Branch Not Set";
    final n = shortName.toLowerCase().trim();
    if (n == 'cse' || n.contains('cs'))  return "Computer Science & Engineering";
    if (n == 'ai')                        return "Artificial Intelligence";
    if (n == 'ece' || n.contains('ec'))  return "Electronics & Communication";
    if (n == 'eee' || n.contains('ee'))  return "Electrical & Electronics Engg.";
    if (n == 'mnc')                       return "Mathematics & Computing";
    if (n == 'me'  || n == 'mech')        return "Mechanical Engineering";
    if (n == 'cbe')                       return "Chemical & Bio Engineering";
    if (n == 'ct')                        return "Chemical Technology";
    if (n == 'eco')                       return "Economics";
    if (n == 'ep')                        return "Engineering Physics";
    if (n == 'mme')                       return "Metallurgical & Materials Engg.";
    if (n == 'ce'  || n == 'civil')       return "Civil Engineering";
    if (n.contains('it'))                 return "Information Technology";
    return shortName.toUpperCase();
  }

  String _calculateDegreeAndBatch(String roll) {
    if (roll.length < 4) return "Batch Unknown";
    final startYear  = 2000 + (int.tryParse(roll.substring(0, 2)) ?? 24);
    final degreeType = roll[2] == '1' ? "M.Tech" : "B.Tech";
    final courseCode = roll.substring(2, 4);
    final duration   = (courseCode == '02' || courseCode == '03')
        ? 5
        : (courseCode.startsWith('1') ? 2 : 4);
    return "$degreeType $startYear-${startYear + duration}";
  }

  Future<void> _openBugReportForm() async {
    final uri = Uri.parse('https://forms.gle/YOUR_FORM_LINK_HERE');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the form.')));
    }
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Logout",
            style: TextStyle(
                fontWeight: FontWeight.w900, color: textBlack, fontSize: 22)),
        content: Text("Are you sure you want to securely log out?",
            style: TextStyle(
                color: textGrey, fontWeight: FontWeight.w600, fontSize: 15)),
        actionsPadding:
            const EdgeInsets.only(bottom: 16, right: 20, left: 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel",
                style: TextStyle(
                    color: textGrey,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: textBlack,
              foregroundColor: primaryYellow,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthScreen()),
                (Route<dynamic> route) => false,
              );
              FirebaseAuth.instance.signOut();
            },
            child: const Text("Logout",
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CHANGE PASSWORD DIALOG
  // ─────────────────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final currentPassCtrl  = TextEditingController();
    final newPassCtrl      = TextEditingController();
    final confirmPassCtrl  = TextEditingController();

    bool showCurrent = false;
    bool showNew     = false;
    bool showConfirm = false;
    bool isLoading   = false;
    String? errorMsg;
    String? successMsg;

    showDialog(
      context: context,
      barrierDismissible: !isLoading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {

          // ── inline banner helper ──────────────────────────
          Widget banner(String msg, bool isSuccess) {
            final color = isSuccess
                ? const Color(0xFF34C759)
                : Colors.redAccent;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Row(children: [
                Icon(
                  isSuccess
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 15,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(msg,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ]),
            );
          }

          // ── password field builder ────────────────────────
          Widget passField(
            TextEditingController ctrl,
            String hint,
            bool visible,
            VoidCallback onToggle,
          ) {
            return Container(
              decoration: BoxDecoration(
                color: backgroundGrey,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFE9ECEF), width: 1),
              ),
              child: TextField(
                controller: ctrl,
                obscureText: !visible,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textBlack),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      TextStyle(color: textGrey.withOpacity(0.7), fontSize: 13),
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      size: 18, color: textGrey),
                  suffixIcon: GestureDetector(
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        visible
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 20,
                        color: textGrey,
                      ),
                    ),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  isDense: true,
                ),
              ),
            );
          }

          // ── submit handler ────────────────────────────────
          Future<void> submit() async {
            setDS(() {
              errorMsg   = null;
              successMsg = null;
            });

            final current = currentPassCtrl.text.trim();
            final newPass = newPassCtrl.text.trim();
            final confirm = confirmPassCtrl.text.trim();

            if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
              setDS(() => errorMsg = 'All fields are required.');
              return;
            }
            if (newPass.length < 6) {
              setDS(() =>
                  errorMsg = 'New password must be at least 6 characters.');
              return;
            }
            if (newPass != confirm) {
              setDS(() => errorMsg = 'New passwords do not match.');
              return;
            }
            if (current == newPass) {
              setDS(() =>
                  errorMsg = 'New password must differ from current.');
              return;
            }

            setDS(() => isLoading = true);
            try {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.email == null) {
                setDS(() {
                  errorMsg  = 'No authenticated user found.';
                  isLoading = false;
                });
                return;
              }

              // Re-authenticate first — required by Firebase before
              // sensitive operations like password change
              final cred = EmailAuthProvider.credential(
                  email: user.email!, password: current);
              await user.reauthenticateWithCredential(cred);

              // Now safe to update
              await user.updatePassword(newPass);

              setDS(() {
                successMsg = '✓ Password changed successfully!';
                isLoading  = false;
              });

              // Clear fields and auto-close after 1.5s
              currentPassCtrl.clear();
              newPassCtrl.clear();
              confirmPassCtrl.clear();
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted) Navigator.pop(ctx);
              });
            } on FirebaseAuthException catch (e) {
              String msg = 'Something went wrong. Try again.';
              if (e.code == 'wrong-password' ||
                  e.code == 'invalid-credential') {
                msg = 'Current password is incorrect.';
              } else if (e.code == 'too-many-requests') {
                msg = 'Too many attempts. Please wait a moment.';
              } else if (e.code == 'requires-recent-login') {
                msg = 'Please log out and log in again, then retry.';
              } else if (e.code == 'network-request-failed') {
                msg = 'No internet connection.';
              }
              setDS(() {
                errorMsg  = msg;
                isLoading = false;
              });
            } catch (e) {
              setDS(() {
                errorMsg  = 'Something went wrong. Please try again.';
                isLoading = false;
              });
            }
          }

          // ── dialog UI ─────────────────────────────────────
          return Dialog(
            backgroundColor: surfaceWhite,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: textGrey.withOpacity(0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── header ─────────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: primaryYellow.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.lock_reset_rounded,
                            color: const Color(0xFFD4A33B), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Change Password',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: textBlack)),
                          Text('Update your account password',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: textGrey)),
                        ],
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: isLoading ? null : () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: backgroundGrey,
                              shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: textBlack),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── banners ─────────────────────────────────
                  if (errorMsg   != null) banner(errorMsg!,   false),
                  if (successMsg != null) banner(successMsg!, true),

                  // ── current password ────────────────────────
                  Text('Current Password',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textGrey)),
                  const SizedBox(height: 6),
                  passField(
                    currentPassCtrl,
                    'Enter current password',
                    showCurrent,
                    () => setDS(() => showCurrent = !showCurrent),
                  ),

                  const SizedBox(height: 14),

                  // ── new password ────────────────────────────
                  Text('New Password',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textGrey)),
                  const SizedBox(height: 6),
                  passField(
                    newPassCtrl,
                    'Min. 6 characters',
                    showNew,
                    () => setDS(() => showNew = !showNew),
                  ),

                  const SizedBox(height: 14),

                  // ── confirm new password ────────────────────
                  Text('Confirm New Password',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textGrey)),
                  const SizedBox(height: 6),
                  passField(
                    confirmPassCtrl,
                    'Re-enter new password',
                    showConfirm,
                    () => setDS(() => showConfirm = !showConfirm),
                  ),

                  const SizedBox(height: 24),

                  // ── submit button ───────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: textBlack,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: isLoading ? null : submit,
                      child: isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Text('Update Password',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
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
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
              top: 250, right: -40,
              child: CircleAvatar(
                  radius: 140,
                  backgroundColor: primaryYellow.withOpacity(0.2))),
          Positioned(
              bottom: -30, right: -20,
              child: CircleAvatar(
                  radius: 130,
                  backgroundColor: primaryYellow.withOpacity(0.1))),

          if (_isLoading)
            Center(child: CircularProgressIndicator(color: primaryYellow))
          else
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── cover + avatar ──────────────────────────
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 200,
                        width: double.infinity,
                        color: textGrey.withOpacity(0.2),
                        child: Image.asset(
                          'assets/images/cover_pic.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.image, color: textGrey)),
                        ),
                      ),
                      Positioned(
                        bottom: -40, left: 24,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: backgroundGrey, shape: BoxShape.circle),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: primaryYellow,
                            child: Icon(Icons.person_rounded,
                                size: 50,
                                color: textBlack.withOpacity(0.7)),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 50),

                  // ── user info ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: textBlack,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: primaryYellow.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: primaryYellow.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.school_rounded,
                                  size: 16,
                                  color: const Color(0xFFD4A33B)),
                              const SizedBox(width: 8),
                              Text(_getFullBranchName(branch),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: textBlack)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "${_calculateDegreeAndBatch(rollNo)}  •  ${rollNo.toUpperCase()}",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textGrey),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.email_rounded,
                                size: 14, color: textGrey),
                            const SizedBox(width: 6),
                            Text(email,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: textGrey,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Account Settings ─────────────────
                        _buildSectionTitle("Account Settings"),
                        _buildMenuGroup([
                          _buildMenuItem(
                            icon: Icons.edit_rounded,
                            title: "Edit Profile",
                            onTap: () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const EditProfileScreen()));
                              setState(() => _isLoading = true);
                              _fetchUserData();
                            },
                          ),
                        ]),

                        const SizedBox(height: 24),

                        // ── Support & About ───────────────────
                        _buildSectionTitle("Support & About"),
                        _buildMenuGroup([
                          _buildMenuItem(
                            icon: Icons.menu_book_rounded,
                            title: "App Guide & FAQ",
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AppGuideScreen())),
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon: Icons.bug_report_rounded,
                            title: "Report a Bug",
                            onTap: _openBugReportForm,
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon: Icons.code_rounded,
                            title: "Meet the Developers",
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const DevelopersScreen())),
                          ),
                        ]),

                        const SizedBox(height: 24),

                        // ── Security + Logout group ───────────
                        _buildMenuGroup([
                          // ✅ Change Password — new entry
                          _buildMenuItem(
                            icon: Icons.lock_reset_rounded,
                            title: "Change Password",
                            onTap: _showChangePasswordDialog,
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon: Icons.logout_rounded,
                            title: "Logout",
                            textColor: Colors.redAccent,
                            iconColor: Colors.redAccent,
                            showChevron: false,
                            onTap: _handleLogout,
                          ),
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

  // ── menu helpers ─────────────────────────────────────────────
  Widget _buildSectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: textBlack)),
      );

  Widget _buildMenuGroup(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: surfaceWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(children: children),
      );

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? textColor,
    Color? iconColor,
    bool showChevron = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: (iconColor ?? primaryYellow).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon,
                    size: 20, color: iconColor ?? const Color(0xFFD4A33B)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor ?? textBlack)),
              ),
              if (showChevron)
                Icon(Icons.chevron_right_rounded,
                    color: textGrey.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() => Divider(
      height: 1,
      thickness: 1,
      color: backgroundGrey,
      indent: 64,
      endIndent: 20);
}