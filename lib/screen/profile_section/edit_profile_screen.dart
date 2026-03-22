// lib/screen/profile_section/edit_profile_screen.dart
//
// What was added on top of the provided original:
//  • Branch dropdown (12 options, pre-filled from Firestore).
//  • Profile photo picker with preview dialog before upload.
//  • Cloudinary upload with progress ring on avatar.
//  • profilePhoto URL saved to Firestore on save.
//  • serverAndCache fetch so data is always fresh.
//  • Consistent styling with profile_screen.dart.
//  • All original functionality (name, phone, roll, email read-only) kept.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/cloudinary_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // ── palette ─────────────────────────────────────────────────
  final Color primaryYellow  = const Color(0xFFFFD166);
  final Color backgroundGrey = const Color(0xFFF0F2F5);
  final Color surfaceWhite   = Colors.white;
  final Color textBlack      = const Color(0xFF1A1D20);
  final Color textGrey       = const Color(0xFF6C757D);

  // ── all supported branches ──────────────────────────────────
  static const List<String> _branches = [
    'CSE', 'AI', 'CBE', 'CE', 'CST', 'ECE',
    'ECO', 'EEE', 'EP', 'ME', 'MME', 'MNC',
  ];

  // ── controllers ─────────────────────────────────────────────
  final TextEditingController _nameController   = TextEditingController();
  final TextEditingController _phoneController  = TextEditingController();
  final TextEditingController _rollNoController = TextEditingController();
  final TextEditingController _groupController  = TextEditingController();

  // ── state ────────────────────────────────────────────────────
  bool    _isLoading  = true;
  bool    _isSaving   = false;
  String  email       = '';
  String? _selectedBranch;
  String  _existingPhotoUrl = '';

  // Photo upload state
  File?   _pickedImageFile;
  bool    _isUploading    = false;
  double  _uploadProgress = 0.0;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _rollNoController.dispose();
    _groupController.dispose();
    super.dispose();
  }

  // ── load ─────────────────────────────────────────────────────
  Future<void> _loadCurrentData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    email = user.email ?? '';

    try {
      // serverAndCache guarantees fresh data including profilePhoto
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
        final d = doc.data()!;
        setState(() {
          _nameController.text   = d['name']         ?? '';
          _phoneController.text  = d['phone']         ?? '';
          // Roll number always stored/shown in UPPERCASE
          _rollNoController.text = (d['rollNo'] ?? '').toString().toUpperCase();
          _groupController.text  = (d['group']  ?? 1).toString();
          _selectedBranch        = d['branch']        as String?;
          _existingPhotoUrl      = d['profilePhoto']  ?? '';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // PHOTO FLOW  (same 2-step flow as profile_screen)
  // Step 1: source picker bottom sheet
  // Step 2: preview dialog — user taps "Use Photo" to confirm selection
  // Actual Cloudinary upload happens inside _saveChanges()
  // ─────────────────────────────────────────────────────────────

  void _showPhotoSourceSheet() {
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
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Text('Update Profile Photo',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: textBlack)),
            const SizedBox(height: 4),
            Text('Choose a source',
                style: TextStyle(
                    fontSize: 13, color: textGrey, fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _srcBtn(
                icon:  Icons.photo_library_rounded,
                label: 'Gallery',
                color: const Color(0xFF007AFF),
                onTap: () { Navigator.pop(context); _pickAndPreview(ImageSource.gallery); },
              )),
              const SizedBox(width: 14),
              Expanded(child: _srcBtn(
                icon:  Icons.camera_alt_rounded,
                label: 'Camera',
                color: const Color(0xFFE5A91A),
                onTap: () { Navigator.pop(context); _pickAndPreview(ImageSource.camera); },
              )),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _srcBtn({
    required IconData icon, required String label,
    required Color color, required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      );

  Future<void> _pickAndPreview(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1200, maxHeight: 1200);
    if (picked == null || !mounted) return;
    _showPreviewDialog(File(picked.path));
  }

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
              Row(children: [
                Text('Preview Photo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: textBlack)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: backgroundGrey, shape: BoxShape.circle),
                    child: Icon(Icons.close_rounded, size: 16, color: textBlack),
                  ),
                ),
              ]),
              const SizedBox(height: 18),

              // preview
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(imageFile,
                    width: double.infinity, height: 220, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
              Text('This photo will be uploaded when you tap "Save Changes".',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: textGrey, fontWeight: FontWeight.w500)),

              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textGrey,
                    side: BorderSide(color: textGrey.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: textBlack, foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Stage the file — actual upload happens in _saveChanges()
                    setState(() { _pickedImageFile = imageFile; _uploadError = null; });
                  },
                  child: const Text('Use Photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── save ─────────────────────────────────────────────────────
  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Name cannot be empty.', isError: true);
      return;
    }
    final parsedGroup = int.tryParse(_groupController.text.trim());
    if (parsedGroup == null || parsedGroup < 1 || parsedGroup > 24) {
      _showSnack('Group must be a number between 1 and 24.', isError: true);
      return;
    }

    setState(() { _isSaving = true; _uploadError = null; });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String photoUrl = _existingPhotoUrl;

      // Upload new photo if one was staged
      if (_pickedImageFile != null) {
        setState(() { _isUploading = true; _uploadProgress = 0.0; });
        try {
          photoUrl = await CloudinaryService().uploadProfilePicture(
            userId:   user.uid,
            filePath: _pickedImageFile!.path,
            onProgress: (p) {
              if (mounted) setState(() => _uploadProgress = p);
            },
          );
        } on CloudinaryUploadException catch (e) {
          setState(() {
            _uploadError = e.message;
            _isUploading = false;
            _isSaving    = false;
          });
          return;
        } finally {
          if (mounted) setState(() => _isUploading = false);
        }
      }

      // Write all fields to Firestore
      await FirebaseFirestore.instance
          .collection('students')
          .doc(user.uid)
          .update({
        'name':         _nameController.text.trim(),
        'phone':        _phoneController.text.trim(),
        // Always stored in UPPERCASE — consistent with display
        'rollNo':       _rollNoController.text.trim().toUpperCase(),
        'branch':       _selectedBranch,
        'group':        parsedGroup,
        'profilePhoto': photoUrl,
        'updatedAt':    FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnack('Profile updated!', isError: false);
        await Future.delayed(const Duration(milliseconds: 600));
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack('Error saving: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: isError ? Colors.red : const Color(0xFF34C759),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGrey,
      appBar: AppBar(
        backgroundColor: backgroundGrey,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textBlack),
        title: Text('Edit Profile',
            style: TextStyle(
                color: textBlack, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryYellow))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // ── Avatar with camera icon + progress ring ──
                  Center(
                    child: Stack(
                      children: [
                        // outer ring — grey border
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: backgroundGrey,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                  color: Colors.black.withOpacity(0.07),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4))]),
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(
                              color: primaryYellow,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(child: _buildAvatarImage()),
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

                        // camera badge
                        Positioned(
                          bottom: 2, right: 2,
                          child: GestureDetector(
                            onTap: _isUploading ? null : _showPhotoSourceSheet,
                            child: Container(
                              width: 30, height: 30,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: backgroundGrey, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // staged photo indicator
                  if (_pickedImageFile != null) ...[
                    const SizedBox(height: 8),
                    Text('New photo selected — will be uploaded on save.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            color: primaryYellow,
                            fontWeight: FontWeight.w600)),
                  ],

                  // upload error
                  if (_uploadError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(_uploadError!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],

                  const SizedBox(height: 36),

                  // ── Fields ──────────────────────────────────
                  _buildEditableField('Full Name',    _nameController,
                      Icons.person_outline_rounded),
                  const SizedBox(height: 16),
                  _buildEditableField('Phone Number', _phoneController,
                      Icons.phone_outlined,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 16),
                  // Roll number — auto-capitalised
                  _buildEditableField('Roll Number',  _rollNoController,
                      Icons.badge_outlined,
                      textCapitalization: TextCapitalization.characters),
                  const SizedBox(height: 16),
                  // Group — number 1–24
                  _buildEditableField('Group (1–24)', _groupController,
                      Icons.group_outlined,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 16),
                  // Branch dropdown
                  _buildBranchDropdown(),
                  const SizedBox(height: 16),
                  _buildReadOnlyField('College Email', email),

                  const SizedBox(height: 40),

                  // ── Save button ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryYellow,
                        foregroundColor: textBlack,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: (_isSaving || _isUploading) ? null : _saveChanges,
                      child: (_isSaving || _isUploading)
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 18, width: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _isUploading ? 'Uploading photo...' : 'Saving...',
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ],
                            )
                          : const Text('Save Changes',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Avatar: staged file → Cloudinary URL → default icon ─────
  Widget _buildAvatarImage() {
    if (_pickedImageFile != null) {
      return Image.file(_pickedImageFile!,
          width: 100, height: 100, fit: BoxFit.cover);
    }
    if (_existingPhotoUrl.isNotEmpty) {
      return Image.network(
        CloudinaryService.optimiseUrl(_existingPhotoUrl, width: 100),
        width: 100, height: 100, fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _defaultIcon(),
        errorBuilder: (_, __, ___) => _defaultIcon(),
      );
    }
    return _defaultIcon();
  }

  Widget _defaultIcon() => Icon(Icons.person,
      size: 50, color: textBlack.withOpacity(0.5));

  // ── Field builders ───────────────────────────────────────────
  Widget _buildEditableField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        style: TextStyle(fontWeight: FontWeight.w700, color: textBlack),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: textGrey, fontWeight: FontWeight.w600),
          prefixIcon: Icon(icon, color: textBlack),
          filled: true,
          fillColor: surfaceWhite,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: primaryYellow, width: 2)),
        ),
      );

  // Branch dropdown — NEW
  Widget _buildBranchDropdown() => DropdownButtonFormField<String>(
        value: _selectedBranch,
        hint: Text('Select Branch',
            style: TextStyle(color: textGrey, fontWeight: FontWeight.w600)),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: textBlack),
        dropdownColor: surfaceWhite,
        decoration: InputDecoration(
          labelText: 'Branch',
          labelStyle: TextStyle(color: textGrey, fontWeight: FontWeight.w600),
          prefixIcon: Icon(Icons.school_outlined, color: textBlack),
          filled: true,
          fillColor: surfaceWhite,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: primaryYellow, width: 2)),
        ),
        style: TextStyle(
            fontWeight: FontWeight.w700,
            color: textBlack,
            fontSize: 16),
        items: _branches
            .map((b) => DropdownMenuItem(value: b, child: Text(b)))
            .toList(),
        onChanged: (v) => setState(() => _selectedBranch = v),
      );

  Widget _buildReadOnlyField(String label, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            color: surfaceWhite.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    color: textGrey, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value.isEmpty ? 'No email found' : value,
                style: TextStyle(
                    color: textBlack.withOpacity(0.5),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}