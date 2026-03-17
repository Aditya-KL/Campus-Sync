import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────
// DOC CONFIG  — icon, label, accent color per document type
// ─────────────────────────────────────────────────────────────
class _DocConfig {
  final String name;
  final IconData icon;
  final Color accent;
  final String hint;
  const _DocConfig({
    required this.name,
    required this.icon,
    required this.accent,
    required this.hint,
  });
}

const List<_DocConfig> _docConfigs = [
  _DocConfig(
    name: 'ID Card',
    icon: Icons.badge_rounded,
    accent: Color(0xFFFFD166),
    hint: 'Student identity card',
  ),
  _DocConfig(
    name: 'Fee Receipt',
    icon: Icons.receipt_long_rounded,
    accent: Color(0xFF4ECDC4),
    hint: 'Payment confirmation',
  ),
  _DocConfig(
    name: 'Semester Marksheet',
    icon: Icons.description_rounded,
    accent: Color(0xFFA78BFA),
    hint: 'Academic results',
  ),
  _DocConfig(
    name: 'Gate QR',
    icon: Icons.qr_code_2_rounded,
    accent: Color(0xFFFF6B6B),
    hint: 'Campus entry code',
  ),
];

// ─────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────
class DocumentManagerScreen extends StatefulWidget {
  const DocumentManagerScreen({super.key});

  @override
  State<DocumentManagerScreen> createState() =>
      _DocumentManagerScreenState();
}

