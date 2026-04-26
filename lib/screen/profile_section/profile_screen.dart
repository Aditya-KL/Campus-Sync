// lib/screen/profile_section/profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'edit_profile_screen.dart';
import 'app_guide_screen.dart';
import 'meet_developers_screen.dart';
import 'developer_screen.dart';        // NEW
import '../auth_screen.dart';
import '../../services/cloudinary_service.dart'; // NEW

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // ── palette (unchanged from original) ───────────────────────
  final Color primaryYellow  = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite   = Colors.white;
  final Color textBlack      = const Color(0xFF1A1D20);
  final Color textGrey       = const Color(0xFF6C757D);

  // ── state ────────────────────────────────────────────────────
  bool   _isLoading   = true;
  String userName     = 'Loading...';
  String rollNo       = '';
  String branch       = '';
  String email        = '';
  String profilePhoto = '';   // NEW — Cloudinary URL from Firestore
  bool   isDeveloper  = false; // NEW — read from Firestore

  // Upload state
  bool   _isUploading    = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  // ── fetch ────────────────────────────────────────────────────
  Future<void> _fetchUserData() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        email = user.email ?? '';
        // Use serverAndCache so photo URL is always fresh after editing
        DocumentSnapshot<Map<String, dynamic>> doc;
        try {
          doc = await FirebaseFirestore.instance
              .collection('students')
              .doc(user.uid)
              .get(const GetOptions(source: Source.serverAndCache));
        } catch (_) {
          doc = await FirebaseFirestore.instance
              .collection('students')
              .doc(user.uid)
              .get(const GetOptions(source: Source.cache));
        }
        if (doc.exists) {
          setState(() {
            userName     = doc.data()?['name']         ?? 'Student';
            rollNo       = doc.data()?['rollNo']        ?? '';
            branch       = doc.data()?['branch']        ?? '';
            profilePhoto = doc.data()?['profilePhoto']  ?? '';   // NEW
            isDeveloper  = doc.data()?['isDeveloper']   == true; // NEW
            if (email.isEmpty) email = doc.data()?['email'] ?? '';
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // ── branch / batch helpers (unchanged) ──────────────────────
  String _getFullBranchName(String shortName) {
    if (shortName.isEmpty) return 'Branch Not Set';
    final n = shortName.toLowerCase().trim();
    if (n == 'cse')                       return 'Computer Science & Engineering';
    if (n == 'ai')                        return 'Artificial Intelligence';
    if (n == 'ece')                       return 'Electronics & Communication';
    if (n == 'eee' || n.contains('ee'))   return 'Electrical & Electronics Engg.';
    if (n == 'mnc')                       return 'Mathematics & Computing';
    if (n == 'me'  || n == 'mech')        return 'Mechanical Engineering';
    if (n == 'cbe')                       return 'Chemical & Bio Engineering';
    if (n == 'ct' || n == 'cst')          return 'Chemical Technology';
    if (n == 'eco')                       return 'Economics';
    if (n == 'ep'|| n == 'ph')            return 'Engineering Physics';
    if (n == 'mme')                       return 'Metallurgical & Materials Engg.';
    if (n == 'ce'  || n == 'civil')       return 'Civil Engineering';
    if (n.contains('it'))                 return 'Information Technology';
    return shortName.toUpperCase();
  }

  String _calculateDegreeAndBatch(String roll) {
    if (roll.length < 4) return 'Batch Unknown';
    final startYear  = 2000 + (int.tryParse(roll.substring(0, 2)) ?? 24);
    final String typeCode = roll.substring(4, 6).toUpperCase();
    final courseCode = roll.substring(2, 4);

    String degreeType;
    int duration;

    if ( typeCode == 'ES' || typeCode == 'PH') {
      degreeType = 'B.S';
      duration   = 4;
    } else if (courseCode == '1' || roll[2] == '1') {
      degreeType = 'M.Tech';
      duration   = 2;
    } else if (courseCode == '02' || courseCode == '03') {
      degreeType = 'B.Tech';
      duration   = 5;
    } else {
      degreeType = 'B.Tech';
      duration   = 4;
    }

    return '$degreeType $startYear–${startYear + duration}';
  }

  // ─────────────────────────────────────────────────────────────
  // FULL SCREEN IMAGE VIEWER (NEW)
  // ─────────────────────────────────────────────────────────────
  void _showFullImageView() {
    showDialog(
      context: context,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black.withOpacity(0.9),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(ctx),
          ),
          actions: [
            // Edit button so they can still change their photo
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showPhotoOptionsSheet();
              },
              icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
              label: const Text(
                'Edit',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.network(
              // You can optionally remove width constraints here if your service supports full res
              CloudinaryService.optimiseUrl(profilePhoto), 
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PHOTO UPLOAD FLOW
  // ─────────────────────────────────────────────────────────────

  // Step 1 — source picker bottom sheet
  void _showPhotoOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: surfaceWhite,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Text('Update Profile Photo',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: textBlack)),
            const SizedBox(height: 4),
            Text('Choose where to pick your photo',
                style: TextStyle(
                    fontSize: 13,
                    color: textGrey,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _sourceBtn(
                  icon:  Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: const Color(0xFF007AFF),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndPreview(ImageSource.gallery);
                  },
                )),
                const SizedBox(width: 14),
                Expanded(child: _sourceBtn(
                  icon:  Icons.camera_alt_rounded,
                  label: 'Camera',
                  color: const Color(0xFFE5A91A),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndPreview(ImageSource.camera);
                  },
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceBtn({
    required IconData icon,
    required String   label,
    required Color    color,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color:        color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border:       Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ]),
        ),
      );

  // Step 2 — pick image then show preview dialog
  Future<void> _pickAndPreview(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source:       source,
      imageQuality: 85,
      maxWidth:     1200,
      maxHeight:    1200,
    );
    if (picked == null || !mounted) return;
    _showPreviewDialog(File(picked.path));
  }

  // Step 2 — preview dialog with Upload / Cancel buttons
  void _showPreviewDialog(File imageFile) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: textGrey.withOpacity(0.1))),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // header
              Row(
                children: [
                  Text('Preview Photo',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: textBlack)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                          color: backgroundGrey, shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: textBlack),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // preview image — rounded square
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(
                  imageFile,
                  width:  double.infinity,
                  height: 240,
                  fit:    BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
              Text('Tap "Upload" to set this as your profile photo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      color: textGrey,
                      fontWeight: FontWeight.w500)),

              const SizedBox(height: 20),

              // action buttons
              Row(
                children: [
                  // Cancel
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textGrey,
                        side: BorderSide(color: textGrey.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Upload
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: textBlack,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx); // close preview
                        _uploadPhoto(imageFile);
                      },
                      child: const Text('Upload',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 3 — actual Cloudinary upload
  Future<void> _uploadPhoto(File imageFile) async {
    setState(() {
      _isUploading    = true;
      _uploadProgress = 0.0;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final url = await CloudinaryService().uploadProfilePicture(
        userId:   user.uid,
        filePath: imageFile.path,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      // Persist URL in Firestore
      await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .update({'profilePhoto': url});

      if (mounted) {
        setState(() => profilePhoto = url);
        _showSnack('Profile photo updated!', isError: false);
      }
    } on CloudinaryUploadException catch (e) {
      _showSnack(e.message, isError: true);
    } catch (_) {
      _showSnack('Upload failed. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor:
          isError ? Colors.redAccent : const Color(0xFF34C759),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // LOGOUT (unchanged from original)
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Logout',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: textBlack,
                fontSize: 22)),
        content: Text(
            'Are you sure you want to securely log out?',
            style: TextStyle(
                color: textGrey,
                fontWeight: FontWeight.w600,
                fontSize: 15)),
        actionsPadding:
            const EdgeInsets.only(bottom: 16, right: 20, left: 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
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
            child: const Text('Logout',
                style:
                    TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // CHANGE PASSWORD DIALOG (unchanged from original)
  // ─────────────────────────────────────────────────────────────
  void _showChangePasswordDialog() {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl     = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool showCurrent = false, showNew = false, showConfirm = false;
    bool isLoading   = false;
    String? errorMsg, successMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDS) {
        Widget banner(String msg, bool ok) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:  (ok ? const Color(0xFF34C759) : Colors.redAccent)
                .withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (ok ? const Color(0xFF34C759) : Colors.redAccent)
                    .withOpacity(0.2)),
          ),
          child: Row(children: [
            Icon(
              ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size:  15,
              color: ok ? const Color(0xFF34C759) : Colors.redAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ok
                          ? const Color(0xFF34C759)
                          : Colors.redAccent)),
            ),
          ]),
        );

        Widget passField(TextEditingController ctrl, String hint,
            bool visible, VoidCallback onToggle) =>
            Container(
              decoration: BoxDecoration(
                color: backgroundGrey,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE9ECEF)),
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
                        size: 20, color: textGrey,
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

        Future<void> submit() async {
          setDS(() { errorMsg = null; successMsg = null; });
          final cur = currentPassCtrl.text.trim();
          final nw  = newPassCtrl.text.trim();
          final cf  = confirmPassCtrl.text.trim();
          if (cur.isEmpty || nw.isEmpty || cf.isEmpty) {
            setDS(() => errorMsg = 'All fields are required.'); return;
          }
          if (nw.length < 6) {
            setDS(() => errorMsg = 'New password must be at least 6 characters.'); return;
          }
          if (nw != cf) {
            setDS(() => errorMsg = 'New passwords do not match.'); return;
          }
          if (cur == nw) {
            setDS(() => errorMsg = 'New password must differ from current.'); return;
          }
          setDS(() => isLoading = true);
          try {
            final user = FirebaseAuth.instance.currentUser!;
            final cred = EmailAuthProvider.credential(
                email: user.email!, password: cur);
            await user.reauthenticateWithCredential(cred);
            await user.updatePassword(nw);
            setDS(() { successMsg = '✓ Password changed!'; isLoading = false; });
            currentPassCtrl.clear(); newPassCtrl.clear(); confirmPassCtrl.clear();
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) Navigator.pop(ctx);
            });
          } on FirebaseAuthException catch (e) {
            String m = 'Something went wrong.';
            if (e.code == 'wrong-password' || e.code == 'invalid-credential')
              m = 'Current password is incorrect.';
            else if (e.code == 'too-many-requests')
              m = 'Too many attempts. Please wait.';
            else if (e.code == 'requires-recent-login')
              m = 'Log out and log in again first.';
            setDS(() { errorMsg = m; isLoading = false; });
          } catch (_) {
            setDS(() { errorMsg = 'Something went wrong.'; isLoading = false; });
          }
        }

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
                Row(children: [
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
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Change Password',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textBlack)),
                    Text('Update your account password',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textGrey)),
                  ]),
                  const Spacer(),
                  GestureDetector(
                    onTap: isLoading ? null : () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: backgroundGrey, shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, size: 16, color: textBlack),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                if (errorMsg   != null) banner(errorMsg!,  false),
                if (successMsg != null) banner(successMsg!, true),
                Text('Current Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textGrey)),
                const SizedBox(height: 6),
                passField(currentPassCtrl, 'Enter current password', showCurrent,
                    () => setDS(() => showCurrent = !showCurrent)),
                const SizedBox(height: 14),
                Text('New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textGrey)),
                const SizedBox(height: 6),
                passField(newPassCtrl, 'Min. 6 characters', showNew,
                    () => setDS(() => showNew = !showNew)),
                const SizedBox(height: 14),
                Text('Confirm New Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textGrey)),
                const SizedBox(height: 6),
                passField(confirmPassCtrl, 'Re-enter new password', showConfirm,
                    () => setDS(() => showConfirm = !showConfirm)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: textBlack, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: isLoading ? null : submit,
                    child: isLoading
                        ? const SizedBox(height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Update Password',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── bug report (unchanged) ───────────────────────────────────
  Future<void> _openBugReportForm() async {
    final uri = Uri.parse('https://forms.gle/oG2AvLWnFsPaix288');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the form.')));
    }
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
                      // cover image
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

                      // avatar — tappable, now opens view if image exists or sheet if empty
                      Positioned(
                        bottom: -44, left: 24,
                        child: GestureDetector(
                          onTap: _isUploading
                              ? null
                              : () {
                                  if (profilePhoto.isNotEmpty) {
                                    _showFullImageView(); // OPEN IMAGE
                                  } else {
                                    _showPhotoOptionsSheet(); // OPEN UPLOAD SHEET
                                  }
                                },
                          child: Stack(
                            children: [
                              // border ring
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                    color: backgroundGrey,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4))]),
                                child: Container(
                                  width: 90, height: 90,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: primaryYellow,
                                  ),
                                  child: ClipOval(child: _buildAvatar()),
                                ),
                              ),

                              // upload progress ring
                              if (_isUploading)
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: CircularProgressIndicator(
                                      value: _uploadProgress > 0.05
                                          ? _uploadProgress
                                          : null,
                                      strokeWidth: 3,
                                      color: primaryYellow,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 58),

                  // ── user info ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(userName,
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: textBlack,
                                  letterSpacing: -0.5)),
                          // DEV badge — only for developers
                          if (isDeveloper) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFA78BFA).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('DEV',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFA78BFA),
                                      letterSpacing: 0.5)),
                            ),
                          ],
                        ]),
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
                          '${_calculateDegreeAndBatch(rollNo)}  •  ${rollNo.toUpperCase()}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textGrey),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.email_rounded,
                              size: 14, color: textGrey),
                          const SizedBox(width: 6),
                          Text(email,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: textGrey,
                                  fontWeight: FontWeight.w600)),
                        ]),
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
                        _buildSectionTitle('Account Settings'),
                        _buildMenuGroup([
                          _buildMenuItem(
                            icon:  Icons.edit_rounded,
                            title: 'Edit Profile',
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
                        _buildSectionTitle('Support & About'),
                        _buildMenuGroup([
                          _buildMenuItem(
                            icon:  Icons.menu_book_rounded,
                            title: 'App Guide & FAQ',
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AppGuideScreen())),
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon:  Icons.bug_report_rounded,
                            title: 'Report a Bug',
                            onTap: _openBugReportForm,
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon:  Icons.code_rounded,
                            title: 'Meet the Developers',
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const DevelopersScreen())),
                          ),

                          // ── Developer Panel ──────────────────
                          if (isDeveloper) ...[
                            _buildDivider(),
                            _buildMenuItem(
                              icon:      Icons.admin_panel_settings_rounded,
                              title:     'Developer Panel',
                              iconColor: const Color(0xFFA78BFA),
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const DevelopersPage())),
                            ),
                          ],
                        ]),

                        const SizedBox(height: 24),

                        // ── Security + Logout ─────────────────
                        _buildMenuGroup([
                          _buildMenuItem(
                            icon:  Icons.lock_reset_rounded,
                            title: 'Change Password',
                            onTap: _showChangePasswordDialog,
                          ),
                          _buildDivider(),
                          _buildMenuItem(
                            icon:        Icons.logout_rounded,
                            title:       'Logout',
                            textColor:   Colors.redAccent,
                            iconColor:   Colors.redAccent,
                            showChevron: false,
                            onTap:       _handleLogout,
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

  // ── Avatar widget — shows network photo, upload overlay, or default ──
  Widget _buildAvatar() {
    if (profilePhoto.isNotEmpty) {
      return Image.network(
        CloudinaryService.optimiseUrl(profilePhoto, width: 90),
        width: 90, height: 90,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _defaultIcon(),
        errorBuilder: (_, __, ___) => _defaultIcon(),
      );
    }
    return _defaultIcon();
  }

  Widget _defaultIcon() => Icon(Icons.person_rounded,
      size: 50, color: textBlack.withOpacity(0.5));

  // ── Menu helpers (unchanged from original) ───────────────────
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
          boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4))],
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
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: (iconColor ?? primaryYellow).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon,
                    size: 20,
                    color: iconColor ?? const Color(0xFFD4A33B)),
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
            ]),
          ),
        ),
      );

  Widget _buildDivider() => Divider(
      height: 1,
      thickness: 1,
      color: backgroundGrey,
      indent: 64,
      endIndent: 20);
}