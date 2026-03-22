// lib/services/cloudinary_service.dart
//
// ── WHAT THIS FILE DOES ──────────────────────────────────────
//
// 1. Uploads files (JPG, PNG, PDF) to Cloudinary via the unsigned
//    upload API using dart:http — NO extra Cloudinary packages needed.
//    Remove 'cloudinary_public' from pubspec.yaml; add 'http: ^1.2.0'.
//
// 2. After upload, saves the URL to Firestore:
//    images/{uid} → field named by [slot]
//    Slots: 'profile', 'id_card', 'fee_receipt',
//           'semester_marksheet', 'gate_qr',
//           'marksheet_2', 'marksheet_3', 'marksheet_4'
//
// 3. fetchAllUrls(uid) → Map<slot, url>  instant, no local files.
//
// 4. 1 MB max file size enforced before network.
//
// 5. Progress: 0.05 → 0.15 → 0.90 → 1.0
//
// ── FIRESTORE STRUCTURE ──────────────────────────────────────
//   images/
//     {uid}/
//       profile:             "https://res.cloudinary.com/..."
//       id_card:             "https://..."
//       fee_receipt:         "https://..."
//       semester_marksheet:  "https://..."
//       gate_qr:             "https://..."
//       marksheet_2:         "https://..."
//       marksheet_3:         "https://..."
//       marksheet_4:         "https://..."
//       updatedAt:           Timestamp
//
// ── CLOUDINARY ONE-TIME SETUP ────────────────────────────────
//   1. Sign up at cloudinary.com (free tier).
//   2. Settings → Upload → Upload Presets → Add preset
//      → Signing mode = UNSIGNED → note the preset name.
//   3. Note your Cloud Name from the dashboard.
//   4. pubspec.yaml:  http: ^1.2.0
//   5. No API key/secret in the app — unsigned preset is safe.

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────
// TYPED ERROR
// ─────────────────────────────────────────────────────────────
class CloudinaryUploadException implements Exception {
  final String message;
  // 'file_not_found' | 'file_too_large' | 'bad_format' |
  // 'upload_failed'  | 'empty_url'      | 'network'    | 'unknown'
  final String code;
  const CloudinaryUploadException(this.message, {this.code = 'unknown'});
  @override
  String toString() => 'CloudinaryUploadException[$code]: $message';
}

// ─────────────────────────────────────────────────────────────
// SLOTS  —  UI card name → Firestore field name
// ─────────────────────────────────────────────────────────────
class CloudinarySlots {
  static const String profile           = 'profile';
  static const String idCard            = 'id_card';
  static const String feeReceipt        = 'fee_receipt';
  static const String semesterMarksheet = 'semester_marksheet';
  static const String gateQr            = 'gate_qr';
  static const String marksheet2        = 'marksheet_2';
  static const String marksheet3        = 'marksheet_3';
  static const String marksheet4        = 'marksheet_4';

  static String fromDocName(String docName) {
    switch (docName) {
      case 'ID Card':            return idCard;
      case 'Fee Receipt':        return feeReceipt;
      case 'Semester Marksheet': return semesterMarksheet;
      case 'Gate QR':            return gateQr;
      default:
        return docName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    }
  }
}

// ─────────────────────────────────────────────────────────────
// SERVICE  (singleton)
// ─────────────────────────────────────────────────────────────
class CloudinaryService {
  // ── ★ UPDATE THESE WITH YOUR OWN VALUES ★ ───────────────────
  static const String _cloudName    = 'dw35xfpla';
  static const String _uploadPreset = 'campus_sync_preset'; // UNSIGNED
  // ────────────────────────────────────────────────────────────

