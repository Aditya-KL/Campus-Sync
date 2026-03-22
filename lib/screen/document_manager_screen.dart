// lib/screen/document_manager_screen.dart
//
// ── STORAGE ARCHITECTURE ─────────────────────────────────────
// NO local file storage.
// 1. User picks file (JPG/PNG from image_picker, PDF from file_picker)
// 2. CloudinaryService.uploadDocumentCard() → uploads to Cloudinary
// 3. Secure URL saved to Firestore: images/{uid}.{slot}
// 4. On screen open: CloudinaryService.fetchAllUrls(uid) restores all cards
//    from Firestore → works on any device, instant from cache.
//
// ── PUBSPEC ──────────────────────────────────────────────────
//   image_picker:                  ^1.0.0
//   file_picker:                   ^10.3.10
//   http:                          ^1.2.0  (inside cloudinary_service.dart)
//   syncfusion_flutter_pdfviewer:  ^28.1.39  ← PDF viewer
//
//   After adding syncfusion_flutter_pdfviewer, run:  flutter pub get
//
// ── FIREBASE ─────────────────────────────────────────────────
//   Firestore collection:  images/{uid}
//     id_card, fee_receipt, semester_marksheet, gate_qr: "https://..."
//     updatedAt: Timestamp

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dashboard_screen.dart';
import '../services/cloudinary_service.dart';

// ─────────────────────────────────────────────────────────────
// DOC CONFIG
// ─────────────────────────────────────────────────────────────
class _DocConfig {
  final String name, hint, slot;
  final IconData icon;
  final Color accent;
  const _DocConfig({
    required this.name, required this.icon, required this.accent,
    required this.hint, required this.slot,
  });
}

const List<_DocConfig> _docConfigs = [
  _DocConfig(name: 'ID Card',           icon: Icons.badge_rounded,
      accent: Color(0xFFFFD166), hint: 'Student identity card',  slot: 'id_card'),
  _DocConfig(name: 'Fee Receipt',        icon: Icons.receipt_long_rounded,
      accent: Color(0xFF4ECDC4), hint: 'Payment confirmation',   slot: 'fee_receipt'),
  _DocConfig(name: 'Semester Marksheet', icon: Icons.description_rounded,
      accent: Color(0xFFA78BFA), hint: 'Academic results',       slot: 'semester_marksheet'),
  _DocConfig(name: 'Gate QR',            icon: Icons.qr_code_2_rounded,
      accent: Color(0xFFFF6B6B), hint: 'Campus entry code',      slot: 'gate_qr'),
];

// ─────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────
class DocumentManagerScreen extends StatefulWidget {
  const DocumentManagerScreen({super.key});
  @override
  State<DocumentManagerScreen> createState() => _DocumentManagerScreenState();
}

