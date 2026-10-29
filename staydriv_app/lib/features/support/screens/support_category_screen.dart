import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../../core/booking_manager.dart';
import '../models/support_ticket_model.dart';
import '../services/support_service.dart';
import 'my_support_tickets_screen.dart';
import 'ticket_detail_screen.dart';

class SupportCategoryScreen extends StatefulWidget {
  final String category; // 'booking', 'payment', 'safety', 'complaint'
  final String userType; // 'customer' or 'pilot'

  const SupportCategoryScreen({
    super.key,
    required this.category,
    this.userType = 'customer',
  });

  @override
  State<SupportCategoryScreen> createState() => _SupportCategoryScreenState();
}

class _SupportCategoryScreenState extends State<SupportCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _rideIdController = TextEditingController();

  String _selectedSubcategory = '';
  bool _isSubmitting = false;
  bool _attachActiveRide = false;
  String? _detectedActiveRideId;

  @override
  void initState() {
    super.initState();
    _initSubcategories();
    _checkActiveRide();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    _rideIdController.dispose();
    super.dispose();
  }

  void _checkActiveRide() {
    final active = BookingManager().activeBooking;
    final rId = active?['bookingId']?.toString() ??
        active?['id']?.toString() ??
        active?['_id']?.toString();
    if (rId != null && rId.isNotEmpty) {
      _detectedActiveRideId = rId;
      _attachActiveRide = true;
      _rideIdController.text = rId;
    }
  }

  List<String> get _subcategories {
    switch (widget.category) {
      case 'booking':
        return [
          'Driver not arriving / Delayed',
          'Ride cancelled unexpectedly',
          'Wrong pickup or drop location',
          'Vehicle didn\'t match details',
          'Other booking issue',
        ];
      case 'payment':
        return [
          'Fare charged was incorrect',
          'Paid twice / Double deduction',
          'Refund not received',
          'Coupon / Discount issue',
          'Digital payment failed but money debited',
        ];
      case 'safety':
        return [
          'Rash / Dangerous driving',
          'Misbehavior / Harassment',
          'Vehicle condition unsafe',
          'Route deviation / Suspicious detour',
          'Accident or medical emergency',
        ];
      case 'complaint':
        if (widget.userType == 'pilot') {
          return [
            'Passenger was rude or abusive',
            'Passenger refused to pay fare',
            'Passenger delayed excessively at pickup',
            'Passenger demanded unsafe route / overloading',
            'Passenger caused damage to vehicle',
          ];
        } else {
          return [
            'Driver was rude or unprofessional',
            'Driver demanded extra cash',
            'Vehicle was not clean / bad odor',
            'AC was not switched on',
            'Driver refused to start or finish trip',
          ];
        }
      default:
        return [
          'General query',
          'App feedback',
          'Account issue',
        ];
    }
  }

  void _initSubcategories() {
    if (_subcategories.isNotEmpty) {
      _selectedSubcategory = _subcategories.first;
      _subjectController.text = _selectedSubcategory;
    }
  }

  String get _categoryTitle {
    switch (widget.category) {
      case 'booking':
        return 'Booking Issue';
      case 'payment':
        return 'Payment & Refund';
      case 'safety':
        return 'Safety Concerns';
      case 'complaint':
        return widget.userType == 'pilot' ? 'Customer Complaints' : 'Driver Complaints';
      default:
        return 'Support Request';
    }
  }

  String get _categorySubtitle {
    switch (widget.category) {
      case 'booking':
        return 'Problems with booking, driver arrival, or cancellations';
      case 'payment':
        return 'Wallet issues, transaction failures, or fare discrepancies';
      case 'safety':
        return 'Emergency reporting and safety protocols (Highest Priority)';
      case 'complaint':
        return widget.userType == 'pilot'
            ? 'Report passenger misconduct, fare refusal, or vehicle issues'
            : 'Feedback on ride quality, driver conduct, or vehicle issues';
      default:
        return 'Tell us how we can help you';
    }
  }

  IconData get _categoryIcon {
    switch (widget.category) {
      case 'booking':
        return Icons.calendar_today_rounded;
      case 'payment':
        return Icons.account_balance_wallet_outlined;
      case 'safety':
        return Icons.shield_outlined;
      case 'complaint':
        return Icons.report_problem_outlined;
      default:
        return Icons.help_outline;
    }
  }

  Color get _categoryColor {
    switch (widget.category) {
      case 'safety':
        return Colors.red.shade700;
      case 'payment':
        return Colors.amber.shade800;
      case 'complaint':
        return Colors.purple.shade700;
      default:
        return AppTheme.primaryColor;
    }
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final rideId = _rideIdController.text.trim().isNotEmpty
          ? _rideIdController.text.trim()
          : null;

      final ticket = await SupportService().createTicket(
        category: widget.category,
        subcategory: _selectedSubcategory,
        subject: _subjectController.text.trim(),
        description: _descriptionController.text.trim(),
        rideId: rideId,
        userType: widget.userType,
        priority: widget.category == 'safety' ? 'URGENT' : 'MEDIUM',
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        _showSuccessDialog(ticket);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showSuccessDialog(SupportTicket ticket) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, size: 54, color: Colors.green.shade600),
            ),
            const SizedBox(height: 16),
            Text(
              'Ticket Submitted!',
              style: GoogleFonts.hankenGrotesk(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
              ),
              child: Text(
                'Ticket ID: ${ticket.ticketId}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Your request has been received. Our support team typically responds within 15 minutes.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TicketDetailScreen(ticket: ticket),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('View Ticket & Chat'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('Back to Home'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSafety = widget.category == 'safety';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _categoryTitle,
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MySupportTicketsScreen()),
              );
            },
            icon: const Icon(Icons.list_alt, size: 18),
            label: const Text('My Requests'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Header Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _categoryColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _categoryColor.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: _categoryColor.withOpacity(0.15),
                      child: Icon(_categoryIcon, color: _categoryColor, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _categoryTitle,
                            style: GoogleFonts.hankenGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.onSurfaceColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _categorySubtitle,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Emergency SOS callout if Safety
              if (isSafety) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'In Immediate Danger?',
                              style: GoogleFonts.hankenGrotesk(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                            Text(
                              'Please call local police (112) or tap to reach StayDriv 24/7 Helpline immediately.',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.red.shade800),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => SupportService().callEmergencyHelpline(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Call SOS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Subcategory Selection
              Text(
                'Select Specific Issue',
                style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Column(
                children: _subcategories.map((sub) {
                  final isSelected = _selectedSubcategory == sub;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withOpacity(0.06)
                          : AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.outlineVariant.withOpacity(0.4),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: isSelected ? AppTheme.primaryColor : AppTheme.outlineColor,
                        size: 20,
                      ),
                      title: Text(
                        sub,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          color: isSelected ? AppTheme.primaryColor : AppTheme.onSurfaceColor,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedSubcategory = sub;
                          _subjectController.text = sub;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // Ride Attachment
              Text(
                'Ride Reference (Optional)',
                style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_detectedActiveRideId != null) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Attach current active ride (#$_detectedActiveRideId)',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  value: _attachActiveRide,
                  onChanged: (val) {
                    setState(() {
                      _attachActiveRide = val ?? false;
                      _rideIdController.text = _attachActiveRide ? (_detectedActiveRideId ?? '') : '';
                    });
                  },
                ),
              ] else ...[
                TextFormField(
                  controller: _rideIdController,
                  decoration: InputDecoration(
                    hintText: 'Enter Ride ID (e.g. BK-123456)',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.outlineColor),
                    prefixIcon: const Icon(Icons.directions_car_outlined, size: 20),
                    filled: true,
                    fillColor: AppTheme.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.4)),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Subject Field
              Text(
                'Subject',
                style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _subjectController,
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter a subject' : null,
                decoration: InputDecoration(
                  hintText: 'Brief summary of the issue',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.outlineColor),
                  filled: true,
                  fillColor: AppTheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.4)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Description Field
              Text(
                'Describe the Issue in Detail',
                style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please describe the issue';
                  }
                  if (val.trim().length < 10) {
                    return 'Please provide more details (minimum 10 characters)';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: 'Explain what happened, including time, location, or amount...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.outlineColor),
                  filled: true,
                  fillColor: AppTheme.surfaceContainerLow,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.outlineVariant.withOpacity(0.4)),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitTicket,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _categoryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 1,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Text(
                          'Submit Support Request',
                          style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
