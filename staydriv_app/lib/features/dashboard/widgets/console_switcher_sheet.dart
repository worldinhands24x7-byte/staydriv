import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../food_ordering/screens/restaurant_partner_console_screen.dart';
import '../../food_ordering/services/food_service.dart';
import '../screens/home_screen.dart';

/// Interactive modal sheet allowing customers and partners to switch effortlessly
/// between Customer Console, Pilot Console, Restaurant Partner Console, and Admin Console.
class ConsoleSwitcherSheet extends StatelessWidget {
  final String currentRole;
  final String? userPhone;

  const ConsoleSwitcherSheet({
    super.key,
    this.currentRole = 'Customer',
    this.userPhone,
  });

  static Future<void> show(BuildContext context, {String currentRole = 'Customer', String? userPhone}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConsoleSwitcherSheet(currentRole: currentRole, userPhone: userPhone),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'StayDriv Portals',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F1E4A),
                    ),
                  ),
                  Text(
                    'Switch between consoles effortlessly',
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Customer Console Card
          _buildConsoleCard(
            context: context,
            title: 'Customer Console',
            subtitle: 'Book Rides, Order Food & Manage Wallet',
            icon: Icons.person_pin_circle_rounded,
            color: const Color(0xFF1E60FF),
            isActive: currentRole.toLowerCase() == 'customer',
            onTap: () => _switchToCustomer(context),
          ),
          const SizedBox(height: 10),

          // 2. Pilot / Driver Console Card
          _buildConsoleCard(
            context: context,
            title: 'Pilot / Driver Console',
            subtitle: 'Accept Rides, GPS Navigation & Daily Salary',
            icon: Icons.two_wheeler_rounded,
            color: const Color(0xFF10B981),
            isActive: currentRole.toLowerCase() == 'driver' || currentRole.toLowerCase() == 'pilot',
            onTap: () => _switchToPilot(context),
          ),
          const SizedBox(height: 10),

          // 3. Restaurant Partner Console Card
          _buildConsoleCard(
            context: context,
            title: 'Restaurant Partner Console',
            subtitle: 'Live Food Orders, Menu, Audio Alerts & Settlements',
            icon: Icons.restaurant_rounded,
            color: const Color(0xFFEA580C),
            isActive: currentRole.toLowerCase() == 'restaurant partner',
            onTap: () => _switchToRestaurantPartner(context),
          ),
          const SizedBox(height: 10),

          // 4. Admin & Operations Console Card
          _buildConsoleCard(
            context: context,
            title: 'Admin & Operations Console',
            subtitle: 'Platform Governance, Live Tracking, Approvals & Ledgers',
            icon: Icons.admin_panel_settings_rounded,
            color: const Color(0xFF4F46E5),
            isActive: currentRole.toLowerCase() == 'admin',
            badgeText: 'Web / Operations',
            onTap: () => _openAdminConsoleOptions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isActive,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? color : const Color(0xFFE2E8F0),
              width: isActive ? 1.8 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Icon Badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F1E4A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'CURRENT',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ] else if (badgeText != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Action Arrow / Active Check
              Icon(
                isActive ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                size: isActive ? 20 : 14,
                color: isActive ? color : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchToCustomer(BuildContext context) async {
    Navigator.pop(context);
    if (currentRole.toLowerCase() == 'customer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in Customer Console'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF1E60FF),
        ),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', 'Customer');
    final phone = userPhone ?? prefs.getString('phone_number') ?? prefs.getString('user_phone') ?? '9010922111';
    final name = prefs.getString('user_name') ?? 'StayDriv Customer';

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            userName: name,
            userRole: 'Customer',
            phoneNumber: phone,
          ),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _switchToPilot(BuildContext context) async {
    Navigator.pop(context);
    if (currentRole.toLowerCase() == 'driver' || currentRole.toLowerCase() == 'pilot') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in Pilot Console'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', 'Driver');
    await prefs.setBool('is_driver', true);
    final phone = userPhone ?? prefs.getString('phone_number') ?? prefs.getString('user_phone') ?? '7013213057';
    final vehicle = prefs.getString('selected_vehicle') ?? 'Bike';

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            userName: 'Pilot Partner',
            userRole: 'Driver',
            phoneNumber: phone,
            selectedVehicle: vehicle,
          ),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _switchToRestaurantPartner(BuildContext context) async {
    Navigator.pop(context);
    if (currentRole.toLowerCase() == 'restaurant partner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already in Restaurant Partner Console'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFFEA580C),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = userPhone ?? prefs.getString('phone_number') ?? prefs.getString('user_phone') ?? '9010922111';

    if (!context.mounted) return;

    // Show quick loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Opening Restaurant Partner Console...'),
          ],
        ),
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFFEA580C),
      ),
    );

    Map<String, dynamic>? restaurantData;

    // Check cached restaurant data
    final cachedStr = prefs.getString('restaurant_data');
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        restaurantData = Map<String, dynamic>.from(jsonDecode(cachedStr));
      } catch (_) {}
    }

    // Try fetching from backend by phone
    if (restaurantData == null) {
      try {
        final partnerCheck = await FoodService().getPartnerByPhone(phone).timeout(const Duration(seconds: 3));
        if (partnerCheck != null && partnerCheck['restaurant'] != null) {
          restaurantData = Map<String, dynamic>.from(partnerCheck['restaurant']);
          await prefs.setString('restaurant_data', jsonEncode(restaurantData));
        }
      } catch (_) {}
    }

    // Provide default fallback restaurant partner profile if not yet registered
    restaurantData ??= {
      'restaurantId': 'REST_${phone.replaceAll(RegExp(r'\D'), '')}',
      'name': 'StayDriv Partner Kitchen',
      'phone': phone,
      'isOpen': true,
      'status': 'approved',
      'address': 'StayDriv Partner Hub, Hyderabad',
      'openingHours': '07:00 AM - 11:00 PM',
      'deliveryTime': '20-30 mins',
      'isMembershipEnrolled': true,
    };

    await prefs.setString('user_role', 'Restaurant Partner');

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RestaurantPartnerConsoleScreen(restaurantData: restaurantData!),
        ),
      );
    }
  }

  void _openAdminConsoleOptions(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF4F46E5), size: 24),
                const SizedBox(width: 8),
                Text(
                  'Admin & Operations Console',
                  style: GoogleFonts.hankenGrotesk(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how you want to open the StayDriv Admin Console:',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
              leading: const Icon(Icons.open_in_browser_rounded, color: Color(0xFF4F46E5)),
              title: Text('Launch Web Admin Portal', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Access full desktop governance portal (localhost:5173 / localhost:3000/admin)'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                final urls = ['http://localhost:5173/', 'http://localhost:3000/admin'];
                for (final u in urls) {
                  try {
                    final uri = Uri.parse(u);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      return;
                    }
                  } catch (_) {}
                }
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
              leading: const Icon(Icons.phone_android_rounded, color: Color(0xFF4F46E5)),
              title: Text('Switch to In-App Admin View', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('View operations dashboard and platform controls in mobile app'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () async {
                Navigator.pop(ctx);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_role', 'Admin');
                final phone = userPhone ?? prefs.getString('phone_number') ?? '9010922111';

                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HomeScreen(
                        userName: 'StayDriv Admin',
                        userRole: 'Admin',
                        phoneNumber: phone,
                      ),
                    ),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