class _DocumentManagerScreenState extends State<DocumentManagerScreen>
    with TickerProviderStateMixin {
  static const Color _yellow = Color(0xFFFFD166);
  static const Color _bg     = Color(0xFFF0F2F5);
  static const Color _ink    = Color(0xFF1A1D20);
  static const Color _muted  = Color(0xFF6C757D);
  static const Color _red    = Color(0xFFFF3B30);

  // slot → Cloudinary URL (null = not uploaded)
  Map<String, String?> _urls = { for (final d in _docConfigs) d.slot: null };
  // slot → upload progress 0.0..1.0 (null = idle)
  final Map<String, double?> _progress = {};
  bool _isLoading = true;

  late List<AnimationController> _cardCtrl;
  late List<Animation<double>>   _cardFade;
  late List<Animation<Offset>>   _cardSlide;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _cardCtrl = List.generate(_docConfigs.length, (i) =>
        AnimationController(vsync: this, duration: const Duration(milliseconds: 550)));
    _cardFade  = _cardCtrl.map((c) =>
        CurvedAnimation(parent: c, curve: Curves.easeOut)).toList();
    _cardSlide = _cardCtrl.map((c) =>
        Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic))).toList();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadUrls();
  }

  @override
  void dispose() {
    for (final c in _cardCtrl) c.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── fetch all URLs from Firestore on init ────────────────────
  Future<void> _loadUrls() async {
    if (_uid.isEmpty) { setState(() => _isLoading = false); return; }
    final fetched = await CloudinaryService().fetchAllUrls(_uid);
    if (!mounted) return;
    setState(() {
      for (final d in _docConfigs) _urls[d.slot] = fetched[d.slot];
      _isLoading = false;
    });
    for (int i = 0; i < _cardCtrl.length; i++) {
      Future.delayed(Duration(milliseconds: 80 * i), () {
        if (mounted) _cardCtrl[i].forward();
      });
    }
  }

  // ── file picker ──────────────────────────────────────────────
  // Shows Gallery / Camera / PDF choice, returns local temp path.
  Future<String?> _pickFile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          const Text('Choose source',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1D20))),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _srcBtn(Icons.photo_library_rounded,
                'Gallery', const Color(0xFF007AFF),
                () => Navigator.pop(context, 'gallery'))),
            const SizedBox(width: 10),
            Expanded(child: _srcBtn(Icons.camera_alt_rounded,
                'Camera', const Color(0xFFE5A91A),
                () => Navigator.pop(context, 'camera'))),
            const SizedBox(width: 10),
            Expanded(child: _srcBtn(Icons.picture_as_pdf_rounded,
                'PDF', _red,
                () => Navigator.pop(context, 'pdf'))),
          ]),
        ]),
      ),
    );
    if (choice == null) return null;
    if (choice == 'pdf') {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf'], withData: false);
      return result?.files.single.path;
    }
    final src    = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final picked = await ImagePicker().pickImage(
        source: src, imageQuality: 85, maxWidth: 1200, maxHeight: 1200);
    return picked?.path;
  }

  Widget _srcBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.25))),
          child: Column(children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      );

  // ── upload ───────────────────────────────────────────────────
  Future<void> _uploadDoc(_DocConfig doc) async {
    if (_uid.isEmpty) return;
    final path = await _pickFile();
    if (path == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _progress[doc.slot] = 0.0);
    try {
      final url = await CloudinaryService().uploadDocumentCard(
        userId: _uid, filePath: path, docName: doc.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress[doc.slot] = p);
        },
      );
      if (!mounted) return;

      // ── Dismiss the bottom sheet immediately when done ────────
      // Pop before setState so the sheet closes instantly without
      // the user having to tap anywhere.
      if (Navigator.canPop(context)) Navigator.pop(context);

      // Update state after dismissal so grid refreshes cleanly
      setState(() {
        _urls[doc.slot]      = url;
        _progress[doc.slot]  = null;
      });
      _showSnack('${doc.name} uploaded!', ok: true);

    } on CloudinaryUploadException catch (e) {
      if (mounted) {
        setState(() => _progress[doc.slot] = null);
        _showSnack(e.message, ok: false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _progress[doc.slot] = null);
        _showSnack('Upload failed. Try again.', ok: false);
      }
    }
  }

  // ── delete ───────────────────────────────────────────────────
  Future<void> _deleteDoc(_DocConfig doc) async {
    if (_uid.isEmpty) return;
    HapticFeedback.heavyImpact();
    await CloudinaryService().deleteUrl(_uid, doc.slot);
    if (!mounted) return;

    // Dismiss sheet immediately, then update grid
    if (Navigator.canPop(context)) Navigator.pop(context);
    setState(() => _urls[doc.slot] = null);
    _showSnack('${doc.name} removed.', ok: true);
  }

  void _showSnack(String msg, {required bool ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: ok ? const Color(0xFF34C759) : _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── view ─────────────────────────────────────────────────────
  void _openViewer(_DocConfig doc, String url) {
    if (CloudinaryService.isPdf(url)) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => _PdfViewer(url: url, docName: doc.name, accent: doc.accent)));
    } else {
      Navigator.push(context, PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: _ImageViewer(url: url, docName: doc.name, accent: doc.accent, slot: doc.slot),
        ),
      ));
    }
  }

  // ── bottom sheet ─────────────────────────────────────────────
  void _showDocSheet(_DocConfig doc) {
    final url  = _urls[doc.slot];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocSheet(
        doc: doc,
        url: url,
        progress: _progress[doc.slot],
        onUpload: () => _uploadDoc(doc),
        onDelete: () => _deleteDoc(doc),
        onView: url != null
            ? () { Navigator.pop(context); _openViewer(doc, url); }
            : null,
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Positioned(top: -60, right: -40, child: CircleAvatar(radius: 140,
            backgroundColor: _yellow.withOpacity(0.35))),
        Positioned(top: 150, left: -80, child: CircleAvatar(radius: 100,
            backgroundColor: const Color(0xFFE2E5E9))),
        Positioned(bottom: -30, right: -20, child: CircleAvatar(radius: 130,
            backgroundColor: _yellow.withOpacity(0.15))),
        Positioned(bottom: 100, left: 20, child: CircleAvatar(radius: 90,
            backgroundColor: const Color(0xFFD3D6DA))),
        SafeArea(
          bottom: false,
          child: Column(children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(
                      color: _yellow, strokeWidth: 2))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisSpacing: 16,
                              crossAxisSpacing: 16, childAspectRatio: 0.88),
                      physics: const BouncingScrollPhysics(),
                      itemCount: _docConfigs.length,
                      itemBuilder: (_, i) {
                        final doc = _docConfigs[i];
                        return FadeTransition(
                          opacity: _cardFade[i],
                          child: SlideTransition(
                            position: _cardSlide[i],
                            child: _DocCard(
                              doc: doc,
                              url: _urls[doc.slot],
                              progress: _progress[doc.slot],
                              pulseAnim: _pulseAnim,
                              onTap: () => _showDocSheet(doc),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    final saved = _urls.values.where((u) => u != null).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Important',
                style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900,
                    color: _ink, letterSpacing: -0.5)),
            const Text('Documents',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800,
                    color: _yellow)),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Container(
                key: ValueKey(saved),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: saved == _docConfigs.length
                      ? const Color(0xFF34C759).withOpacity(0.12)
                      : _yellow.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(saved == _docConfigs.length
                      ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 12,
                      color: saved == _docConfigs.length
                          ? const Color(0xFF34C759) : _muted),
                  const SizedBox(width: 4),
                  Text('$saved / ${_docConfigs.length} secured',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: saved == _docConfigs.length
                              ? const Color(0xFF34C759) : _muted)),
                ]),
              ),
            ),
          ]),
          const TopActionButtons(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DOC CARD
// ─────────────────────────────────────────────────────────────
class _DocCard extends StatefulWidget {
  final _DocConfig doc;
  final String? url;
  final double? progress;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;
  const _DocCard({required this.doc, required this.url, required this.progress,
      required this.pulseAnim, required this.onTap});
  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double>   _scale;
  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _press, curve: Curves.easeIn));
  }
  @override void dispose() { _press.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isSaved    = widget.url != null;
    final isPdf      = isSaved && CloudinaryService.isPdf(widget.url!);
    final isUploading = widget.progress != null;
    final accent     = widget.doc.accent;
    final thumbUrl   = isSaved && !isPdf
        ? CloudinaryService.optimiseUrl(widget.url!, width: 80)
        : null;

    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) { _press.reverse(); widget.onTap(); },
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedBuilder(
          animation: widget.pulseAnim,
          builder: (_, child) => Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: isSaved ? accent.withOpacity(0.35) : Colors.white,
                  width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04),
                    blurRadius: 12, offset: const Offset(0, 6)),
                if (isSaved)
                  BoxShadow(
                      color: accent.withOpacity(
                          0.12 + widget.pulseAnim.value * 0.14),
                      blurRadius: 20, spreadRadius: 2,
                      offset: const Offset(0, 4)),
              ],
            ),
            child: child,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Stack(children: [
              // background thumbnail
              if (thumbUrl != null)
                Positioned.fill(child: Opacity(opacity: 0.12,
                    child: Image.network(thumbUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()))),

              // top accent stripe
              Positioned(top: 0, left: 0, right: 0,
                  child: Container(height: 4,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [accent, accent.withOpacity(0.4)])))),

              // body
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(widget.doc.icon, color: accent, size: 28),
                  ),
                  const Spacer(),
                  Text(widget.doc.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1D20), letterSpacing: -0.2, height: 1.2)),
                  const SizedBox(height: 3),
                  Text(widget.doc.hint, style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w500,
                      color: Color(0xFF6C757D))),
                  const SizedBox(height: 10),

                  // status / progress
                  if (isUploading)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${((widget.progress ?? 0) * 100).toInt()}%',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                              color: accent)),
                      const SizedBox(height: 4),
                      ClipRRect(borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: widget.progress, minHeight: 4,
                            backgroundColor: accent.withOpacity(0.15),
                            valueColor: AlwaysStoppedAnimation(accent),
                          )),
                    ])
                  else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: isSaved ? accent.withOpacity(0.12)
                              : const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          isSaved ? (isPdf
                              ? Icons.picture_as_pdf_rounded
                              : Icons.check_circle_rounded)
                              : Icons.add_circle_outline_rounded,
                          size: 12,
                          color: isSaved ? accent : const Color(0xFF6C757D),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isSaved ? (isPdf ? 'PDF' : 'Secured') : 'Tap to add',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: isSaved ? accent : const Color(0xFF6C757D)),
                        ),
                      ]),
                    ),
                ]),
              ),

              // thumbnail badge
              if (thumbUrl != null)
                Positioned(top: 12, right: 12,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 6)]),
                      child: ClipRRect(borderRadius: BorderRadius.circular(8),
                          child: Image.network(thumbUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                  color: accent.withOpacity(0.2),
                                  child: Icon(widget.doc.icon,
                                      color: accent, size: 16)))),
                    )),

              // PDF badge
              if (isSaved && isPdf)
                Positioned(top: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFFF3B30).withOpacity(0.3))),
                      child: const Text('PDF', style: TextStyle(fontSize: 9,
                          fontWeight: FontWeight.w900, color: Color(0xFFFF3B30),
                          letterSpacing: 0.5)),
                    )),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTTOM SHEET