class _DocumentManagerScreenState extends State<DocumentManagerScreen>
    with TickerProviderStateMixin {
  // ── palette ────────────────────────────────────────────────
  static const Color _yellow = Color(0xFFFFD166);
  static const Color _bg     = Color(0xFFF0F2F5);
  static const Color _ink    = Color(0xFF1A1D20);
  static const Color _muted  = Color(0xFF6C757D);

  // ── state ──────────────────────────────────────────────────
  Map<String, String?> _savedPaths = {
    for (final d in _docConfigs) d.name: null
  };

  // ── animation controllers — one per card ───────────────────
  late List<AnimationController> _cardControllers;
  late List<Animation<double>>   _cardFades;
  late List<Animation<Offset>>   _cardSlides;

  // ── glow pulse (for saved cards) ───────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();

    // staggered entrance — one controller per card
    _cardControllers = List.generate(_docConfigs.length, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 550),
      );
    });
    _cardFades = _cardControllers.map((c) =>
        CurvedAnimation(parent: c, curve: Curves.easeOut)).toList();
    _cardSlides = _cardControllers.map((c) =>
        Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic))
        ).toList();

    // pulse for saved cards
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _loadSavedDocuments();
  }

  void _startStaggeredAnimations() {
    for (int i = 0; i < _cardControllers.length; i++) {
      Future.delayed(Duration(milliseconds: 80 * i), () {
        if (mounted) _cardControllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _cardControllers) c.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── data ───────────────────────────────────────────────────
  Future<void> _loadSavedDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (final d in _docConfigs) {
        _savedPaths[d.name] = prefs.getString(d.name);
      }
    });
    _startStaggeredAnimations();
  }

  Future<void> _pickAndSaveImage(String docName) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    HapticFeedback.mediumImpact();

    final dir = await getApplicationDocumentsDirectory();
    final slug = docName.replaceAll(' ', '_').toLowerCase();

    // delete old
    final old = _savedPaths[docName];
    if (old != null) {
      final f = File(old);
      if (await f.exists()) await f.delete();
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final newPath = '${dir.path}/${slug}_$ts.jpg';
    final saved = await File(picked.path).copy(newPath);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(docName, saved.path);

    setState(() => _savedPaths[docName] = saved.path);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteImage(String docName) async {
    HapticFeedback.heavyImpact();
    final old = _savedPaths[docName];
    if (old != null) {
      final f = File(old);
      if (await f.exists()) await f.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(docName);
    setState(() => _savedPaths[docName] = null);
    if (mounted) Navigator.pop(context);
  }

  // ── full-screen viewer ─────────────────────────────────────
  void _viewFullScreen(String filePath, String docName, Color accent) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: _FullScreenViewer(
              filePath: filePath, docName: docName, accent: accent),
        ),
      ),
    );
  }

  // ── dialog ─────────────────────────────────────────────────
  void _showDocDialog(_DocConfig doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocBottomSheet(
        doc: doc,
        filePath: _savedPaths[doc.name],
        onUpload: () => _pickAndSaveImage(doc.name),
        onDelete: () => _deleteImage(doc.name),
        onView: () {
          final p = _savedPaths[doc.name];
          if (p != null) {
            Navigator.pop(context);
            _viewFullScreen(p, doc.name, doc.accent);
          }
        },
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // background bubbles — original theme
          Positioned(top: -60, right: -40,
              child: CircleAvatar(radius: 140,
                  backgroundColor: _yellow.withOpacity(0.35))),
          Positioned(top: 150, left: -80,
              child: CircleAvatar(radius: 100,
                  backgroundColor: const Color(0xFFE2E5E9))),
          Positioned(bottom: -30, right: -20,
              child: CircleAvatar(radius: 130,
                  backgroundColor: _yellow.withOpacity(0.15))),
          Positioned(bottom: 100, left: 20,
              child: CircleAvatar(radius: 90,
                  backgroundColor: const Color(0xFFD3D6DA))),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.88,
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _docConfigs.length,
                    itemBuilder: (_, i) {
                      final doc = _docConfigs[i];
                      final path = _savedPaths[doc.name];
                      return FadeTransition(
                        opacity: _cardFades[i],
                        child: SlideTransition(
                          position: _cardSlides[i],
                          child: _DocCard(
                            doc: doc,
                            filePath: path,
                            pulseAnim: _pulseAnim,
                            onTap: () => _showDocDialog(doc),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final savedCount =
        _savedPaths.values.where((p) => p != null).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Important',
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                      letterSpacing: -0.5)),
              Text('Documents',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _yellow)),
              const SizedBox(height: 8),
              // live vault status pill
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(savedCount),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: savedCount == _docConfigs.length
                        ? const Color(0xFF34C759).withOpacity(0.12)
                        : _yellow.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        savedCount == _docConfigs.length
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        size: 12,
                        color: savedCount == _docConfigs.length
                            ? const Color(0xFF34C759)
                            : _muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$savedCount / ${_docConfigs.length} secured',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: savedCount == _docConfigs.length
                                ? const Color(0xFF34C759)
                                : _muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const TopActionButtons(unreadCount: 3),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DOC CARD  — thumbnail preview + staggered enter + pulse glow
// ─────────────────────────────────────────────────────────────
class _DocCard extends StatefulWidget {
  final _DocConfig doc;
  final String? filePath;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  const _DocCard({
    required this.doc,
    required this.filePath,
    required this.pulseAnim,
    required this.onTap,
  });

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _pressScale = Tween<double>(begin: 1.0, end: 0.94)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = widget.filePath != null;
    final accent = widget.doc.accent;

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _pressScale,
        child: AnimatedBuilder(
          animation: widget.pulseAnim,
          builder: (_, child) {
            final glowOpacity = isSaved
                ? 0.12 + widget.pulseAnim.value * 0.14
                : 0.0;
            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: isSaved
                        ? accent.withOpacity(0.35)
                        : Colors.white,
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 6)),
                  if (isSaved)
                    BoxShadow(
                        color: accent.withOpacity(glowOpacity),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 4)),
                ],
              ),
              child: child,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Stack(
              children: [
                // ── thumbnail background (if saved) ──────
                if (isSaved)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.12,
                      child: Image.file(
                        File(widget.filePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                // ── accent top stripe ─────────────────────
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        accent,
                        accent.withOpacity(0.4),
                      ]),
                    ),
                  ),
                ),

                // ── card body ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // icon container
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(widget.doc.icon,
                            color: accent, size: 28),
                      ),
                      const Spacer(),
                      // doc name
                      Text(widget.doc.name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1D20),
                              letterSpacing: -0.2,
                              height: 1.2)),
                      const SizedBox(height: 3),
                      // hint
                      Text(widget.doc.hint,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF6C757D))),
                      const SizedBox(height: 10),
                      // status bar
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSaved
                              ? accent.withOpacity(0.12)
                              : const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Icon(
                                isSaved
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                key: ValueKey(isSaved),
                                size: 12,
                                color: isSaved
                                    ? accent
                                    : const Color(0xFF6C757D),
                              ),
                            ),
                            const SizedBox(width: 4),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                isSaved ? 'Secured' : 'Tap to add',
                                key: ValueKey(isSaved),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSaved
                                        ? accent
                                        : const Color(0xFF6C757D)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── thumbnail preview badge (top-right) ───
                if (isSaved)
                  Positioned(
                    top: 12, right: 12,
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 6)
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(widget.filePath!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// BOTTOM SHEET  — premium slide-up doc action sheet
// ─────────────────────────────────────────────────────────────
class _DocBottomSheet extends StatefulWidget {
  final _DocConfig doc;
  final String? filePath;
  final VoidCallback onUpload;
  final VoidCallback onDelete;
  final VoidCallback onView;

  const _DocBottomSheet({
    required this.doc,
    required this.filePath,
    required this.onUpload,
    required this.onDelete,
    required this.onView,
  });

  @override
  State<_DocBottomSheet> createState() => _DocBottomSheetState();
}

class _DocBottomSheetState extends State<_DocBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
            begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = widget.filePath != null;
    final accent = widget.doc.accent;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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

              // ── header row ──────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.doc.icon, color: accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.doc.name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1A1D20))),
                        const SizedBox(height: 2),
                        Text(widget.doc.hint,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6C757D),
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  // status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSaved
                          ? accent.withOpacity(0.1)
                          : const Color(0xFFF0F2F5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isSaved ? 'Secured' : 'Empty',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isSaved ? accent : const Color(0xFF6C757D)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── image preview / upload placeholder ──────
              if (isSaved)
                GestureDetector(
                  onTap: widget.onView,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Hero(
                        tag: 'doc_${widget.doc.name}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(widget.filePath!),
                            height: 190,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      // dark overlay
                      Container(
                        height: 190,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.35),
                            ],
                          ),
                        ),
                      ),
                      // zoom hint
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in_rounded,
                                color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text('View full screen',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                // upload drop zone
                GestureDetector(
                  onTap: widget.onUpload,
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: accent.withOpacity(0.3),
                          style: BorderStyle.solid,
                          width: 1.5),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.cloud_upload_rounded,
                              color: accent, size: 28),
                        ),
                        const SizedBox(height: 10),
                        Text('Tap to upload from gallery',
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 2),
                        const Text('JPG, PNG supported',
                            style: TextStyle(
                                color: Color(0xFF6C757D),
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // ── action buttons ───────────────────────────
              Row(
                children: [
                  if (isSaved)
                    // delete button
                    Expanded(
                      child: _ActionButton(
                        label: 'Delete',
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFFF3B30),
                        filled: false,
                        onTap: widget.onDelete,
                      ),
                    )
                  else
                    Expanded(
                      child: _ActionButton(
                        label: 'Cancel',
                        icon: Icons.close_rounded,
                        color: const Color(0xFF6C757D),
                        filled: false,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _ActionButton(
                      label: isSaved ? 'Update File' : 'Upload File',
                      icon: isSaved
                          ? Icons.upload_rounded
                          : Icons.add_photo_alternate_rounded,
                      color: const Color(0xFF1A1D20),
                      filled: true,
                      onTap: widget.onUpload,
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
}

// ─────────────────────────────────────────────────────────────
// ACTION BUTTON  — reusable filled / outlined button
// ─────────────────────────────────────────────────────────────
class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onTap(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: widget.filled ? widget.color : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: widget.filled
                ? null
                : Border.all(
                    color: widget.color.withOpacity(0.4), width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon,
                  size: 16,
                  color: widget.filled ? Colors.white : widget.color),
              const SizedBox(width: 6),
              Text(widget.label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color:
                          widget.filled ? Colors.white : widget.color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// FULL SCREEN VIEWER  — pinch-to-zoom with accent UI
// ─────────────────────────────────────────────────────────────
class _FullScreenViewer extends StatelessWidget {
  final String filePath;
  final String docName;
  final Color accent;

  const _FullScreenViewer({
    required this.filePath,
    required this.docName,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_rounded,
                color: Colors.white, size: 20),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(docName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            Text('Pinch to zoom',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.4), width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, size: 12, color: accent),
                const SizedBox(width: 4),
                Text('Secured',
                    style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
      body: Hero(
        tag: 'doc_$docName',
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(24),
          minScale: 0.5,
          maxScale: 5.0,
          child: Center(
            child: Image.file(File(filePath)),
          ),
        ),
      ),
    );
  }
}