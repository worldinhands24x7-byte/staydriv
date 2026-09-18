import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme.dart';
import '../../../core/firebase_service.dart';
import '../../../core/api_client.dart';
import '../../../core/network_config.dart';
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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _referralController = TextEditingController();
  final TextEditingController _ownerPhoneController = TextEditingController();
  final TextEditingController _driverPhoneController = TextEditingController();
  final List<TextEditingController> _ownerOtpControllers = List.generate(6, (i) => TextEditingController(text: ['8', '1', '2', '1', '4', '4'][i]));
  final List<TextEditingController> _driverOtpControllers = List.generate(6, (i) => TextEditingController(text: ['8', '1', '2', '1', '4', '4'][i]));
  bool _isOwnerOtpVerified = true;
  bool _isDriverOtpVerified = true;
  bool _driverSameAsOwner = true;
  
  late String _userRole; // Customer or Driver or Admin
  String _selectedVehicle = 'Bike'; // Default selected vehicle
  bool _isLoading = false;
  String _adminType = 'Staff'; // Staff or Admin (default Staff as shown in screenshot)
  String? _mockPhoneNumber;
  bool _obscurePassword = true;
  int _pilotMode = 0; // 0 = New Registration, 1 = Replace/Update/Modify Driver

  @override
  void initState() {
    super.initState();
    _userRole = widget.initialRole ?? 'Customer';
    _ownerPhoneController.text = widget.phoneNumber;
    _driverPhoneController.text = widget.phoneNumber;
    if (_userRole == 'Admin') {
      _nameController.text = _adminType == 'Staff' ? 'StayDriv Staff' : 'StayDriv Admin';
      _passwordController.clear();
    }
  }
  
  // Document upload state flags
  bool _uploadedAadhaarFront = false;
  bool _uploadedAadhaarBack = false;
  bool _uploadedPanFront = false;
  bool _uploadedPanBack = false;
  bool _uploadedLicenseFront = false;
  bool _uploadedLicenseBack = false;
  bool _uploadedRCFront = false;
  bool _uploadedRCBack = false;
  bool _uploadedPhoto = false;
  bool _uploadedFitness = false;
  bool _uploadedPermit = false;

  Uint8List? _aadhaarFrontBytes;
  Uint8List? _aadhaarBackBytes;
  Uint8List? _panFrontBytes;
  Uint8List? _panBackBytes;
  Uint8List? _licenseFrontBytes;
  Uint8List? _licenseBackBytes;
  Uint8List? _rcFrontBytes;
  Uint8List? _rcBackBytes;
  Uint8List? _photoBytes;
  Uint8List? _fitnessBytes;
  Uint8List? _permitBytes;

  final Map<String, String> _docFileNames = {};
  final Map<String, String> _docFileSizes = {};

  bool get _vehicleNeedsExtraDocs {
    return _selectedVehicle == 'Car' || _selectedVehicle == 'Mini Truck' || _selectedVehicle == 'Heavy Truck';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _dobController.dispose();
    _referralController.dispose();
    _ownerPhoneController.dispose();
    _driverPhoneController.dispose();
    for (var c in _ownerOtpControllers) {
      c.dispose();
    }
    for (var c in _driverOtpControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDocument(String docType) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null) {
        Uint8List? fileBytes;
        if (kIsWeb) {
          fileBytes = result.files.single.bytes;
        } else {
          final path = result.files.single.path;
          if (path != null) {
            fileBytes = await io.File(path).readAsBytes();
          }
        }
        
        if (fileBytes != null) {
          final String fileName = result.files.single.name;
          final int bytesLen = fileBytes.length;
          final String sizeStr = bytesLen > 1024 * 1024
              ? '${(bytesLen / (1024 * 1024)).toStringAsFixed(1)} MB'
              : '${(bytesLen / 1024).toStringAsFixed(1)} KB';

          setState(() {
            _docFileNames[docType] = fileName;
            _docFileSizes[docType] = sizeStr;

            if (docType == 'aadhaar_front') {
              _aadhaarFrontBytes = fileBytes;
              _uploadedAadhaarFront = true;
            } else if (docType == 'aadhaar_back') {
              _aadhaarBackBytes = fileBytes;
              _uploadedAadhaarBack = true;
            } else if (docType == 'pan_front') {
              _panFrontBytes = fileBytes;
              _uploadedPanFront = true;
            } else if (docType == 'pan_back') {
              _panBackBytes = fileBytes;
              _uploadedPanBack = true;
            } else if (docType == 'license_front') {
              _licenseFrontBytes = fileBytes;
              _uploadedLicenseFront = true;
            } else if (docType == 'license_back') {
              _licenseBackBytes = fileBytes;
              _uploadedLicenseBack = true;
            } else if (docType == 'rc_front') {
              _rcFrontBytes = fileBytes;
              _uploadedRCFront = true;
            } else if (docType == 'rc_back') {
              _rcBackBytes = fileBytes;
              _uploadedRCBack = true;
            } else if (docType == 'photo') {
              _photoBytes = fileBytes;
              _uploadedPhoto = true;
            } else if (docType == 'fitness') {
              _fitnessBytes = fileBytes;
              _uploadedFitness = true;
            } else if (docType == 'permit') {
              _permitBytes = fileBytes;
              _uploadedPermit = true;
            }
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${docType.replaceAll('_', ' ').toUpperCase()} document selected!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to select file: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _submitForm() async {
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
      if (isStaff) {
        if (enteredPassword != 'admin@123') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect staff password. Please enter "admin@123"'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
          return;
        }
      } else {
        if (enteredPassword != 'bhavi@123' && enteredPassword != 'admin@123') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Incorrect password. Access denied.'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
          return;
        }
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final activePhone = _mockPhoneNumber ?? widget.phoneNumber;
      final bool isStaffUser = (_userRole == 'Admin' && _adminType == 'Staff');
      final String effectiveRole = isStaffUser ? 'Staff' : _userRole;
      final roleStr = _userRole == 'Driver' ? 'partner' : (_userRole == 'Admin' ? 'admin' : 'customer');
      final passwordStr = _userRole == 'Admin' 
          ? _passwordController.text.trim() 
          : "staydriv$activePhone";
      final resolvedName = _nameController.text.trim().isNotEmpty
          ? _nameController.text.trim()
          : (isStaffUser ? 'StayDriv Staff' : (_userRole == 'Admin' ? 'StayDriv Admin' : 'StayDriv Pilot'));

      String uid = _userRole == 'Driver' ? 'mock_uid_${activePhone}_pilot' : 'mock_uid_$activePhone';

      try {
        final creds = await FirebaseService().signUp(
          email: _userRole == 'Driver' ? "${activePhone}_pilot@staydriv.com" : "${activePhone}@staydriv.com",
          password: passwordStr,
          name: resolvedName,
          phone: activePhone,
          role: roleStr,
          vehicleType: _selectedVehicle,
          vehiclePlate: 'TS 09 SD 1234',
          vehicleModelColor: 'Black Sedan',
          adminType: _adminType,
        );
        if (creds.user != null) {
          uid = creds.user!.uid;
        }
      } catch (fbErr) {
        debugPrint("Firebase signUp fallback: $fbErr");
      }

      // Upload files if role is Driver
      String? photoUrl;
      String? aadhaarFrontUrl;
      String? aadhaarBackUrl;
      String? panFrontUrl;
      String? panBackUrl;
      String? licenseFrontUrl;
      String? licenseBackUrl;
      String? rcFrontUrl;
      String? rcBackUrl;
      String? fitnessUrl;
      String? permitUrl;

      if (_userRole == 'Driver' && _pilotMode == 1) {
        final fs = FirebaseService();
        String? photoUrl;
        String? licenseFrontUrl;
        String? licenseBackUrl;

        try {
          if (_photoBytes != null) photoUrl = await fs.uploadProfilePictureToMongo(uid, _photoBytes!, 'jpg');
        } catch (e) { debugPrint("Upload photo error: $e"); }

        try {
          if (_licenseFrontBytes != null) licenseFrontUrl = await fs.uploadProfilePictureToMongo(uid, _licenseFrontBytes!, 'jpg');
        } catch (e) { debugPrint("Upload license_front error: $e"); }

        try {
          if (_licenseBackBytes != null) licenseBackUrl = await fs.uploadProfilePictureToMongo(uid, _licenseBackBytes!, 'jpg');
        } catch (e) { debugPrint("Upload license_back error: $e"); }

        try {
          final baseUrl = NetworkConfig.backendUrl;
          final replaceUrl = Uri.parse('$baseUrl/api/partner/replace-driver');
          await ApiClient().post(
            replaceUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': activePhone,
              'driverPhone': _driverPhoneController.text.isNotEmpty ? _driverPhoneController.text : activePhone,
              'driverName': resolvedName,
              'vehiclePlate': 'TS 09 SD 1234',
              'licenseFront': licenseFrontUrl,
              'licenseBack': licenseBackUrl,
              'photo': photoUrl,
            }),
            retry: false,
          );
        } catch (replaceErr) {
          debugPrint("Failed to replace driver in backend: $replaceErr");
        }
      } else if (_userRole == 'Driver') {
        final fs = FirebaseService();
        
        try {
          if (_photoBytes != null) photoUrl = await fs.uploadProfilePictureToMongo(uid, _photoBytes!, 'jpg');
        } catch (e) { debugPrint("Upload photo error: $e"); }
        
        try {
          if (_aadhaarFrontBytes != null) aadhaarFrontUrl = await fs.uploadProfilePictureToMongo(uid, _aadhaarFrontBytes!, 'jpg');
        } catch (e) { debugPrint("Upload aadhaar_front error: $e"); }
        
        try {
          if (_aadhaarBackBytes != null) aadhaarBackUrl = await fs.uploadProfilePictureToMongo(uid, _aadhaarBackBytes!, 'jpg');
        } catch (e) { debugPrint("Upload aadhaar_back error: $e"); }

        try {
          if (_panFrontBytes != null) panFrontUrl = await fs.uploadProfilePictureToMongo(uid, _panFrontBytes!, 'jpg');
        } catch (e) { debugPrint("Upload pan_front error: $e"); }

        try {
          if (_panBackBytes != null) panBackUrl = await fs.uploadProfilePictureToMongo(uid, _panBackBytes!, 'jpg');
        } catch (e) { debugPrint("Upload pan_back error: $e"); }
        
        try {
          if (_licenseFrontBytes != null) licenseFrontUrl = await fs.uploadProfilePictureToMongo(uid, _licenseFrontBytes!, 'jpg');
        } catch (e) { debugPrint("Upload license_front error: $e"); }
        
        try {
          if (_licenseBackBytes != null) licenseBackUrl = await fs.uploadProfilePictureToMongo(uid, _licenseBackBytes!, 'jpg');
        } catch (e) { debugPrint("Upload license_back error: $e"); }
        
        try {
          if (_rcFrontBytes != null) rcFrontUrl = await fs.uploadProfilePictureToMongo(uid, _rcFrontBytes!, 'jpg');
        } catch (e) { debugPrint("Upload rc_front error: $e"); }
        
        try {
          if (_rcBackBytes != null) rcBackUrl = await fs.uploadProfilePictureToMongo(uid, _rcBackBytes!, 'jpg');
        } catch (e) { debugPrint("Upload rc_back error: $e"); }
        
        try {
          if (_fitnessBytes != null) fitnessUrl = await fs.uploadProfilePictureToMongo(uid, _fitnessBytes!, 'jpg');
        } catch (e) { debugPrint("Upload fitness error: $e"); }
        
        try {
          if (_permitBytes != null) permitUrl = await fs.uploadProfilePictureToMongo(uid, _permitBytes!, 'jpg');
        } catch (e) { debugPrint("Upload permit error: $e"); }

        // Send partner status/document details to MongoDB
        try {
          final baseUrl = NetworkConfig.backendUrl;
          final updateUrl = Uri.parse('$baseUrl/api/partner/update');
          await ApiClient().post(
            updateUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'uid': uid,
              'online': false,
              'approved': true,
              'isApproved': true,
              'isDocumentVerified': true,
              'vehicleType': _selectedVehicle,
              'vehiclePlate': 'TS 09 SD 1234',
              'vehicleModelColor': 'Standard',
              'photo': photoUrl,
              'aadhaarFront': aadhaarFrontUrl,
              'aadhaarBack': aadhaarBackUrl,
              'panFront': panFrontUrl,
              'panBack': panBackUrl,
              'licenseFront': licenseFrontUrl,
              'licenseBack': licenseBackUrl,
              'rcFront': rcFrontUrl,
              'rcBack': rcBackUrl,
              'ownerPhone': _ownerPhoneController.text.isNotEmpty ? _ownerPhoneController.text : activePhone,
              'driverPhone': _driverSameAsOwner ? (_ownerPhoneController.text.isNotEmpty ? _ownerPhoneController.text : activePhone) : _driverPhoneController.text,
              'fitness': fitnessUrl,
              'permit': permitUrl,
            }),
            retry: false,
          );
        } catch (mongoUpdateErr) {
          debugPrint("Failed to update partner details in MongoDB: $mongoUpdateErr");
        }
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_logged_in', true);
        await prefs.setString('user_name', resolvedName);
        await prefs.setString('user_role', effectiveRole);
        await prefs.setString('phone_number', activePhone);
        if (_userRole == 'Driver') {
          await prefs.setString('selected_vehicle', _selectedVehicle);
        } else {
          await prefs.remove('selected_vehicle');
        }
        await prefs.setString('mock_uid', uid);
        FirebaseService.setMockUid(uid);
      } catch (prefsErr) {
        debugPrint("Error saving signup session: $prefsErr");
      }


      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              userName: resolvedName,
              userRole: effectiveRole,
              phoneNumber: activePhone,
              selectedVehicle: _userRole == 'Driver' ? _selectedVehicle : null,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration Failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.onSurfaceColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Complete Profile',
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 22,
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
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    'Tell us about yourself',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.onSurfaceColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Verification complete for +91 ${widget.phoneNumber}',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Role Selection Bento Card
                  Text(
                    'Select Profile Type',
                    style: Theme.of(context).inputDecorationTheme.labelStyle,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Customer Card
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _userRole = 'Customer';
                            _nameController.clear();
                            _emailController.clear();
                            _passwordController.clear();
                          }),
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: _userRole == 'Customer' 
                                  ? AppTheme.surfaceContainerLow 
                                  : AppTheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _userRole == 'Customer'
                                    ? AppTheme.primaryAccent
                                    : AppTheme.outlineVariant.withOpacity(0.4),
                                width: _userRole == 'Customer' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.directions_car,
                                  color: _userRole == 'Customer' 
                                      ? AppTheme.primaryColor 
                                      : AppTheme.onSurfaceVariant,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Customer',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _userRole == 'Customer' 
                                        ? AppTheme.primaryColor 
                                        : AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Driver Partner Card
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _userRole = 'Driver';
                            _nameController.clear();
                            _emailController.clear();
                            _passwordController.clear();
                          }),
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: _userRole == 'Driver' 
                                  ? AppTheme.surfaceContainerLow 
                                  : AppTheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _userRole == 'Driver'
                                    ? AppTheme.primaryAccent
                                    : AppTheme.outlineVariant.withOpacity(0.4),
                                width: _userRole == 'Driver' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.handshake_outlined,
                                  color: _userRole == 'Driver' 
                                      ? AppTheme.primaryColor 
                                      : AppTheme.onSurfaceVariant,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Pilot',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _userRole == 'Driver' 
                                        ? AppTheme.primaryColor 
                                        : AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Admin Card
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _userRole = 'Admin';
                            _nameController.text = _adminType == 'Staff' ? 'StayDriv Staff' : 'StayDriv Admin';
                            _emailController.text = 'staydriv@gmail.com';
                            _passwordController.clear();
                          }),
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: _userRole == 'Admin' 
                                  ? AppTheme.surfaceContainerLow 
                                  : AppTheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _userRole == 'Admin'
                                    ? AppTheme.primaryAccent
                                    : AppTheme.outlineVariant.withOpacity(0.4),
                                width: _userRole == 'Admin' ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.admin_panel_settings,
                                  color: _userRole == 'Admin' 
                                      ? AppTheme.primaryColor 
                                      : AppTheme.onSurfaceVariant,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Admin',
                                  style: GoogleFonts.hankenGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _userRole == 'Admin' 
                                        ? AppTheme.primaryColor 
                                        : AppTheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_userRole == 'Driver') ...[
                    Text(
                      'Select Vehicle Type',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 90,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildVehicleOnboardingCard('Bike', Icons.two_wheeler_rounded, 'Bike Taxi / small parcels'),
                          _buildVehicleOnboardingCard('Auto', Icons.electric_rickshaw_rounded, 'Fast passenger / medium'),
                          _buildVehicleOnboardingCard('Car', Icons.directions_car_rounded, 'Comfort passenger cab'),
                          _buildVehicleOnboardingCard('Mini Truck', Icons.airport_shuttle_rounded, 'Large transport / cargo'),
                          _buildVehicleOnboardingCard('Heavy Truck', Icons.local_shipping_rounded, 'Heavy goods transport'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Text Inputs
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'FULL NAME (OPTIONAL)',
                      hintText: 'John Doe',
                    ),
                    validator: (value) => null,
                  ),

                  if (_userRole == 'Admin') ...[
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _adminType,
                      decoration: const InputDecoration(
                        labelText: 'ROLE TYPE',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Staff', child: Text('Staff')),
                        DropdownMenuItem(value: 'Admin', child: Text('Admin')),
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
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'PASSWORD',
                        hintText: _adminType == 'Staff' ? 'Enter password (admin@123)' : 'Enter password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppTheme.onSurfaceVariant,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (_userRole == 'Admin') {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter password';
                          }
                          final entered = value.trim();
                          if (_adminType == 'Staff') {
                            if (entered != 'admin@123') {
                              return 'Incorrect staff password. Please enter "admin@123"';
                            }
                          } else {
                            if (entered != 'bhavi@123' && entered != 'admin@123') {
                              return 'Incorrect password. Access denied.';
                            }
                          }
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submitForm(),
                    ),
                  ],
                  if (_userRole == 'Driver') ...[
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _dobController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'DATE OF BIRTH',
                          hintText: 'Select Date of Birth',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        onTap: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // 18+ years default
                            firstDate: DateTime(1950),
                            lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                          );
                          if (picked != null) {
                            setState(() {
                              _dobController.text = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
                            });
                          }
                        },
                        validator: (value) {
                          if (_userRole == 'Driver' && (value == null || value.trim().isEmpty)) {
                            return 'Please select your Date of Birth';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_userRole != 'Admin') ...[
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _referralController,
                        decoration: const InputDecoration(
                          labelText: 'REFERRAL CODE (OPTIONAL)',
                          hintText: 'STAYDRIV50',
                        ),
                      ),
                    ],
                  const SizedBox(height: 24),

                  // Driver Document Upload Fields (Visible only when role is Driver)
                  // Driver Document Upload Fields (Visible only when role is Driver)
                  if (_userRole == 'Driver') ...[
                    // 1. Red Button: Already Registered Login
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final String phone = widget.phoneNumber;
                          final String selectedVehicle = _selectedVehicle;
                          final String uid = 'mock_uid_${phone}_pilot';
                          final String displayName = 'Pilot Partner';
                          
                          await prefs.setBool('is_logged_in', true);
                          await prefs.setString('user_name', displayName);
                          await prefs.setString('user_role', 'Driver');
                          await prefs.setString('phone_number', phone);
                          await prefs.setString('selected_vehicle', selectedVehicle);
                          await prefs.setString('mock_uid', uid);
                          
                          FirebaseService.setMockUid(uid);
                          
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HomeScreen(
                                  userName: displayName,
                                  userRole: 'Driver',
                                  phoneNumber: phone,
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 1,
                        ),
                        child: Text(
                          'ALREADY REGISTERED LOGIN',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 2. Mode Selector: New Registration vs Replace / Modify Driver
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => setState(() => _pilotMode = 0),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _pilotMode == 0 ? const Color(0xFF1B7C3E) : Colors.grey.shade200,
                                foregroundColor: _pilotMode == 0 ? Colors.white : Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: _pilotMode == 0 ? const Color(0xFF15803D) : Colors.grey.shade400,
                                    width: _pilotMode == 0 ? 2 : 1,
                                  ),
                                ),
                                elevation: _pilotMode == 0 ? 2 : 0,
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                'NEW REGISTRATION',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () => setState(() => _pilotMode = 1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _pilotMode == 1 ? const Color(0xFFE87A1E) : Colors.grey.shade200,
                                foregroundColor: _pilotMode == 1 ? Colors.white : Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: _pilotMode == 1 ? const Color(0xFFC25E0B) : Colors.grey.shade400,
                                    width: _pilotMode == 1 ? 2 : 1,
                                  ),
                                ),
                                elevation: _pilotMode == 1 ? 2 : 0,
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                'REPLACE / MODIFY DRIVER',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_pilotMode == 0) ...[
                      // SECTION 1: OWNER DETAILS (Orange Header Banner - Image 1)
                      _buildSectionHeader('OWNER DETAILS'),
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
                      _buildMobileVerificationSection(
                        sectionTitle: 'Owner Mobile',
                        phoneController: _ownerPhoneController,
                        otpControllers: _ownerOtpControllers,
                        isVerified: _isOwnerOtpVerified,
                        onToggleVerify: () => setState(() => _isOwnerOtpVerified = !_isOwnerOtpVerified),
                      ),

                      const SizedBox(height: 10),

                      // SECTION 2: VEHICLE DETAILS (Image 2)
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

                      // SECTION 3: DRIVER DETAILS (Orange Header Banner - Image 2)
                      _buildSectionHeader('DRIVER DETAILS'),
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _driverSameAsOwner,
                              activeColor: AppTheme.primaryColor,
                              onChanged: (val) {
                                setState(() {
                                  _driverSameAsOwner = val ?? true;
                                  if (_driverSameAsOwner) {
                                    _driverPhoneController.text = _ownerPhoneController.text;
                                    _isDriverOtpVerified = true;
                                  }
                                });
                              },
                            ),
                            Text(
                              'Driver is the Vehicle Owner',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppTheme.onSurfaceColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildUploadBox(
                        title: 'Driving License - Front',
                        docType: 'license_front',
                        imageBytes: _licenseFrontBytes,
                        onTap: () => _pickDocument('license_front'),
                      ),
                      _buildUploadBox(
                        title: 'Driving License - Back',
                        docType: 'license_back',
                        imageBytes: _licenseBackBytes,
                        onTap: () => _pickDocument('license_back'),
                      ),
                      if (!_driverSameAsOwner) ...[
                        _buildMobileVerificationSection(
                          sectionTitle: 'Driver Mobile',
                          phoneController: _driverPhoneController,
                          otpControllers: _driverOtpControllers,
                          isVerified: _isDriverOtpVerified,
                          onToggleVerify: () => setState(() => _isDriverOtpVerified = !_isDriverOtpVerified),
                        ),
                      ],
                      _buildUploadBox(
                        title: 'Driver Profile Photo',
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
                    ] else ...[
                      // SECTION: REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS (Orange Banner - Image 3)
                      _buildSectionHeader('REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS'),
                      _buildUploadBox(
                        title: 'Driving License - Front',
                        docType: 'license_front',
                        imageBytes: _licenseFrontBytes,
                        onTap: () => _pickDocument('license_front'),
                      ),
                      _buildUploadBox(
                        title: 'Driving License - Back',
                        docType: 'license_back',
                        imageBytes: _licenseBackBytes,
                        onTap: () => _pickDocument('license_back'),
                      ),
                      _buildMobileVerificationSection(
                        sectionTitle: 'Driver Mobile',
                        phoneController: _driverPhoneController,
                        otpControllers: _driverOtpControllers,
                        isVerified: _isDriverOtpVerified,
                        onToggleVerify: () => setState(() => _isDriverOtpVerified = !_isDriverOtpVerified),
                      ),
                      _buildUploadBox(
                        title: 'Driver Profile Photo',
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
                    ],
                    const SizedBox(height: 16),
                  ],

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _userRole == 'Admin'
                            ? const Color(0xFFE87A1E) // Orange matching user screenshot
                            : const Color(0xFF1D4ED8), // Vibrant blue
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            )
                          : Text(
                              _userRole == 'Driver' 
                                  ? 'Submit Application' 
                                  : (_userRole == 'Admin' 
                                      ? (_adminType == 'Staff' ? 'Login Staff' : 'Login Admin') 
                                      : 'Continue'),
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 18,
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
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE87A1E), // Vibrant Orange banner matching image
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: GoogleFonts.hankenGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMobileVerificationSection({
    required String sectionTitle,
    required TextEditingController phoneController,
    required List<TextEditingController> otpControllers,
    required bool isVerified,
    required VoidCallback onToggleVerify,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mobile Number',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.onSurfaceColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    Text(
                      '+91',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: AppTheme.onSurfaceVariant),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Enter 10-digit number',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                onToggleVerify();
                for (int i = 0; i < otpControllers.length; i++) {
                  if (i < 6) {
                    otpControllers[i].text = ['8', '1', '2', '1', '4', '4'][i];
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('OTP sent to +91 ${phoneController.text.isNotEmpty ? phoneController.text : "81214 40281"}: 812144'),
                    backgroundColor: const Color(0xFFE87A1E),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE87A1E), // Orange matching images
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 1,
              ),
              child: Text(
                'GET OTP',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.arrow_back, size: 16, color: AppTheme.onSurfaceColor),
                        const SizedBox(width: 6),
                        Text(
                          'Verify Mobile',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.onSurfaceColor,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: onToggleVerify,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isVerified ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isVerified ? Colors.green.shade300 : Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isVerified ? Icons.check_circle : Icons.pending,
                              size: 13,
                              color: isVerified ? Colors.green.shade700 : Colors.orange.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isVerified ? 'VERIFIED' : 'VERIFY',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: isVerified ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code sent via SMS to +91 ${phoneController.text.isNotEmpty ? phoneController.text : "81214 40281"}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    return Container(
                      width: 42,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        otpControllers[index].text.isNotEmpty ? otpControllers[index].text : '•',
                        style: GoogleFonts.robotoMono(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1D4ED8),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUploaded ? Colors.green.withOpacity(0.3) : AppTheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: ListTile(
        leading: Icon(
          hasUploaded ? Icons.check_circle : Icons.upload_file_rounded,
          color: hasUploaded ? Colors.green : AppTheme.primaryColor,
        ),
        title: Text(
          title,
          style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: AppTheme.onSurfaceColor,
          ),
        ),
        subtitle: hasUploaded
            ? Text(
                displayFileName.isNotEmpty ? '$displayFileName ($displayFileSize)' : 'Document Selected',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant,
                ),
              )
            : Text(
                'Upload JPG/JPEG document',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.onSurfaceVariant,
                ),
              ),
        trailing: hasUploaded
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, color: AppTheme.primaryColor),
                    tooltip: 'View Document',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text(
                              title,
                              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold),
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (displayFileName.isNotEmpty)
                                  Text(
                                    displayFileName,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (displayFileSize.isNotEmpty)
                                  Text(
                                    displayFileSize,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.onSurfaceVariant,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 240,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.outlineVariant),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      imageBytes,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, color: AppTheme.onSurfaceVariant),
                    tooltip: 'Change Document',
                    onPressed: onTap,
                  ),
                ],
              )
            : ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004AC6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text(
                  'Upload',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
      ),
    );
  }

  Widget _buildVehicleOnboardingCard(String name, IconData icon, String desc) {
    final isSelected = _selectedVehicle == name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicle = name;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 110,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppTheme.surfaceContainerLow 
              : AppTheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : AppTheme.outlineVariant.withOpacity(0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppTheme.primaryColor : AppTheme.onSurfaceColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
