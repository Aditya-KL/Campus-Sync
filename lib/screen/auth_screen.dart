import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────
// AUTH SCREEN
// ─────────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  // ── palette (matches app theme) ────────────────────────────
  static const Color _yellow     = Color(0xFFFFD166);
  static const Color _bg         = Color(0xFFF0F2F5);
  static const Color _ink        = Color(0xFF1A1D20);
  static const Color _muted      = Color(0xFF6C757D);
  static const Color _red        = Color(0xFFFF3B30);
  static const Color _green      = Color(0xFF34C759);

  // ── controllers ────────────────────────────────────────────
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _nameCtrl    = TextEditingController();
  final _rollCtrl    = TextEditingController();
  final _confPassCtrl = TextEditingController();

  // ── state ──────────────────────────────────────────────────
  bool _isLogin        = true;
  bool _isForgot       = false;
  bool _isLoading      = false;
  bool _rememberMe     = false;
  bool _showPass       = false;
  bool _showConfPass   = false;
  String? _selectedBranch;
  String? _emailError;
  String? _generalError;

  final List<String> _branches = [
    'CSE', 'AI', 'CBE', 'CE', 'CST', 'ECE',
    'ECO', 'EEE', 'EP', 'ME', 'MME', 'MNC',

  ];

  
  // ── animations ─────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late AnimationController _bubbleCtrl;
  late Animation<double>   _entryFade;
  late Animation<Offset>   _entrySlide;
  late Animation<double>   _bubblePulse;

  @override
  void initState() {
    super.initState();

    // Entry animation
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
            begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();

    // Bubble slow pulse
    _bubbleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
    _bubblePulse = Tween<double>(begin: 0.9, end: 1.1)
        .animate(CurvedAnimation(parent: _bubbleCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _bubbleCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _confPassCtrl.dispose();
    super.dispose();
  }

  // ── re-trigger entry anim on mode switch ───────────────────
  // Pass keepMessage: true when the callback itself sets _generalError
  // (e.g. after successful registration) so it isn't wiped.
  void _switchMode(VoidCallback change, {bool keepMessage = false}) {
    setState(() {
      _emailError = null;
      if (!keepMessage) _generalError = null;
      change();
    });
    _entryCtrl.forward(from: 0);
  }

  // ── email validation ────────────────────────────────────────
  bool _validateEmail(String email) {
    final re = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');
    return re.hasMatch(email.trim());
  }

  // ── Firebase: Sign in ───────────────────────────────────────
  Future<void> _submitAuth() async {
    setState(() { _emailError = null; _generalError = null; });

    // Email format check
    if (!_validateEmail(_emailCtrl.text)) {
      setState(() => _emailError = 'Enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
        if (!cred.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          setState(() => _generalError =
              'Please verify your email before logging in.');
          return;
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('remember_me', _rememberMe);
        if (!mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
      } else {
        // Registration
        if (_passCtrl.text != _confPassCtrl.text) {
          setState(() => _generalError = 'Passwords do not match.');
          return;
        }
        if (_selectedBranch == null) {
          setState(() => _generalError = 'Please select your branch.');
          return;
        }
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );

        // Send verification email — plain call works out of the box.
        // ActionCodeSettings with page.link requires Firebase Dynamic Links
        // to be configured separately and causes errors if not set up.
        // To keep the link active longer: Firebase Console →
        // Authentication → Templates → Email address verification → Link expiry.
        await cred.user!.sendEmailVerification();

        await FirebaseFirestore.instance
            .collection('students')
            .doc(cred.user!.uid)
            .set({
          'name':   _nameCtrl.text.trim(),
          'rollNo': _rollCtrl.text.trim(),
          'branch': _selectedBranch,
          'email':  _emailCtrl.text.trim(),
          'isDeveloper': false,
        });

        await FirebaseAuth.instance.signOut();
        // Set the success message inside the switch callback so it
        // is not wiped when _switchMode clears _generalError
        _switchMode(() {
          _isLogin      = true;
          _generalError = '✓ Verification email sent! Check your inbox.';
        }, keepMessage: true);
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Something went wrong. Please try again.';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Invalid email or password.';
      } else if (e.code == 'email-already-in-use') {
        msg = 'This email is already registered.';
      } else if (e.code == 'weak-password') {
        msg = 'Password must be at least 6 characters.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Too many attempts. Please wait a moment.';
      } else if (e.code == 'network-request-failed') {
        msg = 'No internet connection.';
      }
      setState(() => _generalError = msg);
    } catch (e) {
      // Catches Firestore write errors, network issues etc.
      debugPrint('Auth error: $e');
      setState(() => _generalError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Firebase: Password reset ────────────────────────────────
  // Plain sendPasswordResetEmail works without any extra setup.
  // To keep the link active longer: Firebase Console →
  // Authentication → Templates → Password reset → Link expiry.
  // To improve inbox delivery: customise "From name" and "Reply-to"
  // in that same Templates section.
  Future<void> _sendResetLink() async {
    setState(() { _emailError = null; _generalError = null; });

    if (!_validateEmail(_emailCtrl.text)) {
      setState(() => _emailError = 'Enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Plain call — no ActionCodeSettings needed
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailCtrl.text.trim(),
      );
      // Switch back to login and show success inside the callback
      // so _switchMode doesn't wipe the message
      _switchMode(() {
        _isForgot     = false;
        _generalError = '✓ Reset link sent to ${_emailCtrl.text.trim()}. '
            'Check your inbox.';
      }, keepMessage: true);
    } on FirebaseAuthException catch (e) {
      String msg = 'Failed to send reset email. Try again.';
      if (e.code == 'user-not-found') {
        msg = 'No account found with this email.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Too many attempts. Please wait a moment.';
      } else if (e.code == 'network-request-failed') {
        msg = 'No internet connection.';
      }
      setState(() => _generalError = msg);
    } catch (e) {
      debugPrint('Reset error: $e');
      setState(() => _generalError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── animated bubble background ─────────────────────
          _AnimatedBubbles(pulseAnim: _bubblePulse),

          // ── scrollable content ─────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: FadeTransition(
                  opacity: _entryFade,
                  child: SlideTransition(
                    position: _entrySlide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Logo ────────────────────────────
                        _buildLogo(),
                        const SizedBox(height: 36),
                        // ── Form card ───────────────────────
                        _buildCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LOGO ───────────────────────────────────────────────────
  Widget _buildLogo() {
    return Column(
      children: [
        // Logo image in rounded white card
        Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: _yellow.withOpacity(0.35),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 6)),
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // App name — two-tone
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Campus',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: ' Sync',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _yellow,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your college. Organised.',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _muted),
        ),
      ],
    );
  }

  // ── FORM CARD ──────────────────────────────────────────────
  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _isForgot
              ? _forgotForm()
              : (_isLogin ? _loginForm() : _registerForm()),
        ),
      ),
    );
  }

  // ── LOGIN FORM ─────────────────────────────────────────────
  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formTitle('Welcome back'),
        _formSubtitle('Sign in to continue'),
        const SizedBox(height: 24),
        _emailField(),
        const SizedBox(height: 14),
        _passwordField(_passCtrl, 'Password', _showPass,
            () => setState(() => _showPass = !_showPass)),
        const SizedBox(height: 6),
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _rememberMe ? _ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: _rememberMe
                              ? _ink
                              : _muted.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: _rememberMe
                        ? const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text('Remember me',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _muted)),
                ],
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _switchMode(() => _isForgot = true),
              child: Text('Forgot password?',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _ink)),
            ),
          ],
        ),
        if (_generalError != null) _errorOrSuccess(_generalError!),
        const SizedBox(height: 22),
        _submitButton('Sign In', _submitAuth),
        const SizedBox(height: 16),
        _divider('or'),
        const SizedBox(height: 16),
        _switchLink('Don\'t have an account?', 'Register',
            () => _switchMode(() => _isLogin = false)),
      ],
    );
  }

  // ── REGISTER FORM ──────────────────────────────────────────
  Widget _registerForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formTitle('Create Account'),
        _formSubtitle('Fill in your details to get started'),
        const SizedBox(height: 24),
        _field(_nameCtrl, 'Full Name', Icons.person_outline_rounded),
        const SizedBox(height: 14),
        _emailField(),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _rollCtrl,
                keyboardType: TextInputType.text, // Allows letters for the Dept Code
                maxLength: 8,
                textCapitalization: TextCapitalization.characters, // Auto-uppercase
                decoration: InputDecoration(
                  labelText: 'Roll Number',
                  prefixIcon: Icon(Icons.tag_rounded),
                  counterText: "", 
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  final pattern = r'^[12][0-9][012][123](AI|CB|CE|CS|CT|EC|EE|ES|MC|ME|MM|PH|PR|CM|GT|MT|PC|ST|VL)[0-9]{2}$';
                  final regExp = RegExp(pattern);

                  if (!regExp.hasMatch(value.toUpperCase())) {
                    return 'Invalid Roll Number';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _branchDropdown()),
          ],
        ),
        const SizedBox(height: 14),
        _passwordField(_passCtrl, 'Password', _showPass,
            () => setState(() => _showPass = !_showPass)),
        const SizedBox(height: 14),
        _passwordField(_confPassCtrl, 'Confirm Password', _showConfPass,
            () => setState(() => _showConfPass = !_showConfPass)),
        if (_generalError != null) _errorOrSuccess(_generalError!),
        const SizedBox(height: 22),
        _submitButton('Create Account', _submitAuth),
        const SizedBox(height: 16),
        _divider('or'),
        const SizedBox(height: 16),
        _switchLink('Already have an account?', 'Sign In',
            () => _switchMode(() => _isLogin = true)),
      ],
    );
  }

  // ── FORGOT PASSWORD FORM ───────────────────────────────────
  Widget _forgotForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _formTitle('Reset Password'),
        _formSubtitle('We\'ll send a secure link to your inbox'),
        const SizedBox(height: 24),
        _emailField(),
        if (_generalError != null) _errorOrSuccess(_generalError!),
        const SizedBox(height: 22),
        _submitButton('Send Reset Link', _sendResetLink),
        const SizedBox(height: 16),
        _switchLink('', 'Back to Sign In',
            () => _switchMode(() => _isForgot = false)),
      ],
    );
  }

  // ── FORM WIDGETS ───────────────────────────────────────────

  Widget _formTitle(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: _ink,
            letterSpacing: -0.4));
  }

  Widget _formSubtitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _muted)),
    );
  }

  // Email field with live validation error
  Widget _emailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldContainer(
          child: TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) {
              if (_emailError != null) {
                setState(() => _emailError = null);
              }
            },
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
            decoration: _inputDecoration(
              'Email address',
              Icons.email_outlined,
              hasError: _emailError != null,
            ),
          ),
        ),
        if (_emailError != null)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 4),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 13, color: _red),
                const SizedBox(width: 4),
                Text(_emailError!,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _red)),
              ],
            ),
          ),
      ],
    );
  }

  // Generic text field
  Widget _field(TextEditingController ctrl, String hint, IconData icon) {
    return _fieldContainer(
      child: TextField(
        controller: ctrl,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
        decoration: _inputDecoration(hint, icon),
      ),
    );
  }

  // Password field with show/hide toggle
  Widget _passwordField(TextEditingController ctrl, String hint,
      bool visible, VoidCallback onToggle) {
    return _fieldContainer(
      child: TextField(
        controller: ctrl,
        obscureText: !visible,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
        decoration: _inputDecoration(
          hint,
          Icons.lock_outline_rounded,
        ).copyWith(
          suffixIcon: GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                visible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 20,
                color: _muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldContainer({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon,
      {bool hasError = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _muted.withOpacity(0.7), fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: _muted),
      border: InputBorder.none,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
            color: hasError ? _red.withOpacity(0.4) : Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
            color: hasError ? _red : _yellow, width: 1.5),
      ),
    );
  }

  // Branch dropdown
  Widget _branchDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9ECEF), width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBranch,
          hint: Text('Branch',
              style: TextStyle(
                  color: _muted.withOpacity(0.7), fontSize: 13)),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: _muted, size: 18),
          dropdownColor: Colors.white,
          isExpanded: true,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: _ink),
          items: _branches
              .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text(b),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedBranch = v),
        ),
      ),
    );
  }

  // Error / success message
  Widget _errorOrSuccess(String msg) {
    final isSuccess = msg.startsWith('✓');
    final color = isSuccess ? _green : _red;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
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
        ],
      ),
    );
  }

  // Submit button
  Widget _submitButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _ink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: _isLoading ? null : onTap,
        child: _isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        Expanded(
            child: Divider(color: _muted.withOpacity(0.2), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500, color: _muted)),
        ),
        Expanded(
            child: Divider(color: _muted.withOpacity(0.2), thickness: 1)),
      ],
    );
  }

  Widget _switchLink(String prefix, String action, VoidCallback onTap) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: RichText(
          text: TextSpan(
            children: [
              if (prefix.isNotEmpty)
                TextSpan(
                    text: '$prefix ',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _muted)),
              TextSpan(
                  text: action,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ink)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ANIMATED BUBBLES BACKGROUND
// Soft floating circles matching the app-wide bubble theme,
// but with gentle parallax-style drift animation
// ─────────────────────────────────────────────────────────────
class _AnimatedBubbles extends StatelessWidget {
  final Animation<double> pulseAnim;
  const _AnimatedBubbles({required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) {
        final s = pulseAnim.value;
        return Stack(
          children: [
            // top-right large yellow bubble
            Positioned(
              top: -60 + (s - 1) * 20,
              right: -40 + (s - 1) * 15,
              child: CircleAvatar(
                radius: 140 * s,
                backgroundColor:
                    const Color(0xFFFFD166).withOpacity(0.32),
              ),
            ),
            // mid-left grey
            Positioned(
              top: 160 - (s - 1) * 12,
              left: -80 + (s - 1) * 10,
              child: CircleAvatar(
                radius: 100,
                backgroundColor: const Color(0xFFE2E5E9),
              ),
            ),
            // bottom-right soft yellow
            Positioned(
              bottom: -30 + (s - 1) * 18,
              right: -20,
              child: CircleAvatar(
                radius: 130,
                backgroundColor:
                    const Color(0xFFFFD166).withOpacity(0.15),
              ),
            ),
            // bottom-left grey
            Positioned(
              bottom: 80 - (s - 1) * 10,
              left: 20,
              child: CircleAvatar(
                radius: 90 * s,
                backgroundColor: const Color(0xFFD3D6DA),
              ),
            ),
            // small floating accent top-left
            Positioned(
              top: 80 + (s - 1) * 8,
              left: 30 - (s - 1) * 6,
              child: CircleAvatar(
                radius: 28,
                backgroundColor:
                    const Color(0xFFFFD166).withOpacity(0.18),
              ),
            ),
          ],
        );
      },
    );
  }
}