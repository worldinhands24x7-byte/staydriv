import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';
import '../../../core/socket_service.dart';
import '../../../services/api_service.dart';
import '../../onboarding/screens/login_screen.dart';
import '../services/food_service.dart';
import 'restaurant_partner_console_screen.dart';

class RestaurantApplicationStatusScreen extends StatefulWidget {
  final Map<String, dynamic> restaurantData;
  final String phoneNumber;

  const RestaurantApplicationStatusScreen({
    super.key,
    required this.restaurantData,
    required this.phoneNumber,
  });

  @override
  State<RestaurantApplicationStatusScreen> createState() => _RestaurantApplicationStatusScreenState();
}

class _RestaurantApplicationStatusScreenState extends State<RestaurantApplicationStatusScreen> {
  final FoodService _foodService = FoodService();
  late Map<String, dynamic> _restaurant;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _restaurant = Map<String, dynamic>.from(widget.restaurantData);
    final restId = _restaurant['restaurantId'] as String? ?? '';
    if (restId.isNotEmpty) {
      SocketService().joinRestaurant(restId);
    }
    SocketService().addRestaurantUpdatedListener(_onSocketRestaurantUpdate);
  }

  @override
  void dispose() {
    SocketService().removeRestaurantUpdatedListener(_onSocketRestaurantUpdate);
    super.dispose();
  }

  void _onSocketRestaurantUpdate(Map<String, dynamic> data) {
    final updatedId = data['restaurantId'] as String? ?? '';
    final currentId = _restaurant['restaurantId'] as String? ?? '';
    if (updatedId == currentId || data['phone'] == widget.phoneNumber) {
      debugPrint('[RestaurantApplicationStatus] Live socket update received for $currentId');
      _checkLiveStatus();
    }
  }

  Future<void> _checkLiveStatus() async {
    setState(() => _isRefreshing = true);
    try {
      final res = await _foodService.getPartnerByPhone(widget.phoneNumber);
      if (res != null && res['restaurant'] != null) {
        final updated = res['restaurant'] as Map<String, dynamic>;
        setState(() {
          _restaurant = updated;
          _isRefreshing = false;
        });

        if (updated['status'] == 'approved') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Congratulations! Your restaurant application is approved.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RestaurantPartnerConsoleScreen(restaurantData: updated),
            ),
          );
        }
      } else {
        setState(() => _isRefreshing = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _openResubmitDialog() {
    final fssaiController = TextEditingController(text: _restaurant['fssaiNumber'] ?? '');
    final gstController = TextEditingController(text: _restaurant['gstNumber'] ?? '');
    final notesController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update & Resubmit Application',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Provide corrected details or valid compliance registration numbers for admin review.',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: fssaiController,
              decoration: InputDecoration(
                labelText: 'FSSAI License Number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: gstController,
              decoration: InputDecoration(
                labelText: 'GSTIN (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Correction Remarks',
                hintText: 'e.g. Updated valid FSSAI certificate details',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E60FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  setState(() => _isRefreshing = true);
                  final res = await _foodService.resubmitPartnerApplication(
                    _restaurant['restaurantId'],
                    {
                      'fssaiNumber': fssaiController.text.trim(),
                      'gstNumber': gstController.text.trim(),
                      'notes': notesController.text.trim(),
                    },
                  );
                  if (!mounted) return;
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Application resubmitted for admin review!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _checkLiveStatus();
                  } else {
                    setState(() => _isRefreshing = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res['message'] ?? 'Resubmission failed'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text(
                  'Submit for Verification',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (_restaurant['status'] as String? ?? 'pending').toLowerCase();
    final name = _restaurant['name'] as String? ?? 'Restaurant Partner';
    final restaurantId = _restaurant['restaurantId'] as String? ?? 'Pending';
    final address = _restaurant['address'] as String? ?? '';
    final rejectionReason = _restaurant['rejectionReason'] as String? ?? 'Information requires verification.';
    final actionRequiredNotes = _restaurant['actionRequiredNotes'] as String? ?? '';

    Color statusColor = const Color(0xFFF59E0B); // Amber
    String statusTitle = 'Application Under Review';
    String statusDesc = 'Your restaurant onboarding application has been submitted and is currently being verified by our operations team.';
    IconData statusIcon = Icons.hourglass_top_rounded;

    if (status == 'approved') {
      statusColor = const Color(0xFF10B981);
      statusTitle = 'Application Approved!';
      statusDesc = 'Your restaurant is active and ready to accept live food orders.';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'action_required') {
      statusColor = const Color(0xFFF59E0B);
      statusTitle = 'Action Required';
      statusDesc = actionRequiredNotes.isNotEmpty
          ? 'Correction Requested: $actionRequiredNotes'
          : 'Please update your application documents as requested by our operations team.';
      statusIcon = Icons.warning_amber_rounded;
    } else if (status == 'rejected') {
      statusColor = const Color(0xFFEF4444);
      statusTitle = 'Application Needs Attention';
      statusDesc = 'Rejection reason: $rejectionReason';
      statusIcon = Icons.error_outline_rounded;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Application Status',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A), fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF1E60FF)),
            onPressed: _isRefreshing ? null : _checkLiveStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            // Status Icon & Title Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    statusTitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F1E4A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    statusDesc,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      'STATUS: ${status.toUpperCase()}',
                      style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Restaurant Details Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submitted Information',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F1E4A)),
                  ),
                  const Divider(height: 24),
                  _buildDetailRow('Restaurant Name', name),
                  _buildDetailRow('Partner ID', restaurantId),
                  _buildDetailRow('Mobile Number', widget.phoneNumber),
                  if (address.isNotEmpty) _buildDetailRow('Address', address),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            if (status == 'approved') ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E60FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RestaurantPartnerConsoleScreen(restaurantData: _restaurant),
                      ),
                    );
                  },
                  icon: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 20),
                  label: Text(
                    'Open Restaurant Partner Console',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ] else ...[
              if (status == 'action_required' || status == 'rejected') ...[
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _openResubmitDialog,
                    icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
                    label: Text(
                      'Update & Resubmit Application',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1E60FF), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isRefreshing ? null : _checkLiveStatus,
                  icon: _isRefreshing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_rounded, color: Color(0xFF1E60FF)),
                  label: Text(
                    'Check Verification Status',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E60FF)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 12),

            TextButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                final phone = widget.phoneNumber;
                final rId = (_restaurant['restaurantId'] ?? _restaurant['id'] ?? _restaurant['_id'] ?? '').toString();
                try {
                  await ApiService.logout(mobile: phone, role: 'Restaurant Partner');
                } catch (_) {}
                try {
                  await _foodService.logoutPartner(restaurantId: rId, phone: phone);
                } catch (_) {}
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('is_logged_in', false);
                await prefs.remove('is_logged_in');
                await prefs.remove('user_role');
                await prefs.remove('user_name');
                await prefs.remove('phone_number');
                await prefs.remove('jwt_token');
                await prefs.remove('auth_token');
                await prefs.remove('mock_uid');
                await prefs.remove('restaurant_data');
                await prefs.remove('partner_phone');
                ApiClient.setAuthToken(null);
                FirebaseService.setMockUid(null);
                if (!mounted) return;
                nav.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(initialRole: 'Restaurant Partner'),
                  ),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF64748B)),
              label: Text(
                'Log Out / Switch Account',
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F1E4A)),
            ),
          ),
        ],
      ),
    );
  }
}
