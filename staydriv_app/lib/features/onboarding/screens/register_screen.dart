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
import 'login_screen.dart';

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
  
  late String _userRole; // Customer or Driver or Admin
  String _selectedVehicle = 'Bike'; // Default selected vehicle
  bool _isLoading = false;
  String _adminType = 'Admin'; // Staff or Admin
  String? _mockPhoneNumber;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _userRole = widget.initialRole ?? 'Customer';
    if (_userRole == 'Admin') {
      _nameController.text = 'StayDriv Admin';
      _passwordController.clear();
    }
  }
  
  // Document upload state flags
  bool _uploadedAadhaarFront = false;
  bool _uploadedAadhaarBack = false;
  bool _uploadedLicenseFront = false;
  bool _uploadedLicenseBack = false;
  bool _uploadedRCFront = false;
  bool _uploadedRCBack = false;
  bool _uploadedPhoto = false;
  bool _uploadedFitness = false;
  bool _uploadedPermit = false;

  Uint8List? _aadhaarFrontBytes;
  Uint8List? _aadhaarBackBytes;
  Uint8List? _licenseFrontBytes;
  Uint8List? _licenseBackBytes;
  Uint8List? _rcFrontBytes;
  Uint8List? _rcBackBytes;
  Uint8List? _photoBytes;
  Uint8List? _fitnessBytes;
  Uint8List? _permitBytes;

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
          setState(() {
            if (docType == 'aadhaar_front') {
              _aadhaarFrontBytes = fileBytes;
              _uploadedAadhaarFront = true;
            } else if (docType == 'aadhaar_back') {
              _aadhaarBackBytes = fileBytes;
              _uploadedAadhaarBack = true;
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
      final enteredPassword = _passwordController.text.trim();
      if (enteredPassword.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password is required to access Admin'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
      if (enteredPassword != 'bhavi@123') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect password. Access denied.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }
    }

    if (_userRole == 'Driver') {
      if (!_uploadedAadhaarFront || !_uploadedAadhaarBack ||
          !_uploadedLicenseFront || !_uploadedLicenseBack ||
          !_uploadedRCFront || !_uploadedRCBack || !_uploadedPhoto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload all required driver documents to continue'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      if (_vehicleNeedsExtraDocs) {
        if (!_uploadedFitness || !_uploadedPermit) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please upload Fitness Certificate and Permit for your vehicle'),
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
      final roleStr = _userRole == 'Driver' ? 'partner' : (_userRole == 'Admin' ? 'admin' : 'customer');
      final passwordStr = _userRole == 'Admin' ? _passwordController.text.trim() : "staydriv$activePhone";
      final resolvedName = _userRole == 'Admin' ? 'StayDriv Admin' : (_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'StayDriv User');

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
      String? licenseFrontUrl;
      String? licenseBackUrl;
      String? rcFrontUrl;
      String? rcBackUrl;
      String? fitnessUrl;
      String? permitUrl;

      if (_userRole == 'Driver') {
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
              'approved': _mockPhoneNumber != null ? false : true,
              'vehicleType': _selectedVehicle,
              'vehiclePlate': 'TS 09 SD 1234',
              'vehicleModelColor': 'Black Sedan',
              'photo': photoUrl,
              'aadhaarFront': aadhaarFrontUrl,
              'aadhaarBack': aadhaarBackUrl,
              'licenseFront': licenseFrontUrl,
              'licenseBack': licenseBackUrl,
              'rcFront': rcFrontUrl,
              'rcBack': rcBackUrl,
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
        await prefs.setString('user_role', _userRole);
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
              userName: _userRole == 'Admin' ? 'StayDriv Admin' : (_nameController.text.isNotEmpty ? _nameController.text : 'User'),
              userRole: _userRole,
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
                            _nameController.text = 'StayDriv Admin';
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
                        hintText: '••••••••',
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
                            return 'Password is required to access Admin';
                          }
                          if (value.trim() != 'bhavi@123') {
                            return 'Incorrect password. Access denied.';
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
                  if (_userRole == 'Driver') ...[
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 50,
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
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 1,
                            ),
                            child: Text(
                              'NEW REGISTRATION',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 40),
                    Text(
                      'Required Verification Documents',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'All documents are processed and approved instantly.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Aadhaar Upload Boxes
                    Row(
                      children: [
                        Expanded(
                          child: _buildUploadBox(
                            title: 'Aadhaar - Front',
                            imageBytes: _aadhaarFrontBytes,
                            onTap: () => _pickDocument('aadhaar_front'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildUploadBox(
                            title: 'Aadhaar - Back',
                            imageBytes: _aadhaarBackBytes,
                            onTap: () => _pickDocument('aadhaar_back'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // License Upload Boxes
                    Row(
                      children: [
                        Expanded(
                          child: _buildUploadBox(
                            title: 'License - Front',
                            imageBytes: _licenseFrontBytes,
                            onTap: () => _pickDocument('license_front'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildUploadBox(
                            title: 'License - Back',
                            imageBytes: _licenseBackBytes,
                            onTap: () => _pickDocument('license_back'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // RC Upload Boxes
                    Row(
                      children: [
                        Expanded(
                          child: _buildUploadBox(
                            title: 'Vehicle RC - Front',
                            imageBytes: _rcFrontBytes,
                            onTap: () => _pickDocument('rc_front'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildUploadBox(
                            title: 'Vehicle RC - Back',
                            imageBytes: _rcBackBytes,
                            onTap: () => _pickDocument('rc_back'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Profile Photo Upload Box
                    _buildUploadBox(
                      title: 'Driver Profile Photo',
                      imageBytes: _photoBytes,
                      onTap: () => _pickDocument('photo'),
                    ),
                    
                    // Conditional Vehicle Documents (Fitness and Permit)
                    if (_vehicleNeedsExtraDocs) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildUploadBox(
                              title: 'Fitness Certificate',
                              imageBytes: _fitnessBytes,
                              onTap: () => _pickDocument('fitness'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildUploadBox(
                              title: 'Vehicle Permit',
                              imageBytes: _permitBytes,
                              onTap: () => _pickDocument('permit'),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitForm,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                            )
                          : Text(
                              _userRole == 'Driver' ? 'Submit Application' : 'Login',
                              style: GoogleFonts.hankenGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
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

  Widget _buildUploadBox({
    required String title,
    required Uint8List? imageBytes,
    required VoidCallback onTap,
  }) {
    final bool isUploaded = imageBytes != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: isUploaded ? Colors.transparent : AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUploaded ? Colors.green : AppTheme.outlineVariant.withOpacity(0.5),
            width: isUploaded ? 1.5 : 1,
          ),
          image: isUploaded
              ? DecorationImage(
                  image: MemoryImage(imageBytes),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.4),
                    BlendMode.darken,
                  ),
                )
              : null,
        ),
        child: isUploaded
            ? Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'SELECTED',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 24,
                              ),
                            ],
                          ),
                          Text(
                            title,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 3.0,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                  ),
                  Text(
                    'TAP TO UPLOAD',
                    style: GoogleFonts.robotoMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
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