  static const int _maxBytes = 1 * 1024 * 1024; // 1 MB
  static const Set<String> _allowed = {'jpg', 'jpeg', 'png', 'pdf'};

  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  final _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────
  // CORE UPLOAD
  //
  // Why we append a timestamp to public_id:
  //   Unsigned presets don't allow 'overwrite: true'.
  //   Without overwrite, uploading to the same public_id returns the
  //   OLD cached URL — the image never actually changes in the CDN.
  //
  //   Solution: every upload gets a UNIQUE public_id by appending the
  //   current Unix timestamp (e.g. campus_sync/uid/id_card_1748291234).
  //   This forces Cloudinary to create a fresh asset every time.
  //   The old Cloudinary asset is abandoned (free tier: 25 GB storage,
  //   so this is fine). Firestore is updated to the new URL atomically:
  //   old field deleted → new field written in a single batch.
  // ─────────────────────────────────────────────────────────────
  Future<String> uploadFile({
    required String userId,
    required String filePath,
    required String slot,
    void Function(double progress)? onProgress,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const CloudinaryUploadException(
          'File not found on device.', code: 'file_not_found');
    }

    final ext = filePath.split('.').last.toLowerCase();
    if (!_allowed.contains(ext)) {
      throw CloudinaryUploadException(
          'Only JPG, PNG and PDF files are allowed (got .$ext).',
          code: 'bad_format');
    }

    final sizeBytes = await file.length();
    if (sizeBytes > _maxBytes) {
      final mb = (sizeBytes / _maxBytes).toStringAsFixed(2);
      throw CloudinaryUploadException(
          'File is ${mb} MB — maximum allowed is 1 MB. Please compress it.',
          code: 'file_too_large');
    }

    try {
      onProgress?.call(0.05);

      // ── Unique public_id — one folder per user ───────────────
      // Structure in Cloudinary Media Library:
      //   campus_sync/
      //     users/
      //       {uid}/              ← dedicated folder per student
      //         id_card_1748291234
      //         fee_receipt_1748291890
      //         profile_1748290000
      //         ...
      //
      // Timestamp suffix makes every upload a brand-new asset,
      // bypassing the unsigned-preset overwrite restriction.
      final ts           = DateTime.now().millisecondsSinceEpoch;
      final publicId     = 'campus_sync/users/$userId/${slot}_$ts';
      final resourceType = ext == 'pdf' ? 'raw' : 'image';
      final uri          = Uri.parse(
          'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = 'campus_sync/users/$userId'
        ..fields['public_id'] = '${slot}_$ts'
        ..files.add(await http.MultipartFile.fromPath('file', filePath));

      onProgress?.call(0.15);

      final streamed  = await request.send();
      final bodyBytes = await streamed.stream.toBytes();
      final body      = utf8.decode(bodyBytes);

      onProgress?.call(0.85);

      if (streamed.statusCode != 200) {
        String msg = 'Upload failed (HTTP ${streamed.statusCode}).';
        try {
          final j = jsonDecode(body) as Map<String, dynamic>;
          msg = (j['error']?['message'] as String?) ?? msg;
        } catch (_) {}
        throw CloudinaryUploadException(msg, code: 'upload_failed');
      }

      final json      = jsonDecode(body) as Map<String, dynamic>;
      final secureUrl = (json['secure_url'] as String?) ?? '';
      if (secureUrl.isEmpty) {
        throw const CloudinaryUploadException(
            'Upload succeeded but no URL was returned.', code: 'empty_url');
      }

      onProgress?.call(0.95);

      // ── Atomic Firestore update ───────────────────────────────
      // Delete the old field first, then write the new URL.
      // Using a WriteBatch so both operations are atomic — the UI
      // never sees a state where both old and new URLs exist.
      final docRef = _db.collection('images').doc(userId);
      final batch  = _db.batch();
      // Step 1: delete old field (FieldValue.delete removes the key entirely)
      batch.update(docRef, {slot: FieldValue.delete()});
      // Step 2: write new URL + timestamp
      batch.set(docRef, {
        slot:        secureUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();

      onProgress?.call(1.0);
      return secureUrl;

    } on CloudinaryUploadException {
      rethrow;
    } on SocketException {
      throw const CloudinaryUploadException(
          'No internet. Please check your network and retry.',
          code: 'network');
    } catch (e) {
      throw CloudinaryUploadException(
          'Unexpected upload error: $e', code: 'unknown');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // CONVENIENCE WRAPPERS
  // ─────────────────────────────────────────────────────────────

  Future<String> uploadProfilePicture({
    required String userId,
    required String filePath,
    void Function(double)? onProgress,
  }) =>
      uploadFile(
          userId: userId, filePath: filePath,
          slot: CloudinarySlots.profile, onProgress: onProgress);

  Future<String> uploadDocumentCard({
    required String userId,
    required String filePath,
    required String docName,
    void Function(double)? onProgress,
  }) =>
      uploadFile(
          userId: userId, filePath: filePath,
          slot: CloudinarySlots.fromDocName(docName), onProgress: onProgress);

  // ─────────────────────────────────────────────────────────────
  // FETCH  —  all saved URLs from Firestore
  //
  // serverAndCache: returns instantly from local cache, then
  // refreshes in background. On first install falls back to server.
  // ─────────────────────────────────────────────────────────────
  Future<Map<String, String>> fetchAllUrls(String userId) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db.collection('images').doc(userId)
            .get(const GetOptions(source: Source.serverAndCache));
      } catch (_) {
        snap = await _db.collection('images').doc(userId)
            .get(const GetOptions(source: Source.cache));
      }
      if (!snap.exists || snap.data() == null) return {};
      final out = <String, String>{};
      snap.data()!.forEach((k, v) {
        if (k != 'updatedAt' && v is String && v.isNotEmpty) out[k] = v;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<String?> fetchUrl(String userId, String slot) async =>
      (await fetchAllUrls(userId))[slot];

  // ─────────────────────────────────────────────────────────────
  // DELETE  —  removes the Firestore field for this slot.
  //
  // The old Cloudinary asset is NOT deleted here because unsigned
  // presets cannot call the Cloudinary Destroy API (it requires a
  // signed request with API secret). The old asset simply becomes
  // unreferenced — it will sit in your Cloudinary media library
  // but the app will never show or use it again.
  //
  // Free tier gives 25 GB storage so this is not a problem in
  // practice. To bulk-clean old assets, go to:
  //   Cloudinary Console → Media Library → campus_sync/{uid}/
  //   and delete manually if needed.
  // ─────────────────────────────────────────────────────────────
  Future<void> deleteUrl(String userId, String slot) async {
    try {
      await _db.collection('images').doc(userId).update({
        slot:        FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // URL OPTIMISATION
  // Inserts Cloudinary transform params so cards load fast.
  // PDFs returned unchanged (no image transforms).
  // [width] is logical px; doubled for @2x screens.
  // ─────────────────────────────────────────────────────────────
  static String optimiseUrl(String url, {int width = 200}) {
    if (url.isEmpty || !url.contains('cloudinary.com')) return url;
    if (url.contains('/raw/upload/')) return url; // PDF
    return url.replaceFirst(
        '/upload/', '/upload/w_${width * 2},c_fill,q_auto,f_auto/');
  }

  static bool isPdf(String url) =>
      url.isNotEmpty && url.contains('/raw/upload/');
}