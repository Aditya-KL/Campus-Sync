// lib/services/cloudinary_service.dart
//
// Improvements over original:
//  • Singleton — one instance shared across the whole app.
//  • Typed CloudinaryUploadException with a code field so callers can
//    distinguish network errors from file-not-found errors, etc.
//  • Pre-upload validation: checks file exists and is <= 10 MB.
//  • onProgress callback (0.0 -> 1.0) for upload progress rings.
//  • Convenience wrappers: uploadProfilePicture / uploadDocument.
//  • Static optimiseUrl() helper: appends Cloudinary transforms so images
//    load faster in the UI without extra packages.
//  • All errors caught and re-thrown as CloudinaryUploadException —
//    callers never see raw Cloudinary or Socket internals.

import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';

// ─────────────────────────────────────────────────────────────
// TYPED ERROR
// ─────────────────────────────────────────────────────────────
class CloudinaryUploadException implements Exception {
  final String message;

  /// One of:
  /// 'file_not_found' | 'file_too_large' | 'upload_failed' |
  /// 'empty_url'      | 'network'        | 'unknown'
  final String code;

  const CloudinaryUploadException(this.message, {this.code = 'unknown'});

  @override
  String toString() => 'CloudinaryUploadException[$code]: $message';
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────
class CloudinaryService {
  // ── Credentials ─────────────────────────────────────────────
  // The upload preset must be UNSIGNED in Cloudinary Console:
  //   Settings -> Upload -> Upload Presets -> campus_sync_preset -> Unsigned
  static const String _cloudName    = 'dw35xfpla';
  static const String _uploadPreset = 'campus_sync_preset';

  // Singleton — factory constructor returns the same instance every time
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  // cache: false -> never serve a stale URL from a previous run
  final _cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);

  // ── Core upload ──────────────────────────────────────────────
  /// Uploads any local file to Cloudinary under campus_sync/{userId}/{fileLabel}.
  ///
  /// Re-uploading with the same [fileLabel] overwrites the old file in
  /// Cloudinary, keeping storage clean (ideal for profile pictures).
  ///
  /// [onProgress] fires with values 0.0 -> 1.0 as upload progresses.
  /// Returns the final secure HTTPS URL.
  /// Throws [CloudinaryUploadException] on any failure.
  Future<String> uploadFile({
    required String userId,
    required String filePath,
    required String fileLabel,
    void Function(double progress)? onProgress,
  }) async {
    // 1. File-exists check
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const CloudinaryUploadException(
        'The selected file could not be found on the device.',
        code: 'file_not_found',
      );
    }

    // 2. Size check (10 MB cap on Cloudinary free plan)
    final sizeBytes = await file.length();
    const maxBytes  = 10 * 1024 * 1024; // 10 MB
    if (sizeBytes > maxBytes) {
      throw const CloudinaryUploadException(
        'File exceeds the 10 MB limit. Please choose a smaller image.',
        code: 'file_too_large',
      );
    }

    try {
      onProgress?.call(0.05); // signal: upload starting

      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          filePath,
          folder:       'campus_sync/$userId', // organised per user
          identifier:   fileLabel,             // same label = overwrites
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      onProgress?.call(1.0); // signal: complete

      if (response.secureUrl.isEmpty) {
        throw const CloudinaryUploadException(
          'Upload finished but no URL was returned.',
          code: 'empty_url',
        );
      }

      return response.secureUrl;

    } on CloudinaryUploadException {
      rethrow;
    } on SocketException {
      throw const CloudinaryUploadException(
        'No internet connection. Check your network and try again.',
        code: 'network',
      );
    } on CloudinaryException catch (e) {
      throw CloudinaryUploadException(
        'Upload failed: ${e.message}',
        code: 'upload_failed',
      );
    } catch (e) {
      throw CloudinaryUploadException(
        'Unexpected upload error: $e',
        code: 'unknown',
      );
    }
  }

  // ── Convenience: profile picture ────────────────────────────
  /// Stored as campus_sync/{userId}/profile — overwrites on re-upload.
  Future<String> uploadProfilePicture({
    required String userId,
    required String filePath,
    void Function(double)? onProgress,
  }) =>
      uploadFile(
        userId:     userId,
        filePath:   filePath,
        fileLabel:  'profile',
        onProgress: onProgress,
      );

  // ── Convenience: document ────────────────────────────────────
  Future<String> uploadDocument({
    required String userId,
    required String filePath,
    required String docLabel,
    void Function(double)? onProgress,
  }) =>
      uploadFile(
        userId:     userId,
        filePath:   filePath,
        fileLabel:  'doc_$docLabel',
        onProgress: onProgress,
      );

  // ── URL optimisation ─────────────────────────────────────────
  /// Inserts Cloudinary auto-quality + auto-format + width transforms into
  /// an existing secure URL so images load faster without extra packages.
  /// [width] is in logical pixels; doubled internally for @2x screens.
  static String optimiseUrl(String url, {int width = 200}) {
    if (url.isEmpty || !url.contains('cloudinary.com')) return url;
    return url.replaceFirst(
      '/upload/',
      '/upload/w_${width * 2},c_fill,q_auto,f_auto/',
    );
  }
}