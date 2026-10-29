import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:staydriv_app/core/theme.dart';

class ContactPickerResult {
  final String name;
  final String phoneNumber;
  final List<String> phoneNumbers;

  const ContactPickerResult({
    required this.name,
    required this.phoneNumber,
    this.phoneNumbers = const [],
  });

  @override
  String toString() => 'ContactPickerResult(name: $name, phone: $phoneNumber, all: $phoneNumbers)';
}

class ContactPickerService {
  static const MethodChannel _channel = MethodChannel('com.staydriv.app/contact_picker');

  /// Normalizes and cleans phone numbers, particularly Indian numbers
  /// (e.g. "+91 98765-43210" or "09876543210" -> "9876543210")
  static String cleanIndianPhoneNumber(String raw) {
    if (raw.trim().isEmpty) return '';
    // Strip whitespace, hyphens, brackets, dots, commas
    String cleaned = raw.replaceAll(RegExp(r'[\s\-\(\)\.,]'), '');

    if (cleaned.startsWith('+91')) {
      cleaned = cleaned.substring(3);
    } else if (cleaned.startsWith('0091')) {
      cleaned = cleaned.substring(4);
    } else if (cleaned.startsWith('91') && cleaned.length == 12) {
      cleaned = cleaned.substring(2);
    }

    if (cleaned.startsWith('0') && cleaned.length == 11) {
      cleaned = cleaned.substring(1);
    }

    // Keep only digits
    cleaned = cleaned.replaceAll(RegExp(r'[^\d]'), '');

    // If longer than 10 and ends with 10 digits, extract the last 10
    if (cleaned.length > 10) {
      cleaned = cleaned.substring(cleaned.length - 10);
    }

    return cleaned;
  }

  /// Validates whether a given string is a valid 10-digit Indian mobile number
  /// Indian mobile numbers start with 6, 7, 8, or 9 and have 10 digits.
  static bool isValidIndianMobile(String number) {
    final cleaned = cleanIndianPhoneNumber(number);
    return RegExp(r'^[6-9]\d{9}$').hasMatch(cleaned);
  }

  /// Formats a 10-digit number for clean readable display
  /// e.g. "9876543210" -> "98765 43210"
  static String formatForDisplay(String number) {
    final cleaned = cleanIndianPhoneNumber(number);
    if (cleaned.length == 10) {
      return '${cleaned.substring(0, 5)} ${cleaned.substring(5)}';
    }
    return number;
  }

  /// Launches the system native contact picker without full contacts permission.
  /// Returns [ContactPickerResult] if a contact was selected, or null if cancelled.
  static Future<ContactPickerResult?> pickContact() async {
    try {
      final res = await _channel.invokeMethod<dynamic>('pickContact');
      if (res == null) return null; // User cancelled picker

      final map = Map<String, dynamic>.from(res as Map);
      final name = (map['name'] ?? '').toString().trim();
      final rawPhone = (map['phoneNumber'] ?? '').toString().trim();
      final rawList = (map['phoneNumbers'] as List<dynamic>?) ?? [];

      final cleanedList = <String>[];
      for (final item in rawList) {
        final c = cleanIndianPhoneNumber(item.toString());
        if (c.isNotEmpty && !cleanedList.contains(c)) {
          cleanedList.add(c);
        }
      }

      final cleanedPhone = cleanIndianPhoneNumber(rawPhone);
      if (cleanedPhone.isNotEmpty && !cleanedList.contains(cleanedPhone)) {
        cleanedList.insert(0, cleanedPhone);
      }

      return ContactPickerResult(
        name: name,
        phoneNumber: cleanedPhone,
        phoneNumbers: cleanedList,
      );
    } on PlatformException catch (e) {
      debugPrint('[ContactPickerService] PlatformException: ${e.message}');
      return null;
    } on MissingPluginException catch (e) {
      debugPrint('[ContactPickerService] MissingPluginException: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[ContactPickerService] Unexpected error: $e');
      return null;
    }
  }

  /// If a contact has multiple numbers, presents a clean, modern bottom sheet dialog to select one
  static Future<String?> showNumberSelectionDialog(
    BuildContext context, {
    required String contactName,
    required List<String> numbers,
  }) async {
    if (numbers.isEmpty) return null;
    if (numbers.length == 1) return numbers.first;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.contacts_rounded,
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contactName.isNotEmpty ? contactName : 'Select Mobile Number',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Choose which number to use for this booking',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: numbers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final num = numbers[index];
                      final display = num.length == 10
                          ? '+91 ${num.substring(0, 5)} ${num.substring(5)}'
                          : num;
                      final isValid = isValidIndianMobile(num);

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.phone_iphone_rounded,
                            color: isValid ? AppTheme.primaryColor : Colors.grey.shade600,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          display,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: isValid
                            ? Text(
                                'Mobile Number',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Select',
                            style: GoogleFonts.hankenGrotesk(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.pop(ctx, num),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
