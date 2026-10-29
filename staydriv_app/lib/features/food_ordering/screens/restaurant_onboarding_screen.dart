import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/food_service.dart';
import '../widgets/location_pin_picker_dialog.dart';
import 'restaurant_application_status_screen.dart';

class RestaurantOnboardingScreen extends StatefulWidget {
  final String phoneNumber;
  final String? initialOwnerName;

  const RestaurantOnboardingScreen({
    super.key,
    required this.phoneNumber,
    this.initialOwnerName,
  });

  @override
  State<RestaurantOnboardingScreen> createState() => _RestaurantOnboardingScreenState();
}

class _RestaurantOnboardingScreenState extends State<RestaurantOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final FoodService _foodService = FoodService();

  late TextEditingController _nameController;
  late TextEditingController _ownerController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;
  late TextEditingController _openingHoursController;
  late TextEditingController _fssaiController;
  late TextEditingController _bankAccountController;
  late TextEditingController _upiIdController;

  double _restaurantLat = 0.0;
  double _restaurantLng = 0.0;
  String _restaurantLocationDetails = '';

  final List<String> _availableCuisines = [
    'Biryani',
    'South Indian',
    'North Indian',
    'Pizza',
    'Burgers',
    'Chinese',
    'Snacks',
    'Desserts',
    'Rolls',
    'Beverages'
  ];

  final Set<String> _selectedCuisines = {'Biryani', 'South Indian'};
  bool _isVegOnly = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _ownerController = TextEditingController(text: widget.initialOwnerName ?? '');
    _phoneController = TextEditingController(text: widget.phoneNumber);
    _emailController = TextEditingController();
    _addressController = TextEditingController();
    _openingHoursController = TextEditingController(text: '10:00 AM - 11:00 PM');
    _fssaiController = TextEditingController();
    _bankAccountController = TextEditingController();
    _upiIdController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ownerController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _openingHoursController.dispose();
    _fssaiController.dispose();
    _bankAccountController.dispose();
    _upiIdController.dispose();
    super.dispose();
  }

  Future<void> _openLocationPinPicker() async {
    final result = await LocationPinPickerDialog.show(
      context,
      initialLat: _restaurantLat != 0.0 ? _restaurantLat : null,
      initialLng: _restaurantLng != 0.0 ? _restaurantLng : null,
      initialAddress: _addressController.text.trim(),
      initialDetails: _restaurantLocationDetails,
      title: 'Set Restaurant Location on Map',
      confirmButtonText: 'Confirm Exact Restaurant Location',
      detailsHint: 'Restaurant entrance / delivery pickup counter / floor...',
    );

    if (result == null || !mounted) return;

    setState(() {
      _restaurantLat = result.latitude;
      _restaurantLng = result.longitude;
      _addressController.text = result.address;
      _restaurantLocationDetails = result.locationDetails;
    });
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (_restaurantLat == 0.0 || _restaurantLng == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please set the exact restaurant location on the map so pilots can navigate for pickups.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      _openLocationPinPicker();
      return;
    }

    if (_selectedCuisines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one cuisine type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await _foodService.registerPartner(
        name: _nameController.text.trim(),
        ownerName: _ownerController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : '${_phoneController.text.trim()}@partner.staydriv.com',
        address: _addressController.text.trim(),
        cuisines: _selectedCuisines.toList(),
        openingHours: _openingHoursController.text.trim(),
        fssaiNumber: _fssaiController.text.trim(),
        bankAccount: _bankAccountController.text.trim(),
        upiId: _upiIdController.text.trim(),
        isVegOnly: _isVegOnly,
        lat: _restaurantLat,
        lng: _restaurantLng,
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (res['success'] == true) {
        final restaurant = res['restaurant'] as Map<String, dynamic>? ?? {};
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantApplicationStatusScreen(
              restaurantData: restaurant,
              phoneNumber: _phoneController.text.trim(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to register restaurant'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting registration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Restaurant Partner Onboarding',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F1E4A),
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F1E4A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E60FF), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E60FF).withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Grow Your Food Business',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Join StayDriv Partner Network with 0% onboarding fee and fast payouts.',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('Basic Restaurant Details'),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _nameController,
                label: 'Restaurant Name *',
                hint: 'e.g. Royal Bawarchi Kitchen',
                icon: Icons.storefront_rounded,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter restaurant name' : null,
              ),

              const SizedBox(height: 14),
              _buildTextField(
                controller: _ownerController,
                label: 'Owner / Manager Name *',
                hint: 'e.g. Rajesh Kumar',
                icon: Icons.person_outline_rounded,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter owner name' : null,
              ),

              const SizedBox(height: 14),
              _buildTextField(
                controller: _phoneController,
                label: 'Verified Mobile Number *',
                hint: '10-digit mobile number',
                icon: Icons.phone_android_rounded,
                readOnly: true,
              ),

              const SizedBox(height: 14),
              _buildTextField(
                controller: _emailController,
                label: 'Business Email',
                hint: 'partner@restaurant.com',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('Location & Address'),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _addressController,
                label: 'Complete Restaurant Address *',
                hint: 'Shop No, Street, Landmark, Area, City',
                icon: Icons.place_outlined,
                maxLines: 2,
                validator: (v) => (v == null || v.trim().length < 8) ? 'Please enter full restaurant address' : null,
              ),

              const SizedBox(height: 10),

              // Interactive Exact Location on Map Button & Confirmed Coordinates Badge
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                      ? const Color(0xFF10B981).withOpacity(0.08)
                      : const Color(0xFFEF4444).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                        ? const Color(0xFF10B981).withOpacity(0.4)
                        : const Color(0xFFEF4444).withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                              ? Icons.location_on_rounded
                              : Icons.location_off_rounded,
                          color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Exact Map Location & Delivery Pickup Pin *',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                                      ? const Color(0xFF047857)
                                      : const Color(0xFFB91C1C),
                                ),
                              ),
                              Text(
                                (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                                    ? 'GPS: ${_restaurantLat.toStringAsFixed(6)}, ${_restaurantLng.toStringAsFixed(6)} (Exact Confirmed)'
                                    : '⚠️ Map pin required! Pilots need this exact pin to navigate to your restaurant.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                                      ? const Color(0xFF065F46)
                                      : const Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_restaurantLocationDetails.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Entrance / Landmark: $_restaurantLocationDetails',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.black87),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _openLocationPinPicker,
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: Text(
                          (_restaurantLat != 0.0 && _restaurantLng != 0.0)
                              ? 'Edit Restaurant Location on Map'
                              : 'Set Restaurant Location on Map *',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('Cuisines & Operating Hours'),
              const SizedBox(height: 10),

              Text(
                'Select Cuisines Offered:',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF334155)),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableCuisines.map((cuisine) {
                  final isSelected = _selectedCuisines.contains(cuisine);
                  return FilterChip(
                    label: Text(cuisine),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCuisines.add(cuisine);
                        } else {
                          _selectedCuisines.remove(cuisine);
                        }
                      });
                    },
                    selectedColor: const Color(0xFF1E60FF).withOpacity(0.15),
                    checkmarkColor: const Color(0xFF1E60FF),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFF475569),
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF1E60FF) : const Color(0xFFE2E8F0),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              _buildTextField(
                controller: _openingHoursController,
                label: 'Opening Hours *',
                hint: 'e.g. 10:00 AM - 11:00 PM',
                icon: Icons.access_time_rounded,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter opening hours' : null,
              ),

              const SizedBox(height: 14),

              SwitchListTile.adaptive(
                value: _isVegOnly,
                onChanged: (val) => setState(() => _isVegOnly = val),
                title: Text(
                  'Pure Vegetarian Restaurant',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                ),
                subtitle: Text(
                  'Serve vegetarian dishes only with 100% veg kitchen',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                activeColor: Colors.green,
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 24),
              _buildSectionTitle('Compliance & Payouts'),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _fssaiController,
                label: 'FSSAI Registration / License Number',
                hint: '14-digit FSSAI number',
                icon: Icons.verified_outlined,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 14),

              _buildTextField(
                controller: _upiIdController,
                label: 'UPI ID for Daily Settlement',
                hint: 'restaurant@upi / 9849012345@paytm',
                icon: Icons.account_balance_wallet_outlined,
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E60FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: _isSubmitting ? null : _submitRegistration,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          'Submit Application for Approval',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                ),
              ),

              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Approval SLA: 24 Hours • StayDriv Partner Terms Apply',
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFF94A3B8)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF0F1E4A),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F1E4A), fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
        filled: true,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
        labelStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
        hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1E60FF), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