// ─────────────────────────────────────────────────────────────
class _DocSheet extends StatefulWidget {
  final _DocConfig doc;
  final String? url;
  final double? progress;
  final VoidCallback onUpload, onDelete;
  final VoidCallback? onView;
  const _DocSheet({required this.doc, required this.url, required this.progress,
      required this.onUpload, required this.onDelete, this.onView});
  @override State<_DocSheet> createState() => _DocSheetState();
}

class _DocSheetState extends State<_DocSheet> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isSaved    = widget.url != null;
    final isPdf      = isSaved && CloudinaryService.isPdf(widget.url!);
    final isUploading = widget.progress != null;
    final accent     = widget.doc.accent;

    Widget preview;
    if (isUploading) {
      preview = Container(
        height: 130, width: double.infinity,
        decoration: BoxDecoration(color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withOpacity(0.3))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(
              value: (widget.progress ?? 0) > 0.05 ? widget.progress : null,
              color: accent, strokeWidth: 3),
          const SizedBox(height: 12),
          Text('${((widget.progress ?? 0) * 100).toInt()}% uploading…',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
        ]),
      );
    } else if (isSaved && isPdf) {
      preview = GestureDetector(
        onTap: widget.onView,
        child: Container(
          height: 130, width: double.infinity,
          decoration: BoxDecoration(
              color: const Color(0xFFFF3B30).withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF3B30).withOpacity(0.25))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.picture_as_pdf_rounded,
                color: Color(0xFFFF3B30), size: 44),
            const SizedBox(height: 8),
            const Text('PDF Document', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1D20))),
            const SizedBox(height: 4),
            Text('Tap to open', style: TextStyle(
                fontSize: 11, color: const Color(0xFF6C757D).withOpacity(0.7),
                fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    } else if (isSaved) {
      preview = GestureDetector(
        onTap: widget.onView,
        child: Stack(alignment: Alignment.center, children: [
          Hero(
            tag: 'doc_${widget.doc.slot}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                CloudinaryService.optimiseUrl(widget.url!, width: 360),
                height: 190, width: double.infinity, fit: BoxFit.cover,
                loadingBuilder: (_, child, prog) => prog == null ? child
                    : Container(height: 190,
                        decoration: BoxDecoration(color: accent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16)),
                        child: Center(child: CircularProgressIndicator(
                            color: accent, strokeWidth: 2))),
                errorBuilder: (_, __, ___) => Container(height: 190,
                    decoration: BoxDecoration(color: accent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16)),
                    child: Center(child: Icon(Icons.broken_image_rounded,
                        color: accent.withOpacity(0.4), size: 40))),
              ),
            ),
          ),
          Container(height: 190, width: double.infinity,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.35)]))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
              SizedBox(width: 6),
              Text('View full screen', style: TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );
    } else {
      preview = GestureDetector(
        onTap: widget.onUpload,
        child: Container(
          height: 130, width: double.infinity,
          decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withOpacity(0.3), width: 1.5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: accent.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.cloud_upload_rounded, color: accent, size: 28),
            ),
            const SizedBox(height: 10),
            Text('Tap to upload', style: TextStyle(
                color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            const Text('JPG, PNG or PDF  •  Max 1 MB',
                style: TextStyle(color: Color(0xFF6C757D),
                    fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
    }

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),

            Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(widget.doc.icon, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.doc.name, style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1D20))),
                    Text(widget.doc.hint, style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6C757D),
                        fontWeight: FontWeight.w600)),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: isSaved ? accent.withOpacity(0.1)
                        : const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                  isSaved ? (isPdf ? 'PDF' : 'Secured') : 'Empty',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                      color: isSaved ? accent : const Color(0xFF6C757D)),
                ),
              ),
            ]),

            const SizedBox(height: 20),
            preview,
            const SizedBox(height: 20),

            if (!isUploading)
              Row(children: [
                Expanded(child: _Btn(
                  label: isSaved ? 'Delete' : 'Cancel',
                  icon:  isSaved ? Icons.delete_outline_rounded : Icons.close_rounded,
                  color: isSaved ? const Color(0xFFFF3B30) : const Color(0xFF6C757D),
                  filled: false,
                  onTap: isSaved ? widget.onDelete : () => Navigator.pop(context),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _Btn(
                  label: isSaved ? 'Update File' : 'Upload File',
                  icon:  isSaved ? Icons.upload_rounded : Icons.add_photo_alternate_rounded,
                  color: const Color(0xFF1A1D20),
                  filled: true,
                  onTap: widget.onUpload,
                )),
              ]),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ACTION BUTTON
// ─────────────────────────────────────────────────────────────
class _Btn extends StatefulWidget {
  final String label; final IconData icon;
  final Color color; final bool filled; final VoidCallback onTap;
  const _Btn({required this.label, required this.icon, required this.color,
      required this.filled, required this.onTap});
  @override State<_Btn> createState() => _BtnState();
}
class _BtnState extends State<_Btn> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _s;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _s = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => _c.forward(),
    onTapUp: (_) { _c.reverse(); widget.onTap(); },
    onTapCancel: () => _c.reverse(),
    child: ScaleTransition(scale: _s,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: widget.filled ? widget.color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: widget.filled ? null
              : Border.all(color: widget.color.withOpacity(0.4), width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(widget.icon, size: 16,
              color: widget.filled ? Colors.white : widget.color),
          const SizedBox(width: 6),
          Text(widget.label, style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w800,
              color: widget.filled ? Colors.white : widget.color)),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// FULL SCREEN IMAGE VIEWER
// ─────────────────────────────────────────────────────────────
class _ImageViewer extends StatelessWidget {
  final String url, docName, slot;
  final Color accent;
  const _ImageViewer({required this.url, required this.docName,
      required this.accent, required this.slot});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      backgroundColor: Colors.transparent, elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20)),
      ),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(docName, style: const TextStyle(color: Colors.white,
            fontSize: 16, fontWeight: FontWeight.w800)),
        Text('Pinch to zoom', style: TextStyle(color: Colors.white.withOpacity(0.6),
            fontSize: 11, fontWeight: FontWeight.w500)),
      ]),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: accent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.4))),
          child: Row(children: [
            Icon(Icons.lock_rounded, size: 12, color: accent),
            const SizedBox(width: 4),
            Text('Secured', style: TextStyle(
                color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
        ),
      ],
    ),
    body: Hero(
      tag: 'doc_$slot',
      child: InteractiveViewer(
        panEnabled: true,
        boundaryMargin: const EdgeInsets.all(24),
        minScale: 0.5, maxScale: 5.0,
        child: Center(child: Image.network(url,
            loadingBuilder: (_, child, prog) => prog == null ? child
                : const Center(child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)),
            errorBuilder: (_, __, ___) => const Center(child: Icon(
                Icons.broken_image_rounded, color: Colors.white54, size: 64)))),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// PDF VIEWER SCREEN  — full in-app rendering via Syncfusion
// Loads directly from the Cloudinary URL — no download needed.
// Features: scroll, pinch-to-zoom, page counter, search button.
// ─────────────────────────────────────────────────────────────
class _PdfViewer extends StatefulWidget {
  final String url;
  final String docName;
  final Color  accent;

  const _PdfViewer({
    required this.url,
    required this.docName,
    required this.accent,
  });

  @override
  State<_PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<_PdfViewer> {
  static const Color _ink   = Color(0xFF1A1D20);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _bg    = Color(0xFFF0F2F5);
  static const Color _red   = Color(0xFFFF3B30);

  final PdfViewerController         _pdfCtrl   = PdfViewerController();
  final TextEditingController       _searchCtrl = TextEditingController();

  // Incrementing this forces Flutter to rebuild SfPdfViewer from scratch
  // (equivalent to reload — SfPdfViewerState has no reload() method)
  int  _reloadKey  = 0;
  int  _currentPage = 1;
  int  _totalPages  = 0;
  bool _isLoading   = true;
  bool _hasError    = false;
  bool _showSearch  = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
                decoration: InputDecoration(
                  hintText:   'Search in PDF…',
                  hintStyle:  const TextStyle(color: _muted, fontSize: 13),
                  filled:     true,
                  fillColor:  _bg,
                  isDense:    true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onSubmitted: (text) {
                  if (text.isNotEmpty) {
                    _pdfCtrl.searchText(text);
                  }
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.docName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (_totalPages > 0)
                    Text('Page $_currentPage of $_totalPages',
                        style: const TextStyle(
                            fontSize: 11,
                            color: _muted,
                            fontWeight: FontWeight.w500)),
                ],
              ),
        actions: [
          // PDF badge
          if (!_showSearch)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('PDF',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _red)),
            ),

          // Search toggle
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
              color: _ink, size: 22,
            ),
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) {
                _searchCtrl.clear();
                _pdfCtrl.clearSelection();
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: Stack(
        children: [
          // ── PDF viewer ─────────────────────────────────────
          SfPdfViewer.network(
            widget.url,
            key:        ValueKey(_reloadKey),
            controller: _pdfCtrl,
            onDocumentLoaded: (details) {
              setState(() {
                _totalPages = details.document.pages.count;
                _isLoading  = false;
                _hasError   = false;
              });
            },
            onDocumentLoadFailed: (details) {
              setState(() {
                _isLoading = false;
                _hasError  = true;
              });
            },
            onPageChanged: (details) {
              setState(() => _currentPage = details.newPageNumber);
            },
            // Themed scroll indicator
            scrollDirection: PdfScrollDirection.vertical,
            pageLayoutMode:  PdfPageLayoutMode.continuous,
            canShowScrollStatus: true,
            canShowPageLoadingIndicator: true,
          ),

          // ── Loading overlay ────────────────────────────────
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                        color: widget.accent, strokeWidth: 3),
                    const SizedBox(height: 16),
                    const Text('Loading PDF…',
                        style: TextStyle(
                            fontSize: 13,
                            color: _muted,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),

          // ── Error state ────────────────────────────────────
          if (_hasError && !_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 56, color: _red),
                      const SizedBox(height: 16),
                      const Text('Failed to load PDF',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
                      const SizedBox(height: 8),
                      const Text(
                        'Check your internet connection\nand try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13,
                            color: _muted,
                            height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _hasError  = false;
                            _reloadKey++;   // new key → Flutter rebuilds SfPdfViewer fresh
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Page navigation bar (bottom) ───────────────────
          if (!_isLoading && !_hasError && _totalPages > 1)
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, -3))],
                ),
                child: Row(
                  children: [
                    // Prev
                    IconButton(
                      onPressed: _currentPage > 1
                          ? () => _pdfCtrl.previousPage()
                          : null,
                      icon: Icon(Icons.chevron_left_rounded,
                          color: _currentPage > 1 ? _ink : _muted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                    ),

                    // Page counter pill
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                              color: widget.accent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            '$_currentPage / $_totalPages',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: widget.accent ==
                                        const Color(0xFFFFD166)
                                    ? const Color(0xFF1A1D20)
                                    : widget.accent),
                          ),
                        ),
                      ),
                    ),

                    // Next
                    IconButton(
                      onPressed: _currentPage < _totalPages
                          ? () => _pdfCtrl.nextPage()
                          : null,
                      icon: Icon(Icons.chevron_right_rounded,
                          color: _currentPage < _totalPages
                              ? _ink : _muted),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}