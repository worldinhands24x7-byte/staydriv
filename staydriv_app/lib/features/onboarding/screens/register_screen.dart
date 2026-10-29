import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme.dart';
import '../../../core/firebase_service.dart';
import '../../../core/api_client.dart';
import '../../../core/network_config.dart';
import '../../../core/booking_manager.dart';
import '../../../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../dashboard/screens/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  final String phoneNumber;
  final String? initialRole;
  const RegisterScreen({super.key, required this.phoneNumber, this.initialRole});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _vehicleMakeController = TextEditingController();
  final TextEditingController _vehicleModelController = TextEditingController();
  final TextEditingController _vehicleColorController = TextEditingController();
  final TextEditingController _vehicleRegDateController = TextEditingController();
  final TextEditingController _insuranceExpiryController = TextEditingController();
  final TextEditingController _referralController = TextEditingController();
  final TextEditingController _ownerPhoneController = TextEditingController();
  final TextEditingController _driverNameController = TextEditingController();
  final TextEditingController _driverPhoneController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  final TextEditingController _licenseNumberController = TextEditingController();
  final TextEditingController _aadhaarNumberController = TextEditingController();
  String _twoWheelerType = 'Bike'; // 'Bike' or 'Scooty'
  String _vehicleSubtype = 'Bike'; // Subtype e.g. Scooty, Tata Ace, 14ft-19ft, Sedan, etc.
  bool _declarationAccepted = true;

  // Supported vehicle colours
  static const List<String> _vehicleColours = [
    'White',
    'Black',
    'Silver',
    'Grey',
    'Red',
    'Blue',
    'Yellow',
    'Brown',
    'Other (Custom)',
  ];

  // Step 3 / Replace Driver OTP Verification State
  final List<TextEditingController> _registrationOtpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _isRegistrationOtpVerified = false;
  int _otpCountdown = 0;
  Timer? _otpTimer;
  String? _otpVerificationSessionId;
  String? _sentOtpMobile;

  // Pilot Navigation & Mode State
  // _pilotCurrentStep: 0 = Step 1 (Personal Details), 1 = Step 2 (Vehicle Details), 2 = Step 3 (Review & Submit)
  int _pilotCurrentStep = 0;
  int _pilotMode = 0; // 0 = New Registration, 1 = Replace/Update/Modify Driver
  bool _driverSameAsOwner = true;

  late String _userRole; // Customer or Driver or Admin
  String _selectedVehicle = 'Motorcycle/Bike'; // Default selected vehicle
  String _selectedVehicleColor = 'White';
  bool _isCustomColor = false;
  bool _isLoading = false;
  String _loadingMessage = 'Processing registration...';
  String _adminType = 'Staff'; // Staff or Admin
  String? _mockPhoneNumber;
  bool _obscurePassword = true;

  // Document Upload State (Bytes & Metadata)
  Uint8List? _aadhaarFrontBytes;
  Uint8List? _aadhaarBackBytes;
  Uint8List? _panFrontBytes;
  Uint8List? _panBackBytes;
  Uint8List? _licenseFrontBytes;
  Uint8List? _licenseBackBytes;
  Uint8List? _rcFrontBytes;
  Uint8List? _rcBackBytes;
  Uint8List? _insuranceBytes;
  Uint8List? _photoBytes;
  Uint8List? _fitnessBytes;
  Uint8List? _permitBytes;

  final Map<String, String> _docFileNames = {};
  final Map<String, String> _docFileSizes = {};

  bool get _vehicleNeedsExtraDocs {
    return _selectedVehicle == 'Hatchback Car' ||
        _selectedVehicle == 'Sedan' ||
        _selectedVehicle == 'SUV' ||
        _selectedVehicle == 'Car XL' ||
        _selectedVehicle == 'XL Cab' ||
        _selectedVehicle == 'Mini Truck' ||
        _selectedVehicle == 'Heavy Truck' ||
        _selectedVehicle == 'Car';
  }

  bool get _isBikeSelected => _selectedVehicle == 'Motorcycle/Bike' || _selectedVehicle == 'Scooty' || _selectedVehicle == 'Bike';
  bool get _isAutoSelected => _selectedVehicle == 'Auto Rickshaw' || _selectedVehicle == 'Auto';
  bool get _isCarSelected => _selectedVehicle == 'Hatchback Car' ||
      _selectedVehicle == 'Sedan' ||
      _selectedVehicle == 'SUV' ||
      _selectedVehicle == 'Car';
  bool get _isCarXlSelected =>
      _selectedVehicle == 'Car XL' ||
      _selectedVehicle == 'XL Cab' ||
      _selectedVehicle == 'Innova / Crysta' ||
      _selectedVehicle == 'Ertiga / XL6' ||
      _selectedVehicle == 'Carens / SUV XL';
  bool get _isMiniTruckSelected => _selectedVehicle == 'Mini Truck' || _selectedVehicle == 'Pickup';
  bool get _isHeavyTruckSelected => _selectedVehicle == 'Heavy Truck' || _selectedVehicle == 'Truck';

  @override
  void initState() {
    super.initState();
    _userRole = widget.initialRole ?? 'Customer';
    final initialPhone = widget.phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
    _ownerPhoneController.text = initialPhone;
    _driverPhoneController.text = initialPhone;
    _driverNameController.text = '';

    if (_userRole == 'Admin') {
      _nameController.text = _adminType == 'Staff' ? 'StayDriv Staff' : 'StayDriv Admin';
      _passwordController.clear();
    }

    if (_userRole == 'Driver') {
      _loadDraft();
    }
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pilot_reg_vehicle', _selectedVehicle);
      await prefs.setString('pilot_reg_name', _nameController.text);
      await prefs.setString('pilot_reg_dob', _dobController.text);
      await prefs.setString('pilot_reg_address', _addressController.text);
      await prefs.setString('pilot_reg_vehicle_number', _vehicleNumberController.text);
      await prefs.setString('pilot_reg_vehicle_make', _vehicleMakeController.text);
      await prefs.setString('pilot_reg_vehicle_model', _vehicleModelController.text);
      await prefs.setString('pilot_reg_vehicle_color', _selectedVehicleColor);
      await prefs.setString('pilot_reg_custom_color', _vehicleColorController.text);
      await prefs.setBool('pilot_reg_is_custom_color', _isCustomColor);
      await prefs.setString('pilot_reg_vehicle_reg_date', _vehicleRegDateController.text);
      await prefs.setString('pilot_reg_insurance_expiry', _insuranceExpiryController.text);
      await prefs.setString('pilot_reg_referral', _referralController.text);
      await prefs.setString('pilot_reg_owner_phone', _ownerPhoneController.text);
      await prefs.setString('pilot_reg_owner_name', _ownerNameController.text);
      await prefs.setString('pilot_reg_driver_name', _driverNameController.text);
      await prefs.setString('pilot_reg_driver_phone', _driverPhoneController.text);
      await prefs.setString('pilot_reg_license_number', _licenseNumberController.text);
      await prefs.setString('pilot_reg_aadhaar_number', _aadhaarNumberController.text);
      await prefs.setString('pilot_reg_two_wheeler_type', _twoWheelerType);
      await prefs.setString('pilot_reg_vehicle_subtype', _vehicleSubtype);
      await prefs.setInt('pilot_reg_step', _pilotCurrentStep);
      await prefs.setInt('pilot_reg_mode', _pilotMode);
      await prefs.setBool('pilot_reg_otp_verified', _isRegistrationOtpVerified);
    } catch (_) {}
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('pilot_reg_vehicle');
      if (v != null && v.isNotEmpty) _selectedVehicle = v;
      final vs = prefs.getString('pilot_reg_vehicle_subtype');
      if (vs != null && vs.isNotEmpty) _vehicleSubtype = vs;
      final n = prefs.getString('pilot_reg_name');
      if (n != null && n.isNotEmpty) _nameController.text = n;
      final d = prefs.getString('pilot_reg_dob');
      if (d != null && d.isNotEmpty) _dobController.text = d;
      final a = prefs.getString('pilot_reg_address');
      if (a != null && a.isNotEmpty) _addressController.text = a;
      final vn = prefs.getString('pilot_reg_vehicle_number');
      if (vn != null && vn.isNotEmpty) _vehicleNumberController.text = vn;
      final vMake = prefs.getString('pilot_reg_vehicle_make');
      if (vMake != null && vMake.isNotEmpty) _vehicleMakeController.text = vMake;
      final vModel = prefs.getString('pilot_reg_vehicle_model');
      if (vModel != null && vModel.isNotEmpty) _vehicleModelController.text = vModel;
      final vCol = prefs.getString('pilot_reg_vehicle_color');
      if (vCol != null && vCol.isNotEmpty) _selectedVehicleColor = vCol;
      final cCol = prefs.getString('pilot_reg_custom_color');
      if (cCol != null && cCol.isNotEmpty) _vehicleColorController.text = cCol;
      final isCust = prefs.getBool('pilot_reg_is_custom_color');
      if (isCust != null) _isCustomColor = isCust;
      final vDate = prefs.getString('pilot_reg_vehicle_reg_date');
      if (vDate != null && vDate.isNotEmpty) _vehicleRegDateController.text = vDate;
      final insDate = prefs.getString('pilot_reg_insurance_expiry');
      if (insDate != null && insDate.isNotEmpty) _insuranceExpiryController.text = insDate;
      final r = prefs.getString('pilot_reg_referral');
      if (r != null && r.isNotEmpty) _referralController.text = r;
      final op = prefs.getString('pilot_reg_owner_phone');
      if (op != null && op.isNotEmpty) _ownerPhoneController.text = op;
      final on = prefs.getString('pilot_reg_owner_name');
      if (on != null && on.isNotEmpty) _ownerNameController.text = on;
      final dn = prefs.getString('pilot_reg_driver_name');
      if (dn != null && dn.isNotEmpty) _driverNameController.text = dn;
      final dp = prefs.getString('pilot_reg_driver_phone');
      if (dp != null && dp.isNotEmpty) _driverPhoneController.text = dp;
      final ln = prefs.getString('pilot_reg_license_number');
      if (ln != null && ln.isNotEmpty) _licenseNumberController.text = ln;
      final an = prefs.getString('pilot_reg_aadhaar_number');
      if (an != null && an.isNotEmpty) _aadhaarNumberController.text = an;
      final tw = prefs.getString('pilot_reg_two_wheeler_type');
      if (tw != null && tw.isNotEmpty) _twoWheelerType = tw;
      final step = prefs.getInt('pilot_reg_step');
      if (step != null && step >= 0 && step <= 2) {
        _pilotCurrentStep = step;
      }
      final mode = prefs.getInt('pilot_reg_mode');
      if (mode != null && (mode == 0 || mode == 1)) {
        _pilotMode = mode;
      }
      final otpVer = prefs.getBool('pilot_reg_otp_verified');
      if (otpVer != null) _isRegistrationOtpVerified = otpVer;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pilot_reg_vehicle');
      await prefs.remove('pilot_reg_name');
      await prefs.remove('pilot_reg_dob');
      await prefs.remove('pilot_reg_address');
      await prefs.remove('pilot_reg_vehicle_number');
      await prefs.remove('pilot_reg_vehicle_make');
      await prefs.remove('pilot_reg_vehicle_model');
      await prefs.remove('pilot_reg_vehicle_color');
      await prefs.remove('pilot_reg_custom_color');
      await prefs.remove('pilot_reg_is_custom_color');
      await prefs.remove('pilot_reg_vehicle_reg_date');
      await prefs.remove('pilot_reg_insurance_expiry');
      await prefs.remove('pilot_reg_referral');
      await prefs.remove('pilot_reg_owner_phone');
      await prefs.remove('pilot_reg_owner_name');
      await prefs.remove('pilot_reg_driver_name');
      await prefs.remove('pilot_reg_driver_phone');
      await prefs.remove('pilot_reg_license_number');
      await prefs.remove('pilot_reg_aadhaar_number');
      await prefs.remove('pilot_reg_two_wheeler_type');
      await prefs.remove('pilot_reg_step');
      await prefs.remove('pilot_reg_mode');
      await prefs.remove('pilot_reg_otp_verified');
    } catch (_) {}
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _scrollController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _vehicleNumberController.dispose();
    _vehicleMakeController.dispose();
    _vehicleModelController.dispose();
    _vehicleColorController.dispose();
    _vehicleRegDateController.dispose();
    _insuranceExpiryController.dispose();
    _referralController.dispose();
    _ownerPhoneController.dispose();
    _ownerNameController.dispose();
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _licenseNumberController.dispose();
    _aadhaarNumberController.dispose();
    for (var c in _registrationOtpControllers) {
      c.dispose();
    }
    for (var f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // --- DATE PICKER HELPER ---
  Future<void> _selectDate(
    TextEditingController controller, {
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: firstDate ?? DateTime(1950),
      lastDate: lastDate ?? DateTime(2040),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1D4ED8),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
      _saveDraft();
    }
  }

  // --- DOCUMENT PICKER WITH FORMAT & SIZE VALIDATION (JPG, JPEG, PNG, PDF) ---
  Future<void> _pickDocument(String docType) async {
    try {
      final bool allowPdf = docType == 'insurance' || docType == 'rc_front' || docType == 'rc_back';
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: allowPdf ? FileType.custom : FileType.image,
        allowedExtensions: allowPdf ? ['jpg', 'jpeg', 'png', 'pdf'] : null,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        final ext = file.extension?.toLowerCase() ?? '';

        if (ext.isNotEmpty && ext != 'jpg' && ext != 'jpeg' && ext != 'png' && ext != 'webp' && ext != 'pdf') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid format. Allowed formats: JPG, JPEG, PNG, PDF.'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        Uint8List? fileBytes;
        if (kIsWeb) {
          fileBytes = file.bytes;
        } else {
          final path = file.path;
          if (path != null) {
            fileBytes = await io.File(path).readAsBytes();
          }
        }

        if (fileBytes != null) {
          final int bytesLen = fileBytes.length;
          // Validate maximum file size: 10 MB limit
          if (bytesLen > 10 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('File size exceeds 10 MB limit. Please select a smaller document.'),
                  backgroundColor: AppTheme.errorColor,
                ),
              );
            }
            return;
          }

          final String fileName = file.name;
          final String sizeStr = bytesLen > 1024 * 1024
              ? '${(bytesLen / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(bytesLen / 1024).toStringAsFixed(1)} KB';

          setState(() {
            _docFileNames[docType] = fileName;
            _docFileSizes[docType] = sizeStr;

            if (docType == 'aadhaar_front') {
              _aadhaarFrontBytes = fileBytes;
            } else if (docType == 'aadhaar_back') {
              _aadhaarBackBytes = fileBytes;
            } else if (docType == 'pan_front') {
              _panFrontBytes = fileBytes;
            } else if (docType == 'pan_back') {
              _panBackBytes = fileBytes;
            } else if (docType == 'license_front') {
              _licenseFrontBytes = fileBytes;
            } else if (docType == 'license_back') {
              _licenseBackBytes = fileBytes;
            } else if (docType == 'rc_front') {
              _rcFrontBytes = fileBytes;
            } else if (docType == 'rc_back') {
              _rcBackBytes = fileBytes;
            } else if (docType == 'insurance') {
              _insuranceBytes = fileBytes;
            } else if (docType == 'photo') {
              _photoBytes = fileBytes;
            } else if (docType == 'fitness') {
              _fitnessBytes = fileBytes;
            } else if (docType == 'permit') {
              _permitBytes = fileBytes;
            }
          });

          _saveDraft();

          if (mounted) {
            final readableTitle = docType.replaceAll('_', ' ').toUpperCase();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('$readableTitle document selected: $fileName ($sizeStr)')),
                  ],
                ),
                backgroundColor: const Color(0xFF16A34A),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select document: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  // --- STEP 1 VALIDATION (VEHICLE DETAILS) & ADVANCEMENT TO STEP 2 ---
  void _validateAndProceedToScreen2() {
    // 1. Validate Vehicle Registration Number
    final vehPlate = _vehicleNumberController.text.trim().toUpperCase();
    if (vehPlate.isEmpty || vehPlate.length < 5) {
      _showWarningSnackBar('Please enter a valid Vehicle Registration Number (e.g. AP 07 AX 6057)');
      return;
    }

    // 2. Validate Vehicle Registration Date (D.O.R.)
    if (_vehicleRegDateController.text.trim().isEmpty) {
      _showWarningSnackBar('Please select Vehicle Date of Registration (D.O.R.)');
      return;
    }

    // 3. Validate Vehicle Colour
    final color = _isCustomColor ? _vehicleColorController.text.trim() : _selectedVehicleColor;
    if (color.isEmpty) {
      _showWarningSnackBar('Please specify Vehicle Colour');
      return;
    }

    // 4. Validate Vehicle Make & Model
    if (_vehicleMakeController.text.trim().isEmpty) {
      _showWarningSnackBar('Please enter Vehicle Make (e.g. Hero, Honda, Maruti)');
      return;
    }
    if (_vehicleModelController.text.trim().isEmpty) {
      _showWarningSnackBar('Please enter Vehicle Model (e.g. Splendor, Activa, Swift)');
      return;
    }

    // 5. Validate Vehicle Insurance Copy & Expiry
    if (_insuranceBytes == null) {
      _showWarningSnackBar('Please upload Vehicle Insurance Copy (PDF or Image)');
      return;
    }
    if (_insuranceExpiryController.text.trim().isEmpty) {
      _showWarningSnackBar('Please select Insurance Expiry Date');
      return;
    }

    // 6. Validate Vehicle RC Front & Back
    if (_rcFrontBytes == null) {
      _showWarningSnackBar('Please upload Vehicle RC - Front');
      return;
    }
    if (_rcBackBytes == null) {
      _showWarningSnackBar('Please upload Vehicle RC - Back');
      return;
    }

    // 7. Validate Owner details if owner is different from driver
    if (!_driverSameAsOwner) {
      if (_ownerNameController.text.trim().isEmpty) {
        _showWarningSnackBar('Please enter Vehicle Owner Full Name');
        return;
      }
      final op = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
      if (op.length < 10) {
        _showWarningSnackBar('Please enter a valid 10-digit Vehicle Owner Phone Number');
        return;
      }
    }

    // 8. Commercial Vehicle Extra Documents (Fitness & Permit if required)
    if (_vehicleNeedsExtraDocs) {
      if (_fitnessBytes == null) {
        _showWarningSnackBar('Please upload Fitness Certificate for commercial vehicle');
        return;
      }
      if (_permitBytes == null) {
        _showWarningSnackBar('Please upload Vehicle Permit for commercial vehicle');
        return;
      }
    }

    // All Step 1 validations passed -> advance to Step 2
    setState(() {
      _pilotCurrentStep = 1;
    });
    _saveDraft();
    _scrollToTop();
  }

  // --- STEP 2 VALIDATION (OWNER & DRIVER VERIFICATION) & ADVANCEMENT TO STEP 3 ---
  void _validateAndProceedToScreen3() {
    // 1. Validate Pilot/Driver Full Name
    if (_nameController.text.trim().isEmpty) {
      _showWarningSnackBar('Please enter Driver Full Name');
      return;
    }

    // 2. Validate Owner Mobile Number & OTP Verification
    final ownerPhone = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (ownerPhone.length < 10) {
      _showWarningSnackBar('Please enter a valid 10-digit Owner Mobile Number');
      return;
    }
    if (!_isRegistrationOtpVerified) {
      _showWarningSnackBar('Please verify the Owner Mobile Number with OTP before continuing');
      return;
    }

    // 3. Validate Driver Mobile Number
    final driverPhone = _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (driverPhone.length < 10) {
      _showWarningSnackBar('Please enter a valid 10-digit Driver Mobile Number');
      return;
    }

    // 4. Validate Driving Licence Number & Uploads
    if (_licenseNumberController.text.trim().isEmpty) {
      _showWarningSnackBar('Please enter Driving Licence Number');
      return;
    }
    if (_licenseFrontBytes == null) {
      _showWarningSnackBar('Please upload Driving Licence - Front');
      return;
    }
    if (_licenseBackBytes == null) {
      _showWarningSnackBar('Please upload Driving Licence - Back');
      return;
    }

    // 5. Validate Aadhaar Card Number & Uploads
    final aadhaar = _aadhaarNumberController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (aadhaar.length < 12) {
      _showWarningSnackBar('Please enter a valid 12-digit Aadhaar Card Number');
      return;
    }
    if (_aadhaarFrontBytes == null) {
      _showWarningSnackBar('Please upload Aadhaar Card - Front');
      return;
    }
    if (_aadhaarBackBytes == null) {
      _showWarningSnackBar('Please upload Aadhaar Card - Back');
      return;
    }

    // 6. Validate PAN Card Uploads
    if (_panFrontBytes == null) {
      _showWarningSnackBar('Please upload PAN Card - Front');
      return;
    }
    if (_panBackBytes == null) {
      _showWarningSnackBar('Please upload PAN Card - Back');
      return;
    }

    // 7. Validate Driver Profile Photo
    if (_photoBytes == null) {
      _showWarningSnackBar('Please upload Driver Profile Photo');
      return;
    }

    // 8. Validate Residential Address
    if (_addressController.text.trim().isEmpty) {
      _showWarningSnackBar('Please enter Residential Address');
      return;
    }

    // All Step 2 validations passed -> advance to Step 3
    setState(() {
      _pilotCurrentStep = 2;
    });
    _saveDraft();
    _scrollToTop();
  }

  void _showWarningSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.errorColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- REAL OTP GENERATION VIA TTBS DLT PRODUCTION SMS GATEWAY ---
  Future<void> _requestRegistrationOtp() async {
    final targetPhone = (_pilotMode == 1 || !_driverSameAsOwner)
        ? _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim()
        : _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();

    if (targetPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number to receive OTP'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isSendingOtp = true;
    });

    try {
      final res = await ApiService.sendOtp(targetPhone, role: 'PILOT');
      if (res['success'] == true) {
        setState(() {
          _sentOtpMobile = targetPhone;
          _otpVerificationSessionId = res['verificationSessionId'];
          _otpCountdown = 60;
          for (var c in _registrationOtpControllers) {
            c.clear();
          }
        });

        _startOtpCountdown();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Verification code sent via SMS to +91 $targetPhone'),
              backgroundColor: const Color(0xFF16A34A),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        final errMsg = res['message'] ?? 'Failed to send verification code. Please try again.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errMsg),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error sending OTP: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingOtp = false;
        });
      }
    }
  }

  void _startOtpCountdown() {
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_otpCountdown > 0) {
        setState(() {
          _otpCountdown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  // --- VERIFY REAL SMS OTP WITH STAYDRIV BACKEND ---
  Future<void> _verifyRegistrationOtp() async {
    final enteredOtp = _registrationOtpControllers.map((c) => c.text.trim()).join();
    if (enteredOtp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of the verification code'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final targetPhone = _sentOtpMobile ?? ((_pilotMode == 1 || !_driverSameAsOwner)
        ? _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim()
        : _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim());

    setState(() {
      _isVerifyingOtp = true;
    });

    try {
      final res = await ApiService.verifyOtp(
        targetPhone,
        enteredOtp,
        role: 'PILOT',
        verificationSessionId: _otpVerificationSessionId,
      );

      if (res['success'] == true) {
        setState(() {
          _isRegistrationOtpVerified = true;
        });
        _otpTimer?.cancel();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Mobile Number Verified Successfully!'),
                ],
              ),
              backgroundColor: Color(0xFF16A34A),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        final errMsg = res['message'] ?? 'Invalid verification code. Please check and retry.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errMsg),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
        });
      }
    }
  }

  // --- SUBMIT PILOT APPLICATION TO MONGODB BACKEND ---
  Future<void> _submitPilotApplication() async {
    if (_isLoading) return;
    if (!_isRegistrationOtpVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your mobile number with OTP before submitting.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Uploading documents to secure storage...';
    });

    final fs = FirebaseService();
    final cleanPhone = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    final activePhone = cleanPhone.isNotEmpty ? cleanPhone : widget.phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
    final String uid = 'mock_uid_${activePhone}_pilot';
    final String resolvedDriverName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'StayDriv Pilot Partner';
    final String resolvedOwnerName = _driverSameAsOwner
        ? resolvedDriverName
        : (_ownerNameController.text.trim().isNotEmpty ? _ownerNameController.text.trim() : resolvedDriverName);
    final String resolvedDriverPhone = _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim().isNotEmpty
        ? _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim()
        : activePhone;

    try {
      // 1. Upload all documents to MongoDB GridFS backend via /api/upload
      String? aadhaarFrontUrl;
      String? aadhaarBackUrl;
      String? panFrontUrl;
      String? panBackUrl;
      String? rcFrontUrl;
      String? rcBackUrl;
      String? licenseFrontUrl;
      String? licenseBackUrl;
      String? photoUrl;
      String? fitnessUrl;
      String? permitUrl;
      String? insuranceUrl;

      if (_aadhaarFrontBytes != null) {
        setState(() => _loadingMessage = 'Uploading Aadhaar Card - Front...');
        aadhaarFrontUrl = await fs.uploadProfilePictureToMongo(uid, _aadhaarFrontBytes!, 'jpg', documentType: 'aadhaarFront');
      }
      if (_aadhaarBackBytes != null) {
        setState(() => _loadingMessage = 'Uploading Aadhaar Card - Back...');
        aadhaarBackUrl = await fs.uploadProfilePictureToMongo(uid, _aadhaarBackBytes!, 'jpg', documentType: 'aadhaarBack');
      }
      if (_panFrontBytes != null) {
        setState(() => _loadingMessage = 'Uploading PAN Card - Front...');
        panFrontUrl = await fs.uploadProfilePictureToMongo(uid, _panFrontBytes!, 'jpg', documentType: 'panFront');
      }
      if (_panBackBytes != null) {
        setState(() => _loadingMessage = 'Uploading PAN Card - Back...');
        panBackUrl = await fs.uploadProfilePictureToMongo(uid, _panBackBytes!, 'jpg', documentType: 'panBack');
      }
      if (_rcFrontBytes != null) {
        setState(() => _loadingMessage = 'Uploading Vehicle RC - Front...');
        final ext = _docFileNames['rc_front']?.split('.').last.toLowerCase() ?? 'jpg';
        rcFrontUrl = await fs.uploadProfilePictureToMongo(uid, _rcFrontBytes!, ext, documentType: 'rcFront');
      }
      if (_rcBackBytes != null) {
        setState(() => _loadingMessage = 'Uploading Vehicle RC - Back...');
        final ext = _docFileNames['rc_back']?.split('.').last.toLowerCase() ?? 'jpg';
        rcBackUrl = await fs.uploadProfilePictureToMongo(uid, _rcBackBytes!, ext, documentType: 'rcBack');
      }
      if (_insuranceBytes != null) {
        setState(() => _loadingMessage = 'Uploading Vehicle Insurance Copy...');
        final ext = _docFileNames['insurance']?.split('.').last.toLowerCase() ?? 'pdf';
        insuranceUrl = await fs.uploadProfilePictureToMongo(uid, _insuranceBytes!, ext, documentType: 'insurance');
      }
      if (_licenseFrontBytes != null) {
        setState(() => _loadingMessage = 'Uploading Driving Licence - Front...');
        licenseFrontUrl = await fs.uploadProfilePictureToMongo(uid, _licenseFrontBytes!, 'jpg', documentType: 'licenseFront');
      }
      if (_licenseBackBytes != null) {
        setState(() => _loadingMessage = 'Uploading Driving Licence - Back...');
        licenseBackUrl = await fs.uploadProfilePictureToMongo(uid, _licenseBackBytes!, 'jpg', documentType: 'licenseBack');
      }
      if (_photoBytes != null) {
        setState(() => _loadingMessage = 'Uploading Driver Profile Photo...');
        photoUrl = await fs.uploadProfilePictureToMongo(uid, _photoBytes!, 'jpg', documentType: 'photo');
      }
      if (_fitnessBytes != null) {
        setState(() => _loadingMessage = 'Uploading Fitness Certificate...');
        fitnessUrl = await fs.uploadProfilePictureToMongo(uid, _fitnessBytes!, 'jpg', documentType: 'fitness');
      }
      if (_permitBytes != null) {
        setState(() => _loadingMessage = 'Uploading Vehicle Permit...');
        permitUrl = await fs.uploadProfilePictureToMongo(uid, _permitBytes!, 'jpg', documentType: 'permit');
      }

      // 2. Submit partner registration and document URLs to StayDriv backend
      setState(() => _loadingMessage = 'Submitting registration details...');
      final baseUrl = NetworkConfig.backendUrl;
      final updateUrl = Uri.parse('$baseUrl/api/partner/update');

      final effectiveColor = _isCustomColor ? _vehicleColorController.text.trim() : _selectedVehicleColor;
      final effectiveMake = _vehicleMakeController.text.trim();
      final effectiveModel = _vehicleModelController.text.trim();
      final effectiveModelColor = (effectiveMake.isNotEmpty || effectiveModel.isNotEmpty)
          ? '$effectiveMake $effectiveModel • $effectiveColor'
          : '$effectiveColor $_selectedVehicle';

      final payload = {
        'uid': uid,
        'name': resolvedDriverName,
        'ownerName': resolvedOwnerName,
        'driverName': resolvedDriverName,
        'phone': activePhone,
        'ownerPhone': activePhone,
        'driverPhone': resolvedDriverPhone,
        'role': 'partner',
        'address': _addressController.text.trim(),
        'vehicleType': _isBikeSelected
            ? (_twoWheelerType == 'Scooty' ? 'Scooty' : 'Bike')
            : (_isCarXlSelected
                ? 'Car XL'
                : (_isMiniTruckSelected
                    ? 'Mini Truck'
                    : (_isHeavyTruckSelected
                        ? 'Heavy Truck'
                        : (_isAutoSelected ? 'Auto' : _selectedVehicle)))),
        'vehicleSubtype': _vehicleSubtype.isNotEmpty ? _vehicleSubtype : _twoWheelerType,
        'vehiclePlate': _vehicleNumberController.text.trim().toUpperCase(),
        'vehicleNumber': _vehicleNumberController.text.trim().toUpperCase(),
        'vehicleMake': effectiveMake,
        'vehicleModel': effectiveModel,
        'vehicleColor': effectiveColor,
        'vehicleModelColor': effectiveModelColor,
        'vehicleRegistrationDate': _vehicleRegDateController.text.trim(),
        'dor': _vehicleRegDateController.text.trim(),
        'insuranceExpiryDate': _insuranceExpiryController.text.trim(),
        'insuranceDocument': insuranceUrl,
        'insuranceDocumentUrl': insuranceUrl,
        'rcDocumentUrl': rcFrontUrl,
        'licenseNumber': _licenseNumberController.text.trim().toUpperCase(),
        'aadhaarNumber': _aadhaarNumberController.text.trim(),
        'dob': _dobController.text.trim(),
        'online': false,
        'approved': false,
        'isApproved': false,
        'isDocumentVerified': false,
        'photo': photoUrl,
        'aadhaarFront': aadhaarFrontUrl,
        'aadhaarBack': aadhaarBackUrl,
        'panFront': panFrontUrl,
        'panBack': panBackUrl,
        'licenseFront': licenseFrontUrl,
        'licenseBack': licenseBackUrl,
        'rcFront': rcFrontUrl,
        'rcBack': rcBackUrl,
        'fitness': fitnessUrl,
        'permit': permitUrl,
      };

      final response = await ApiClient().post(
        updateUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
        timeout: const Duration(seconds: 30),
        retry: false,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String serverAppId = '';
        try {
          final resData = jsonDecode(response.body);
          if (resData is Map) {
            serverAppId = resData['applicationId']?.toString() ?? 
                          (resData['user'] is Map ? resData['user']['applicationId']?.toString() : null) ?? '';
          }
        } catch (_) {}
        if (serverAppId.isEmpty) {
          serverAppId = 'SD-PLT-${activePhone.substring(max(0, activePhone.length - 4))}-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
        }

        // Save session locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_active_booking');
        BookingManager().clearBooking();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_name', resolvedOwnerName);
        await prefs.setString('user_role', 'Driver');
        await prefs.setString('phone_number', activePhone);
        await prefs.setString('selected_vehicle', _selectedVehicle);
        await prefs.setString('mock_uid', uid);
        await prefs.setString('pilot_application_id', serverAppId);
        await prefs.setString('pilot_application_status', 'PENDING_VERIFICATION');
        FirebaseService.setMockUid(uid);
        await _clearDraft();

        if (!mounted) return;
        setState(() => _isLoading = false);

        // 3. Show Application Status Dialog confirmed by Backend
        _showApplicationSubmittedDialog(
          applicationId: serverAppId,
          ownerName: resolvedOwnerName,
          vehicleType: _selectedVehicle,
          phone: activePhone,
        );
      } else {
        throw Exception('Server could not process application (HTTP ${response.statusCode}). Please try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final errStr = e.toString();
        final friendlyErr = (e is FormatException || errStr.contains('FormatException') || errStr.contains('<html>') || errStr.contains('Unexpected character'))
            ? 'Server returned an unexpected response. Please check your connection and try again.'
            : errStr.replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: $friendlyErr'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // --- SUBMIT REPLACE DRIVER FLOW (MODE 1 / PICTURE 3 HEADER) ---
  Future<void> _submitReplaceDriver() async {
    if (!_isRegistrationOtpVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify the new driver mobile number with OTP first.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    if (_licenseFrontBytes == null || _licenseBackBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload Driving Licence Front and Back'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Updating driver details...';
    });

    final fs = FirebaseService();
    final cleanPhone = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    final activePhone = cleanPhone.isNotEmpty ? cleanPhone : widget.phoneNumber.replaceAll(RegExp(r'\D'), '').trim();
    final uid = 'mock_uid_${activePhone}_pilot';
    final targetDriverPhone = _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    final driverName = _driverNameController.text.trim().isNotEmpty
        ? _driverNameController.text.trim()
        : 'Replacement Driver';

    try {
      String? photoUrl;
      String? licenseFrontUrl;
      String? licenseBackUrl;

      if (_photoBytes != null) {
        photoUrl = await fs.uploadProfilePictureToMongo(uid, _photoBytes!, 'jpg', documentType: 'photo');
      }
      if (_licenseFrontBytes != null) {
        licenseFrontUrl = await fs.uploadProfilePictureToMongo(uid, _licenseFrontBytes!, 'jpg', documentType: 'licenseFront');
      }
      if (_licenseBackBytes != null) {
        licenseBackUrl = await fs.uploadProfilePictureToMongo(uid, _licenseBackBytes!, 'jpg', documentType: 'licenseBack');
      }

      final baseUrl = NetworkConfig.backendUrl;
      final replaceUrl = Uri.parse('$baseUrl/api/partner/replace-driver');
      final res = await ApiClient().post(
        replaceUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': activePhone,
          'driverPhone': targetDriverPhone.isNotEmpty ? targetDriverPhone : activePhone,
          'driverName': driverName,
          'vehiclePlate': _vehicleNumberController.text.trim().toUpperCase(),
          'licenseFront': licenseFrontUrl,
          'licenseBack': licenseBackUrl,
          'photo': photoUrl,
        }),
        retry: false,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!mounted) return;
        setState(() => _isLoading = false);

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 28),
                SizedBox(width: 8),
                Text('Driver Updated'),
              ],
            ),
            content: const Text(
              'New driver details have been updated successfully and submitted to the StayDriv admin panel for verification.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(
                        userName: driverName,
                        userRole: 'Driver',
                        phoneNumber: activePhone,
                        selectedVehicle: _selectedVehicle,
                      ),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
                child: const Text('Go to Dashboard', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      } else {
        throw Exception('Server error: ${res.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update driver: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // --- SUBMIT CUSTOMER / ADMIN FORM ---
  Future<void> _submitCustomerOrAdminForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_userRole == 'Admin') {
      final bool isStaff = _adminType == 'Staff';
      final String enteredPassword = _passwordController.text.trim();
      if (enteredPassword.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isStaff ? 'Please enter staff password (admin@123)' : 'Please enter password to continue'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
      if (isStaff && enteredPassword != 'admin@123') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect staff password. Please enter "admin@123"'), backgroundColor: AppTheme.errorColor),
        );
        return;
      }
      if (!isStaff && enteredPassword != 'bhavi@123' && enteredPassword != 'admin@123') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect password. Access denied.'), backgroundColor: AppTheme.errorColor),
        );
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Logging in...';
    });

    try {
      final activePhone = _mockPhoneNumber ?? widget.phoneNumber;
      final bool isStaffUser = (_userRole == 'Admin' && _adminType == 'Staff');
      final String effectiveRole = isStaffUser ? 'Staff' : _userRole;
      final roleStr = _userRole == 'Admin' ? 'admin' : 'customer';
      final passwordStr = _userRole == 'Admin' ? _passwordController.text.trim() : "staydriv$activePhone";
      final resolvedName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : (isStaffUser ? 'StayDriv Staff' : (_userRole == 'Admin' ? 'StayDriv Admin' : 'StayDriv Customer'));

      String uid = 'mock_uid_$activePhone';
      try {
        final creds = await FirebaseService().signUp(
          email: "${activePhone}@staydriv.com",
          password: passwordStr,
          name: resolvedName,
          phone: activePhone,
          role: roleStr,
          adminType: _adminType,
        );
        if (creds.user != null) {
          uid = creds.user!.uid;
        }
      } catch (fbErr) {
        debugPrint("Firebase signUp fallback: $fbErr");
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_active_booking');
      BookingManager().clearBooking();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('user_name', resolvedName);
      await prefs.setString('user_role', effectiveRole);
      await prefs.setString('phone_number', activePhone);
      await prefs.remove('selected_vehicle');
      await prefs.setString('mock_uid', uid);
      FirebaseService.setMockUid(uid);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              userName: resolvedName,
              userRole: effectiveRole,
              phoneNumber: activePhone,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration Failed: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- APPLICATION SUBMITTED DIALOG ---
  void _showApplicationSubmittedDialog({
    required String applicationId,
    required String ownerName,
    required String vehicleType,
    required String phone,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF16A34A), width: 2),
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Application Submitted!',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Text(
                  'Status: Pending Admin Verification',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Application ID', applicationId),
                    const Divider(height: 12),
                    _buildSummaryRow('Pilot Name', ownerName),
                    const Divider(height: 12),
                    _buildSummaryRow('Vehicle Type', vehicleType),
                    const Divider(height: 12),
                    _buildSummaryRow('Mobile', '+91 $phone'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your documents have been submitted to StayDriv Admin for review. Once verified, your pilot account will be approved for rides.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomeScreen(
                          userName: ownerName,
                          userRole: 'Driver',
                          phoneNumber: phone,
                          selectedVehicle: vehicleType,
                        ),
                      ),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Open Pilot Dashboard',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
        Text(value, style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
      ],
    );
  }

  // --- BUILD METHOD ---
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return PopScope(
      canPop: _userRole != 'Driver' || _pilotMode == 1 || _pilotCurrentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_userRole == 'Driver' && _pilotMode == 0 && _pilotCurrentStep > 0) {
          setState(() {
            _pilotCurrentStep--;
          });
          _scrollToTop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.onSurfaceColor),
            onPressed: () {
              if (_userRole == 'Driver' && _pilotMode == 0 && _pilotCurrentStep > 0) {
                setState(() {
                  _pilotCurrentStep--;
                });
                _scrollToTop();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _userRole == 'Driver'
                ? (_pilotMode == 1
                    ? 'Update Driver'
                    : 'Complete Profile (${_pilotCurrentStep + 1}/3)')
                : 'Complete Profile',
            style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 500 : double.infinity,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),

                    // Role Selection Bento Card (visible ONLY for non-driver sign-up)
                    if (_userRole != 'Driver') ...[
                      Text(
                        'Tell us about yourself',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurfaceColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select profile type to continue',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildRoleSelector(),
                      const SizedBox(height: 16),
                    ],

                    // PILOT REGISTRATION STEPPER PROGRESS (When Driver & Mode 0)
                    if (_userRole == 'Driver' && _pilotMode == 0) ...[
                      _buildPilotStepProgress(),
                      const SizedBox(height: 14),
                    ],

                    // Render content based on Role and Step
                    if (_userRole != 'Driver') ...[
                      _buildCustomerOrAdminFields(),
                    ] else if (_pilotMode == 1) ...[
                      // MODE 1: REPLACE / MODIFY DRIVER (Picture 3 Header)
                      _buildReplaceDriverScreen(),
                    ] else if (_pilotCurrentStep == 0) ...[
                      // STEP 1: SCREEN 1 – VEHICLE DETAILS
                      _buildScreen1VehicleDetails(),
                    ] else if (_pilotCurrentStep == 1) ...[
                      // STEP 2: SCREEN 2 – OWNER & DRIVER VERIFICATION
                      _buildScreen2OwnerDriverVerification(),
                    ] else ...[
                      // STEP 3: SCREEN 3 – REVIEW AND SUBMIT
                      _buildScreen3ReviewAndSubmit(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- STEP PROGRESS INDICATOR FOR PILOT APP ---
  Widget _buildPilotStepProgress() {
    final steps = [
      {'number': '1', 'title': 'Vehicl...'},
      {'number': '2', 'title': 'RC & ...'},
      {'number': '3', 'title': 'Verify & ...'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isCompleted = _pilotCurrentStep > index;
          final isCurrent = _pilotCurrentStep == index;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? const Color(0xFF16A34A)
                              : (isCurrent ? const Color(0xFF1D4ED8) : Colors.white),
                          border: Border.all(
                            color: isCompleted
                                ? const Color(0xFF16A34A)
                                : (isCurrent ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1)),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : Text(
                                  steps[index]['number']!,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? Colors.white : const Color(0xFF64748B),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          steps[index]['title']!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFFCBD5E1)),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // --- SCREEN 1: VEHICLE DETAILS (STEP 1) ---
  Widget _buildScreen1VehicleDetails() {
    final bool isBikeSelected = _isBikeSelected;
    final bool isAutoSelected = _isAutoSelected;
    final bool isCarSelected = _isCarSelected;
    final bool isCarXlSelected = _isCarXlSelected;
    final bool isMiniTruckSelected = _isMiniTruckSelected;
    final bool isHeavyTruckSelected = _isHeavyTruckSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. SELECT VEHICLE TYPE HEADER & 6 CHIP CARDS (Row 1: Bike, Auto, Car | Row 2: Car XL, Mini Truck, Heavy Truck)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Vehicle Type',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                '6 Categories',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1D4ED8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row 1: Bike, Auto, Car
        Row(
          children: [
            // Bike Card
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedVehicle = _twoWheelerType == 'Scooty' ? 'Scooty' : 'Motorcycle/Bike';
                    _vehicleSubtype = _twoWheelerType;
                  });
                  _saveDraft();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: isBikeSelected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isBikeSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                      width: isBikeSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.two_wheeler_rounded,
                        color: isBikeSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        size: 26,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bike',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isBikeSelected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Auto Card
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedVehicle = 'Auto Rickshaw';
                    _vehicleSubtype = 'Auto Rickshaw';
                  });
                  _saveDraft();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: isAutoSelected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isAutoSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                      width: isAutoSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.electric_rickshaw_rounded,
                        color: isAutoSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        size: 26,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Auto',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isAutoSelected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Car Card
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedVehicle = 'Hatchback Car';
                    _vehicleSubtype = 'Hatchback';
                  });
                  _saveDraft();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: isCarSelected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCarSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                      width: isCarSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_car_rounded,
                        color: isCarSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        size: 26,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Car',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isCarSelected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Row 2: Car XL, Mini Truck & Heavy Truck (XL Cabs, Logistics & Cargo)
        Row(
          children: [
            // Car XL Card
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedVehicle = 'Car XL';
                    _vehicleSubtype = 'Innova / Crysta';
                  });
                  _saveDraft();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isCarXlSelected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCarXlSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                      width: isCarXlSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_car_filled_rounded,
                        color: isCarXlSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        size: 26,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Car XL',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isCarXlSelected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '6-7 Seater XL Cab',
                        style: GoogleFonts.inter(
                          fontSize: 8.8,
                          fontWeight: FontWeight.w600,
                          color: isCarXlSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Mini Truck Card
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedVehicle = 'Mini Truck';
                    _vehicleSubtype = 'Tata Ace / Dost';
                  });
                  _saveDraft();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: isMiniTruckSelected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMiniTruckSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                      width: isMiniTruckSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.airport_shuttle_rounded,
                        color: isMiniTruckSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        size: 26,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Mini Truck',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isMiniTruckSelected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        'Ace • Dost • Pickup',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: isMiniTruckSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Heavy Truck Card
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedVehicle = 'Heavy Truck';
                    _vehicleSubtype = '14ft - 19ft (6 - 10 Ton)';
                  });
                  _saveDraft();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: isHeavyTruckSelected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isHeavyTruckSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                      width: isHeavyTruckSelected ? 2 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_shipping_rounded,
                        color: isHeavyTruckSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        size: 26,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Heavy Truck',
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isHeavyTruckSelected ? const Color(0xFF1D4ED8) : const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '6 to 35 Ton Cargo',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: isHeavyTruckSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. FULL NAME (OPTIONAL)
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'FULL NAME (OPTIONAL)',
            hintText: 'Enter driver / applicant full name',
            prefixIcon: Icon(Icons.person_outline, size: 20),
          ),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 14),

        // 3. DATE OF BIRTH * (Date Picker)
        TextFormField(
          controller: _dobController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'DATE OF BIRTH *',
            hintText: 'Select Date of Birth (DD/MM/YYYY)',
            suffixIcon: Icon(Icons.calendar_today, size: 20),
          ),
          onTap: () => _selectDate(
            _dobController,
            initialDate: DateTime.now().subtract(const Duration(days: 365 * 22)),
            firstDate: DateTime(1950),
            lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
          ),
        ),
        const SizedBox(height: 14),

        // 4. Veh No - (BRIGHT YELLOW CARD)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF000), // Bright yellow plate style
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6D700), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Text(
                'Veh No - ',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFD32F2F),
                  letterSpacing: 0.5,
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _vehicleNumberController,
                  textCapitalization: TextCapitalization.characters,
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                    letterSpacing: 1.5,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'AP 07 AX 6057',
                    hintStyle: TextStyle(
                      color: Color(0xFF857900),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) => _saveDraft(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 5. D.O.R - (Date of Registration)
        TextFormField(
          controller: _vehicleRegDateController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'D.O.R - (DATE OF REGISTRATION) *',
            hintText: 'Select vehicle registration date',
            suffixIcon: Icon(Icons.calendar_today, size: 20),
          ),
          onTap: () => _selectDate(
            _vehicleRegDateController,
            firstDate: DateTime(1990),
            lastDate: DateTime.now(),
          ),
        ),
        const SizedBox(height: 14),

        // 6. Veh Color - (Vehicle Colour Dropdown)
        Text(
          'Veh Color - (VEHICLE COLOUR) *',
          style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _vehicleColours.contains(_selectedVehicleColor) ? _selectedVehicleColor : _vehicleColours.first,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.color_lens_outlined, size: 20, color: Color(0xFF1D4ED8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1D4ED8), width: 1.5)),
          ),
          items: _vehicleColours.map((color) {
            return DropdownMenuItem<String>(
              value: color,
              child: Text(color, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedVehicleColor = val;
                _isCustomColor = (val == 'Other (Custom)');
              });
              _saveDraft();
            }
          },
        ),
        if (_isCustomColor) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _vehicleColorController,
            decoration: const InputDecoration(
              labelText: 'SPECIFY VEHICLE COLOUR *',
              hintText: 'Enter custom vehicle colour',
              prefixIcon: Icon(Icons.edit_outlined, size: 20),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => _saveDraft(),
          ),
        ],
        const SizedBox(height: 14),

        // 7. Choose Sub-Category Toggle
        if (isBikeSelected) ...[
          Text(
            'Choose Two-Wheeler – Bike or Scooty',
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _twoWheelerType = 'Bike';
                      _vehicleSubtype = 'Bike';
                      _selectedVehicle = 'Motorcycle/Bike';
                    });
                    _saveDraft();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _twoWheelerType == 'Bike' ? const Color(0xFFEFF6FF) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _twoWheelerType == 'Bike' ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                        width: _twoWheelerType == 'Bike' ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Motorcycle / Bike',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _twoWheelerType == 'Bike' ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _twoWheelerType = 'Scooty';
                      _vehicleSubtype = 'Scooty';
                      _selectedVehicle = 'Scooty';
                    });
                    _saveDraft();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _twoWheelerType == 'Scooty' ? const Color(0xFFEFF6FF) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _twoWheelerType == 'Scooty' ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                        width: _twoWheelerType == 'Scooty' ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Scooty / Scooter',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _twoWheelerType == 'Scooty' ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ] else if (isCarSelected) ...[
          Text(
            'Choose Cab Segment – Hatchback, Sedan, or SUV',
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final seg in ['Hatchback', 'Sedan', 'SUV']) ...[
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedVehicle = seg == 'Hatchback' ? 'Hatchback Car' : seg;
                        _vehicleSubtype = seg;
                      });
                      _saveDraft();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_selectedVehicle.contains(seg) || _vehicleSubtype == seg) ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_selectedVehicle.contains(seg) || _vehicleSubtype == seg) ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                          width: (_selectedVehicle.contains(seg) || _vehicleSubtype == seg) ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        seg,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: (_selectedVehicle.contains(seg) || _vehicleSubtype == seg) ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
                if (seg != 'SUV') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ] else if (isCarXlSelected) ...[
          Text(
            'Choose Car XL Segment (6-7 Seater Spacious SUV/MUV)',
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final seg in ['Innova / Crysta', 'Ertiga / XL6', 'Carens / SUV XL']) ...[
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedVehicle = 'Car XL';
                        _vehicleSubtype = seg;
                      });
                      _saveDraft();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_selectedVehicle == 'Car XL' && _vehicleSubtype == seg) ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_selectedVehicle == 'Car XL' && _vehicleSubtype == seg) ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                          width: (_selectedVehicle == 'Car XL' && _vehicleSubtype == seg) ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        seg,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: (_selectedVehicle == 'Car XL' && _vehicleSubtype == seg) ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
                if (seg != 'Carens / SUV XL') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ] else if (isMiniTruckSelected) ...[
          Text(
            'Choose Mini Truck Category',
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final mt in ['Tata Ace', 'Pickup / Dost', '3-Wheeler Cargo']) ...[
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedVehicle = 'Mini Truck';
                        _vehicleSubtype = mt;
                      });
                      _saveDraft();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_vehicleSubtype == mt || (_vehicleSubtype == 'Tata Ace / Dost' && mt == 'Tata Ace')) ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_vehicleSubtype == mt || (_vehicleSubtype == 'Tata Ace / Dost' && mt == 'Tata Ace')) ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                          width: (_vehicleSubtype == mt || (_vehicleSubtype == 'Tata Ace / Dost' && mt == 'Tata Ace')) ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        mt,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: (_vehicleSubtype == mt || (_vehicleSubtype == 'Tata Ace / Dost' && mt == 'Tata Ace')) ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
                if (mt != '3-Wheeler Cargo') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ] else if (isHeavyTruckSelected) ...[
          Text(
            'Choose Heavy Truck Tonnage & Capacity',
            style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final ht in ['14ft - 19ft (6-10T)', '22ft - 32ft (16-35T)', 'Container / Tipper']) ...[
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedVehicle = 'Heavy Truck';
                        _vehicleSubtype = ht;
                      });
                      _saveDraft();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: (_vehicleSubtype == ht || (_vehicleSubtype == '14ft - 19ft (6 - 10 Ton)' && ht.startsWith('14ft'))) ? const Color(0xFFEFF6FF) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (_vehicleSubtype == ht || (_vehicleSubtype == '14ft - 19ft (6 - 10 Ton)' && ht.startsWith('14ft'))) ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
                          width: (_vehicleSubtype == ht || (_vehicleSubtype == '14ft - 19ft (6 - 10 Ton)' && ht.startsWith('14ft'))) ? 2 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        ht,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11.0,
                          fontWeight: FontWeight.bold,
                          color: (_vehicleSubtype == ht || (_vehicleSubtype == '14ft - 19ft (6 - 10 Ton)' && ht.startsWith('14ft'))) ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ),
                if (ht != 'Container / Tipper') const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 14),
        ],

        // 8. Vehicle Make & Model with Dynamic Category Hints
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _vehicleMakeController,
                decoration: InputDecoration(
                  labelText: 'VEHICLE MAKE *',
                  hintText: isMiniTruckSelected
                      ? 'e.g. Tata, Mahindra, Ashok Leyland'
                      : (isHeavyTruckSelected
                          ? 'e.g. Eicher, BharatBenz, Tata'
                          : (isCarXlSelected
                              ? 'e.g. Toyota, Maruti Suzuki, Kia'
                              : (isCarSelected
                                  ? 'e.g. Maruti, Hyundai, Tata'
                                  : (isAutoSelected ? 'e.g. Bajaj, Piaggio, TVS' : 'e.g. Hero, Honda, Bajaj')))),
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _saveDraft(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _vehicleModelController,
                decoration: InputDecoration(
                  labelText: 'VEHICLE MODEL *',
                  hintText: isMiniTruckSelected
                      ? 'e.g. Ace Gold, Bolero Maxx, Dost'
                      : (isHeavyTruckSelected
                          ? 'e.g. Pro 2049, 1617R, Signa 2823'
                          : (isCarXlSelected
                              ? 'e.g. Innova Crysta, Ertiga, Carens, Scorpio'
                              : (isCarSelected
                                  ? 'e.g. Swift, Dzire, Nexon'
                                  : (isAutoSelected ? 'e.g. Compact RE, Maxima, King' : 'e.g. Splendor, Activa, Pulsar')))),
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _saveDraft(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 9. Upload Veh Insurance (Copy & Expiry)
        _buildSectionSubHeader('VEHICLE INSURANCE (PDF OR IMAGE)'),
        _buildUploadBox(
          title: 'Upload Veh Insurance',
          docType: 'insurance',
          imageBytes: _insuranceBytes,
          onTap: () => _pickDocument('insurance'),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _insuranceExpiryController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'INSURANCE EXPIRY DATE *',
            hintText: 'Select insurance expiry date',
            suffixIcon: Icon(Icons.event_available, size: 20),
          ),
          onTap: () => _selectDate(
            _insuranceExpiryController,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
          ),
        ),
        const SizedBox(height: 14),

        // 10. Vehicle Registration Certificate (RC)
        _buildSectionSubHeader('VEHICLE REGISTRATION CERTIFICATE (RC)'),
        _buildUploadBox(
          title: 'Vehicle RC - Front',
          docType: 'rc_front',
          imageBytes: _rcFrontBytes,
          onTap: () => _pickDocument('rc_front'),
        ),
        _buildUploadBox(
          title: 'Vehicle RC - Back',
          docType: 'rc_back',
          imageBytes: _rcBackBytes,
          onTap: () => _pickDocument('rc_back'),
        ),
        const SizedBox(height: 10),

        // Commercial Vehicle Extra Documents (if Car or Truck)
        if (_vehicleNeedsExtraDocs) ...[
          _buildSectionSubHeader('COMMERCIAL VEHICLE DOCUMENTS'),
          _buildUploadBox(
            title: 'Fitness Certificate',
            docType: 'fitness',
            imageBytes: _fitnessBytes,
            onTap: () => _pickDocument('fitness'),
          ),
          _buildUploadBox(
            title: 'Vehicle Permit',
            docType: 'permit',
            imageBytes: _permitBytes,
            onTap: () => _pickDocument('permit'),
          ),
          const SizedBox(height: 14),
        ],

        // 11. ALREADY REGISTERED LOGIN (Red Button)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final String phone = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
              final String effectivePhone = phone.isNotEmpty ? phone : widget.phoneNumber;
              final String selectedVehicle = _selectedVehicle;
              final String uid = 'mock_uid_${effectivePhone}_pilot';
              final String displayName = _nameController.text.trim().isNotEmpty
                  ? _nameController.text.trim()
                  : 'Pilot Partner';

              await prefs.setBool('is_logged_in', true);
              await prefs.setString('user_name', displayName);
              await prefs.setString('user_role', 'Driver');
              await prefs.setString('phone_number', effectivePhone);
              await prefs.setString('selected_vehicle', selectedVehicle);
              if (_vehicleNumberController.text.trim().isNotEmpty) {
                await prefs.setString('vehicle_plate', _vehicleNumberController.text.trim().toUpperCase());
              }
              await prefs.setString('mock_uid', uid);
              FirebaseService.setMockUid(uid);

              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomeScreen(
                      userName: displayName,
                      userRole: 'Driver',
                      phoneNumber: effectivePhone,
                      selectedVehicle: selectedVehicle,
                    ),
                  ),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ALREADY REGISTERED LOGIN',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 12. Mode Selector: NEW REGISTRATION vs REPLACE / MODIFY DRIVER
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => setState(() => _pilotMode = 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7C3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF15803D), width: 2),
                    ),
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'NEW REGISTRATION',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => setState(() => _pilotMode = 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade400, width: 1),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'REPLACE / MODIFY DRIVER',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 13. OWNER DETAILS (Orange Banner)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFEA580C), // Orange banner
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEA580C).withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'OWNER DETAILS',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _driverSameAsOwner,
                    activeColor: const Color(0xFFEA580C),
                    onChanged: (val) {
                      setState(() {
                        _driverSameAsOwner = val ?? true;
                        if (_driverSameAsOwner) {
                          _ownerNameController.text = _nameController.text;
                          _ownerPhoneController.text = _driverPhoneController.text;
                        }
                      });
                      _saveDraft();
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Vehicle Owner is the Driver',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF9A3412),
                      ),
                    ),
                  ),
                ],
              ),
              if (!_driverSameAsOwner) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ownerNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'OWNER FULL NAME *',
                    hintText: 'Enter registered vehicle owner full name',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                  onChanged: (_) => _saveDraft(),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ownerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'OWNER MOBILE NUMBER *',
                    hintText: '10-digit mobile number for OTP',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                  onChanged: (_) => _saveDraft(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 14. Action buttons: Continue to Step 2 & Save as Draft
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _validateAndProceedToScreen2,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue to Step 2: Owner & Driver Verification',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () async {
              await _saveDraft();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Registration draft saved successfully!'),
                    backgroundColor: Color(0xFF16A34A),
                  ),
                );
              }
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.save_outlined, size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  'Save as Draft',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- STEP 1 IN-STEP MOBILE OTP VERIFICATION BOX ---
  Widget _buildStep1MobileOtpBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isRegistrationOtpVerified ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
          width: _isRegistrationOtpVerified ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pilot Mobile Number *',
                style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
              ),
              if (_isRegistrationOtpVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 14),
                      SizedBox(width: 4),
                      Text('VERIFIED', style: TextStyle(color: Color(0xFF16A34A), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text('+91', style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                const SizedBox(width: 8),
                Container(width: 1, height: 22, color: const Color(0xFFCBD5E1)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _ownerPhoneController,
                    keyboardType: TextInputType.phone,
                    enabled: !_isRegistrationOtpVerified,
                    style: GoogleFonts.robotoMono(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Enter 10-digit number',
                    ),
                    onChanged: (val) {
                      if (_isRegistrationOtpVerified) {
                        setState(() => _isRegistrationOtpVerified = false);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // GET OTP Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: (_isSendingOtp || _otpCountdown > 0 || _isRegistrationOtpVerified)
                  ? null
                  : _requestRegistrationOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE87A1E),
                disabledBackgroundColor: _isRegistrationOtpVerified ? const Color(0xFFDCFCE7) : const Color(0xFFCBD5E1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isSendingOtp
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(
                      _isRegistrationOtpVerified
                          ? 'MOBILE NUMBER VERIFIED ✓'
                          : (_otpCountdown > 0 ? 'RESEND OTP IN ${_otpCountdown}s' : 'GET OTP'),
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: _isRegistrationOtpVerified ? const Color(0xFF16A34A) : Colors.black87,
                      ),
                    ),
            ),
          ),

          // OTP Input Fields when OTP is sent and not yet verified
          if (!_isRegistrationOtpVerified && _sentOtpMobile != null) ...[
            const SizedBox(height: 12),
            Text(
              'Enter 6-Digit SMS Verification Code',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (index) {
                return SizedBox(
                  width: 44,
                  height: 48,
                  child: TextFormField(
                    controller: _registrationOtpControllers[index],
                    focusNode: _otpFocusNodes[index],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: GoogleFonts.robotoMono(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1D4ED8)),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color(0xFFEFF6FF),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFBFDBFE))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF1D4ED8), width: 1.5)),
                    ),
                    onChanged: (val) {
                      if (val.isNotEmpty && index < 5) {
                        _otpFocusNodes[index + 1].requestFocus();
                      } else if (val.isEmpty && index > 0) {
                        _otpFocusNodes[index - 1].requestFocus();
                      }
                      if (_registrationOtpControllers.every((c) => c.text.isNotEmpty)) {
                        _verifyRegistrationOtp();
                      }
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton(
                onPressed: _isVerifyingOtp ? null : _verifyRegistrationOtp,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF1D4ED8), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isVerifyingOtp
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        'VERIFY OTP',
                        style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF1D4ED8)),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- SCREEN 2: OWNER & DRIVER VERIFICATION (STEP 2) ---
  Widget _buildScreen2OwnerDriverVerification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. SECTION HEADER: STEP 2: OWNER & DRIVER VERIFICATION
        _buildSectionHeader('STEP 2: OWNER & DRIVER VERIFICATION'),

        // 2. Driver / Pilot Full Name
        Text(
          'Driver Full Name *',
          style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'DRIVER FULL NAME *',
            hintText: 'Enter full name as per Driving Licence',
            prefixIcon: Icon(Icons.person_outline, size: 20),
          ),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 14),

        // 3. Owner Mobile Number with In-Step OTP Verification Box
        _buildSectionSubHeader('OWNER MOBILE NUMBER & OTP VERIFICATION'),
        _buildStep1MobileOtpBox(),
        const SizedBox(height: 14),

        // 4. Driver Mobile Number
        Text(
          'Driver Mobile Number *',
          style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _driverPhoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: const InputDecoration(
            labelText: 'DRIVER MOBILE NUMBER *',
            hintText: '10-digit mobile number for driver communication',
            prefixIcon: Icon(Icons.phone_iphone_outlined, size: 20),
            counterText: '',
          ),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 14),

        // 5. Driving Licence Number & Uploads
        _buildSectionSubHeader('DRIVING LICENCE DETAILS'),
        TextFormField(
          controller: _licenseNumberController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'DRIVING LICENCE NUMBER *',
            hintText: 'e.g. AP07 20210012345',
            prefixIcon: Icon(Icons.card_membership_outlined, size: 20),
          ),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 10),
        _buildUploadBox(
          title: 'Driving Licence - Front',
          docType: 'license_front',
          imageBytes: _licenseFrontBytes,
          onTap: () => _pickDocument('license_front'),
        ),
        _buildUploadBox(
          title: 'Driving Licence - Back',
          docType: 'license_back',
          imageBytes: _licenseBackBytes,
          onTap: () => _pickDocument('license_back'),
        ),
        const SizedBox(height: 14),

        // 6. Aadhaar Card Number & Uploads
        _buildSectionSubHeader('AADHAAR CARD DETAILS'),
        TextFormField(
          controller: _aadhaarNumberController,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: 'AADHAAR CARD NUMBER (12 DIGITS) *',
            hintText: 'Enter 12-digit Aadhaar number',
            prefixIcon: Icon(Icons.fingerprint_rounded, size: 20),
            counterText: '',
          ),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 10),
        _buildUploadBox(
          title: 'Aadhaar Card - Front',
          docType: 'aadhaar_front',
          imageBytes: _aadhaarFrontBytes,
          onTap: () => _pickDocument('aadhaar_front'),
        ),
        _buildUploadBox(
          title: 'Aadhaar Card - Back',
          docType: 'aadhaar_back',
          imageBytes: _aadhaarBackBytes,
          onTap: () => _pickDocument('aadhaar_back'),
        ),
        const SizedBox(height: 14),

        // 7. PAN Card Uploads
        _buildSectionSubHeader('PAN CARD DETAILS'),
        _buildUploadBox(
          title: 'PAN Card - Front',
          docType: 'pan_front',
          imageBytes: _panFrontBytes,
          onTap: () => _pickDocument('pan_front'),
        ),
        _buildUploadBox(
          title: 'PAN Card - Back',
          docType: 'pan_back',
          imageBytes: _panBackBytes,
          onTap: () => _pickDocument('pan_back'),
        ),
        const SizedBox(height: 14),

        // 8. Driver Profile Photo
        _buildSectionSubHeader('DRIVER PROFILE PHOTO'),
        _buildUploadBox(
          title: 'Driver Profile Photo (Clear Face Photo)',
          docType: 'photo',
          imageBytes: _photoBytes,
          onTap: () => _pickDocument('photo'),
        ),
        const SizedBox(height: 14),

        // 9. Residential Address
        _buildSectionSubHeader('RESIDENTIAL ADDRESS'),
        TextFormField(
          controller: _addressController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'CURRENT RESIDENTIAL ADDRESS *',
            hintText: 'Door No, Street, City, State, PIN Code',
            prefixIcon: Icon(Icons.home_outlined, size: 20),
          ),
          onChanged: (_) => _saveDraft(),
        ),
        const SizedBox(height: 18),

        // 10. CONTINUE TO STEP 3 BUTTON
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _validateAndProceedToScreen3,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue to Step 3: Review & Submit',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 11. BACK TO STEP 1 BUTTON
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _pilotCurrentStep = 0;
              });
              _saveDraft();
              _scrollToTop();
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.arrow_back, size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  'Back to Step 1: Vehicle Details',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 12. Save as Draft Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () async {
              await _saveDraft();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Registration draft saved successfully!'),
                    backgroundColor: Color(0xFF16A34A),
                  ),
                );
              }
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.save_outlined, size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  'Save as Draft',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  // --- SCREEN 3: REVIEW & SUBMIT (STEP 3) ---
  Widget _buildScreen3ReviewAndSubmit() {
    final effectiveColor = _isCustomColor ? _vehicleColorController.text.trim() : _selectedVehicleColor;
    final effectiveOwnerPhone = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
    final effectiveDriverPhone = _driverPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. SECTION HEADER: STEP 3: REVIEW & SUBMIT
        _buildSectionHeader('STEP 3: REVIEW & SUBMIT'),

        // 2. Vehicle Details Summary Card (with Edit Step 1 jump button)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.directions_car_filled_rounded, color: Color(0xFF1D4ED8), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Vehicle Details',
                        style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _pilotCurrentStep = 0);
                      _scrollToTop();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 12, color: Color(0xFF1D4ED8)),
                          const SizedBox(width: 4),
                          Text('Edit Step 1', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1D4ED8))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFE2E8F0)),
              _buildReviewRow(
                'Vehicle Type',
                _isBikeSelected
                    ? 'Two-Wheeler ($_twoWheelerType)'
                    : (_isCarXlSelected
                        ? 'Car XL ($_vehicleSubtype)'
                        : (_isMiniTruckSelected
                            ? 'Mini Truck ($_vehicleSubtype)'
                            : (_isHeavyTruckSelected
                                ? 'Heavy Truck ($_vehicleSubtype)'
                                : (_isCarSelected ? 'Car ($_vehicleSubtype)' : _selectedVehicle)))),
              ),
              const SizedBox(height: 6),
              _buildReviewRow('Registration Number', _vehicleNumberController.text.trim().toUpperCase()),
              const SizedBox(height: 6),
              _buildReviewRow('Make & Model', '${_vehicleMakeController.text.trim()} ${_vehicleModelController.text.trim()}'),
              const SizedBox(height: 6),
              _buildReviewRow('Vehicle Colour', effectiveColor),
              const SizedBox(height: 6),
              _buildReviewRow('Date of Reg. (D.O.R)', _vehicleRegDateController.text.trim()),
              const SizedBox(height: 6),
              _buildReviewRow('Insurance Expiry', _insuranceExpiryController.text.trim()),
              const SizedBox(height: 6),
              _buildReviewRow('Vehicle Ownership', _driverSameAsOwner ? 'Driver is Owner' : '${_ownerNameController.text.trim()} (+91 $effectiveOwnerPhone)'),
            ],
          ),
        ),

        // 3. Owner & Driver Verification Summary Card (with Edit Step 2 jump button)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCBD5E1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_user_rounded, color: Color(0xFF1D4ED8), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Owner & Driver Verification',
                        style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _pilotCurrentStep = 1);
                      _scrollToTop();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 12, color: Color(0xFF1D4ED8)),
                          const SizedBox(width: 4),
                          Text('Edit Step 2', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1D4ED8))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFE2E8F0)),
              _buildReviewRow('Driver Full Name', _nameController.text.trim()),
              const SizedBox(height: 6),
              _buildReviewRow('Owner Mobile', '+91 $effectiveOwnerPhone (Verified ✓)'),
              const SizedBox(height: 6),
              _buildReviewRow('Driver Mobile', '+91 $effectiveDriverPhone'),
              const SizedBox(height: 6),
              _buildReviewRow('Driving Licence No.', _licenseNumberController.text.trim().toUpperCase()),
              const SizedBox(height: 6),
              _buildReviewRow('Aadhaar Card No.', _aadhaarNumberController.text.trim()),
              const SizedBox(height: 6),
              _buildReviewRow('Date of Birth', _dobController.text.trim().isNotEmpty ? _dobController.text.trim() : 'Not specified'),
              const SizedBox(height: 6),
              _buildReviewRow('Residential Address', _addressController.text.trim()),
            ],
          ),
        ),

        // 4. Documents Upload Status Card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Document Verification Checklist',
                style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildDocCheckPill('Driving Licence', _licenseFrontBytes != null && _licenseBackBytes != null),
                  _buildDocCheckPill('Aadhaar Card', _aadhaarFrontBytes != null && _aadhaarBackBytes != null),
                  _buildDocCheckPill('PAN Card', _panFrontBytes != null && _panBackBytes != null),
                  _buildDocCheckPill('Vehicle RC', _rcFrontBytes != null && _rcBackBytes != null),
                  _buildDocCheckPill('Insurance Copy', _insuranceBytes != null),
                  _buildDocCheckPill('Pilot Photo', _photoBytes != null),
                  if (_vehicleNeedsExtraDocs) ...[
                    _buildDocCheckPill('Fitness Certificate', _fitnessBytes != null),
                    _buildDocCheckPill('Vehicle Permit', _permitBytes != null),
                  ],
                ],
              ),
            ],
          ),
        ),

        // 5. Declaration Checkbox
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _declarationAccepted ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _declarationAccepted ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _declarationAccepted,
                activeColor: const Color(0xFF16A34A),
                onChanged: (val) {
                  setState(() {
                    _declarationAccepted = val ?? false;
                  });
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _declarationAccepted = !_declarationAccepted;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'I confirm and declare that all the information, vehicle details, and documents provided are true, authentic, and legally valid. I accept the StayDriv Partner Agreement and Code of Conduct.',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: const Color(0xFF1E293B),
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 6. ALL 6 FUNCTIONAL BUTTONS
        // Button 1: Submit Registration (Blue)
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () {
                    if (!_declarationAccepted) {
                      _showWarningSnackBar('Please accept the declaration checkbox before submitting');
                      return;
                    }
                    _submitPilotApplication();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              disabledBackgroundColor: const Color(0xFF94A3B8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 2,
            ),
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _loadingMessage,
                          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Submit Pilot Registration',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Button 2: Save as Draft
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () async {
              await _saveDraft();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Registration draft saved successfully!'),
                    backgroundColor: Color(0xFF16A34A),
                  ),
                );
              }
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.save_outlined, size: 18, color: Color(0xFF16A34A)),
                const SizedBox(width: 6),
                Text(
                  'Save as Draft',
                  style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF16A34A)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Button 3: Previous (Back to Step 2)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _pilotCurrentStep = 1;
              });
              _saveDraft();
              _scrollToTop();
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.arrow_back, size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Text(
                  'Back to Step 2: Owner & Driver Verification',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w700, color: const Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Button 4 & Button 6: Mode Row (NEW REGISTRATION vs REPLACE / MODIFY DRIVER)
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _pilotMode = 0;
                      _pilotCurrentStep = 0;
                    });
                    _scrollToTop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B7C3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF15803D), width: 2),
                    ),
                    elevation: 1,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'NEW REGISTRATION',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _pilotMode = 1;
                    });
                    _scrollToTop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade400, width: 1),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'REPLACE / MODIFY DRIVER',
                      style: GoogleFonts.hankenGrotesk(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Button 5: ALREADY REGISTERED? LOGIN (Red Button)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final String phone = _ownerPhoneController.text.replaceAll(RegExp(r'\D'), '').trim();
              final String effectivePhone = phone.isNotEmpty ? phone : widget.phoneNumber;
              final String selectedVehicle = _selectedVehicle;
              final String uid = 'mock_uid_${effectivePhone}_pilot';
              final String displayName = _nameController.text.trim().isNotEmpty
                  ? _nameController.text.trim()
                  : 'Pilot Partner';

              await prefs.setBool('is_logged_in', true);
              await prefs.setString('user_name', displayName);
              await prefs.setString('user_role', 'Driver');
              await prefs.setString('phone_number', effectivePhone);
              await prefs.setString('selected_vehicle', selectedVehicle);
              if (_vehicleNumberController.text.trim().isNotEmpty) {
                await prefs.setString('vehicle_plate', _vehicleNumberController.text.trim().toUpperCase());
              }
              await prefs.setString('mock_uid', uid);
              FirebaseService.setMockUid(uid);

              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HomeScreen(
                      userName: displayName,
                      userRole: 'Driver',
                      phoneNumber: effectivePhone,
                      selectedVehicle: selectedVehicle,
                    ),
                  ),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 1,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'ALREADY REGISTERED? LOGIN',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value.isNotEmpty ? value : '-',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0F172A), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // --- MODE 1: REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS (PICTURE 3) ---
  Widget _buildReplaceDriverScreen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode Selector: Switch between New Registration and Replace
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () => setState(() {
                    _pilotMode = 0;
                    _pilotCurrentStep = 0;
                  }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade400, width: 1),
                    ),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text('NEW REGISTRATION', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () => setState(() => _pilotMode = 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE87A1E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFC25E0B), width: 2),
                    ),
                    elevation: 1,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text('REPLACE / MODIFY DRIVER', style: GoogleFonts.hankenGrotesk(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // SECTION HEADER: REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS (Orange Header Banner matching Picture 3)
        _buildSectionHeader('REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS'),

        // Driving License Front & Back
        _buildUploadBox(
          title: 'Driving Licence - Front',
          docType: 'license_front',
          imageBytes: _licenseFrontBytes,
          onTap: () => _pickDocument('license_front'),
        ),
        _buildUploadBox(
          title: 'Driving Licence - Back',
          docType: 'license_back',
          imageBytes: _licenseBackBytes,
          onTap: () => _pickDocument('license_back'),
        ),

        // New Driver Name & Mobile Number
        TextFormField(
          controller: _driverNameController,
          decoration: const InputDecoration(labelText: 'NEW DRIVER FULL NAME', hintText: 'Enter replacement driver name'),
        ),
        const SizedBox(height: 12),
        _buildPhoneInputTile(title: 'New Driver Mobile Number', controller: _driverPhoneController),
        const SizedBox(height: 14),

        // Real OTP Verification for New Driver
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: (_isSendingOtp || _otpCountdown > 0) ? null : _requestRegistrationOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE87A1E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _isSendingOtp
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _otpCountdown > 0 ? 'RESEND OTP IN ${_otpCountdown}s' : 'GET OTP',
                    style: GoogleFonts.hankenGrotesk(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 44,
              height: 48,
              child: TextFormField(
                controller: _registrationOtpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: GoogleFonts.robotoMono(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1D4ED8)),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: const Color(0xFFEFF6FF),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFBFDBFE))),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty && index < 5) {
                    _otpFocusNodes[index + 1].requestFocus();
                  } else if (val.isEmpty && index > 0) {
                    _otpFocusNodes[index - 1].requestFocus();
                  }
                  if (_registrationOtpControllers.every((c) => c.text.isNotEmpty)) {
                    _verifyRegistrationOtp();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton(
            onPressed: _isVerifyingOtp ? null : _verifyRegistrationOtp,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _isRegistrationOtpVerified ? const Color(0xFF16A34A) : const Color(0xFF1D4ED8)),
              backgroundColor: _isRegistrationOtpVerified ? const Color(0xFFDCFCE7) : Colors.transparent,
            ),
            child: Text(
              _isRegistrationOtpVerified ? 'DRIVER MOBILE VERIFIED ✓' : 'VERIFY OTP',
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: _isRegistrationOtpVerified ? const Color(0xFF16A34A) : const Color(0xFF1D4ED8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Driver Profile Photo
        _buildUploadBox(
          title: 'New Driver Profile Photo',
          docType: 'photo',
          imageBytes: _photoBytes,
          onTap: () => _pickDocument('photo'),
        ),

        if (_vehicleNeedsExtraDocs) ...[
          _buildUploadBox(
            title: 'Fitness Certificate',
            docType: 'fitness',
            imageBytes: _fitnessBytes,
            onTap: () => _pickDocument('fitness'),
          ),
          _buildUploadBox(
            title: 'Vehicle Permit',
            docType: 'permit',
            imageBytes: _permitBytes,
            onTap: () => _pickDocument('permit'),
          ),
        ],
        const SizedBox(height: 16),

        // SUBMIT APPLICATION BUTTON (Blue)
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: (_isLoading || !_isRegistrationOtpVerified) ? null : _submitReplaceDriver,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              disabledBackgroundColor: const Color(0xFF94A3B8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text(_loadingMessage, style: const TextStyle(color: Colors.white)),
                    ],
                  )
                : Text(
                    'Submit Application',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }

  // --- CUSTOMER OR ADMIN FIELDS ---
  Widget _buildCustomerOrAdminFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'FULL NAME', hintText: 'Enter your full name'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Please enter your full name';
            return null;
          },
        ),
        const SizedBox(height: 14),
        if (_userRole == 'Admin') ...[
          DropdownButtonFormField<String>(
            value: _adminType,
            decoration: const InputDecoration(labelText: 'ADMIN ROLE'),
            items: const [
              DropdownMenuItem(value: 'Staff', child: Text('StayDriv Staff')),
              DropdownMenuItem(value: 'Admin', child: Text('Super Admin')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _adminType = value;
                  _nameController.text = value == 'Staff' ? 'StayDriv Staff' : 'StayDriv Admin';
                  _passwordController.clear();
                });
              }
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'PASSWORD',
              hintText: _adminType == 'Staff' ? 'Enter staff password (admin@123)' : 'Enter superadmin password',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitCustomerOrAdminForm,
            style: ElevatedButton.styleFrom(
              backgroundColor: _userRole == 'Admin' ? const Color(0xFFE87A1E) : const Color(0xFF1D4ED8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isLoading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _userRole == 'Admin' ? 'Login to Admin Panel' : 'Continue to StayDriv',
                    style: GoogleFonts.hankenGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }

  // --- REUSABLE UI COMPONENTS ---

  Widget _buildRoleSelector() {
    return Row(
      children: [
        _buildRoleCard('Customer', Icons.directions_car_rounded, _userRole == 'Customer', () {
          setState(() {
            _userRole = 'Customer';
            _nameController.clear();
          });
        }),
        const SizedBox(width: 8),
        _buildRoleCard('Pilot', Icons.handshake_outlined, _userRole == 'Driver', () {
          setState(() {
            _userRole = 'Driver';
            _nameController.clear();
          });
        }),
        const SizedBox(width: 8),
        _buildRoleCard('Admin', Icons.admin_panel_settings_outlined, _userRole == 'Admin', () {
          setState(() {
            _userRole = 'Admin';
            _nameController.text = _adminType == 'Staff' ? 'StayDriv Staff' : 'StayDriv Admin';
          });
        }),
      ],
    );
  }

  Widget _buildRoleCard(String title, IconData icon, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFEFF5FF) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF64748B), size: 26),
              const SizedBox(height: 6),
              Text(
                title,
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(top: 10, bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE87A1E), // Vibrant Orange banner matching Pictures 1, 2, 3
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 16.5,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSectionSubHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF475569),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildUploadBox({
    required String title,
    required String docType,
    required Uint8List? imageBytes,
    required VoidCallback onTap,
  }) {
    final bool hasUploaded = imageBytes != null;
    final String displayFileName = _docFileNames[docType] ?? '';
    final String displayFileSize = _docFileSizes[docType] ?? '';
    final bool isPdf = displayFileName.toLowerCase().endsWith('.pdf');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUploaded ? const Color(0xFF22C55E) : const Color(0xFFE2E8F0),
          width: hasUploaded ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: hasUploaded
            ? (isPdf
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Center(
                      child: Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 26),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ))
            : Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.upload_file_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 24,
                ),
              ),
        title: Text(
          title,
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: const Color(0xFF0F172A),
          ),
        ),
        subtitle: hasUploaded
            ? Row(
                children: [
                  const Icon(Icons.check_circle, size: 13, color: Color(0xFF16A34A)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      displayFileName.isNotEmpty ? '$displayFileName ($displayFileSize)' : 'Selected ($displayFileSize)',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF16A34A), fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Text(
                docType == 'insurance' ? 'Upload PDF, JPG or PNG (max 10MB)' : 'Upload JPG/JPEG document (max 10MB)',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
              ),
        trailing: hasUploaded
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, color: Color(0xFF1D4ED8), size: 20),
                    tooltip: 'View Document',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(title, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (displayFileName.isNotEmpty)
                                Text('$displayFileName • $displayFileSize', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 12),
                              if (isPdf)
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFECACA)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 54),
                                      const SizedBox(height: 12),
                                      Text(
                                        displayFileName.isNotEmpty ? displayFileName : 'PDF Document Attached',
                                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF991B1B)),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Document verified & ready for submission',
                                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB91C1C)),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(imageBytes, fit: BoxFit.contain, height: 260),
                                ),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                          ],
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, color: Color(0xFF64748B), size: 20),
                    tooltip: 'Replace Document',
                    onPressed: onTap,
                  ),
                ],
              )
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text('Upload', style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
      ),
    );
  }

  Widget _buildPhoneInputTile({required String title, required TextEditingController controller}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF1E293B)),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1.4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text('+91', style: GoogleFonts.robotoMono(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
              const SizedBox(width: 8),
              Container(width: 1, height: 22, color: const Color(0xFFCBD5E1)),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.robotoMono(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Enter 10-digit number',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDocCheckPill(String name, bool isUploaded) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isUploaded ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isUploaded ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isUploaded ? Icons.check : Icons.close, size: 11, color: isUploaded ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
          const SizedBox(width: 3),
          Text(
            name,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isUploaded ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
            ),
          ),
        ],
      ),
    );
  }
}
