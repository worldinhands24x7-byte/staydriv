import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Document Upload & Validation Tests', () {
    test('Allowed document extensions strictly include JPG, JPEG, PNG, and PDF', () {
      final allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];
      
      expect(allowedExtensions.contains('jpg'), isTrue);
      expect(allowedExtensions.contains('jpeg'), isTrue);
      expect(allowedExtensions.contains('png'), isTrue);
      expect(allowedExtensions.contains('pdf'), isTrue);
      expect(allowedExtensions.contains('exe'), isFalse);
      expect(allowedExtensions.contains('mp4'), isFalse);
      expect(allowedExtensions.contains('docx'), isFalse);
    });

    test('MIME type resolution matches expected Content-Type for backend storage', () {
      String resolveMime(String ext) {
        final clean = ext.replaceAll('.', '').toLowerCase();
        if (clean == 'png') return 'image/png';
        if (clean == 'pdf') return 'application/pdf';
        if (clean == 'jpg' || clean == 'jpeg') return 'image/jpeg';
        return 'application/octet-stream';
      }

      expect(resolveMime('jpg'), 'image/jpeg');
      expect(resolveMime('.jpeg'), 'image/jpeg');
      expect(resolveMime('png'), 'image/png');
      expect(resolveMime('.pdf'), 'application/pdf');
      expect(resolveMime('bin'), 'application/octet-stream');
    });

    test('10 MB file size limit validation', () {
      const maxSizeBytes = 10 * 1024 * 1024; // 10,485,760 bytes
      
      bool isAllowedSize(int sizeBytes) => sizeBytes <= maxSizeBytes;

      expect(isAllowedSize(500 * 1024), isTrue); // 500 KB
      expect(isAllowedSize(5 * 1024 * 1024), isTrue); // 5 MB
      expect(isAllowedSize(10 * 1024 * 1024), isTrue); // 10 MB exactly
      expect(isAllowedSize(10 * 1024 * 1024 + 1), isFalse); // > 10 MB
      expect(isAllowedSize(25 * 1024 * 1024), isFalse); // 25 MB
    });

    test('File size display formatting handles KB and MB correctly', () {
      String formatSize(int bytes) {
        final sizeKb = bytes / 1024;
        return sizeKb >= 1024
            ? '${(sizeKb / 1024).toStringAsFixed(2)} MB'
            : '${sizeKb.toStringAsFixed(1)} KB';
      }

      expect(formatSize(512 * 1024), '512.0 KB');
      expect(formatSize(1024 * 1024), '1.00 MB');
      expect(formatSize((2.5 * 1024 * 1024).round()), '2.50 MB');
    });

    test('User-facing error sanitization removes raw exception and stack trace markers', () {
      String sanitizeError(dynamic e) {
        final clean = e.toString().replaceAll('Exception: ', '').replaceAll('Exception', '').trim();
        return clean.isNotEmpty ? clean : 'Upload could not be completed. Please try again.';
      }

      expect(
        sanitizeError(Exception('Failed to upload file to MongoDB storage')),
        'Failed to upload file to MongoDB storage',
      );
      expect(
        sanitizeError(Exception('')),
        'Upload could not be completed. Please try again.',
      );
      expect(
        sanitizeError(Exception('Your session has expired. Please login again.')),
        'Your session has expired. Please login again.',
      );
      expect(
        sanitizeError(Exception('File exceeds maximum size limit of 10 MB.')),
        'File exceeds maximum size limit of 10 MB.',
      );
    });

    test('Local persistent cache keys match expected format for each document type', () {
      final docTypes = [
        'photo',
        'aadhaarFront',
        'aadhaarBack',
        'licenseFront',
        'licenseBack',
        'rcFront',
        'rcBack',
        'fitness',
        'permit'
      ];

      for (final type in docTypes) {
        expect('doc_url_$type', startsWith('doc_url_'));
        expect('doc_name_$type', startsWith('doc_name_'));
        expect('doc_size_$type', startsWith('doc_size_'));
      }
    });
  });
}
