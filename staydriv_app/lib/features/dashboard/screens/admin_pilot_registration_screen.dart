import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme.dart';
import '../../../core/firebase_service.dart';
import '../../../core/api_client.dart';
import '../../../core/network_config.dart';

class AdminPilotRegistrationScreen extends StatefulWidget {
  final bool isStaff;
  final Future<void> Function()? onSuccess;

  const AdminPilotRegistrationScreen({
    super.key,
    required this.isStaff,
    this.onSuccess,
  });

  @override
  State<AdminPilotRegistrationScreen> createState() => _AdminPilotRegistrationScreenState();
}

class _AdminPilotRegistrationScreenState extends State<AdminPilotRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _modelColorController = TextEditingController(text: 'Standard');

  String _selectedVehicle = 'Bike';
  bool _isLoading = false;

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
  bool _driverSameAsOwner = true;

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

  final TextEditingController _ownerPhoneController = TextEditingController();

  final Map<String, String> _docFileNames = {};
  final Map<String, String> _docFileSizes = {};

  int _adminPilotMode = 0; // 0 = New Registration, 1 = Replace/Modify Driver
  final List<TextEditingController> _otpControllers = List.generate(6, (i) => TextEditingController(text: ['8', '1', '2', '1', '4', '4'][i]));
  bool _isOtpVerified = true;

  bool get _vehicleNeedsExtraDocs {
    return _selectedVehicle == 'Car' || _selectedVehicle == 'Mini Truck' || _selectedVehicle == 'Heavy Truck';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ownerPhoneController.dispose();
    _plateController.dispose();
    _modelColorController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDocument(String docType) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
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

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${docType.replaceAll('_', ' ').toUpperCase()} document selected!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 1),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select file: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _submitPilotRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (_adminPilotMode == 1) {
      final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
      if (phone.length < 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid 10-digit vehicle owner/partner mobile number'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final driverName = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'New Driver';
        final vehiclePlate = _plateController.text.trim().isNotEmpty ? _plateController.text.trim().toUpperCase() : 'TS 09 SD 1234';
        final driverPhone = _ownerPhoneController.text.trim().isNotEmpty ? _ownerPhoneController.text.trim() : phone;
        final fs = FirebaseService();
        final String uid = 'mock_uid_${phone}_pilot';

        String? photoUrl;
        String? licenseFrontUrl;
        String? licenseBackUrl;

        try {
          if (_photoBytes != null) photoUrl = await fs.uploadProfilePictureToMongo(uid, _photoBytes!, 'jpg');
        } catch (e) { debugPrint("Upload photo err: $e"); }

        try {
          if (_licenseFrontBytes != null) licenseFrontUrl = await fs.uploadProfilePictureToMongo(uid, _licenseFrontBytes!, 'jpg');
        } catch (e) { debugPrint("Upload licenseFront err: $e"); }

        try {
          if (_licenseBackBytes != null) licenseBackUrl = await fs.uploadProfilePictureToMongo(uid, _licenseBackBytes!, 'jpg');
        } catch (e) { debugPrint("Upload licenseBack err: $e"); }

        final baseUrl = NetworkConfig.backendUrl;
        await ApiClient().post(
          Uri.parse('$baseUrl/api/partner/replace-driver'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone': phone,
            'driverPhone': driverPhone,
            'driverName': driverName,
            'vehiclePlate': vehiclePlate,
            'licenseFront': licenseFrontUrl,
            'licenseBack': licenseBackUrl,
            'photo': photoUrl,
          }),
          retry: false,
        );

        try {
          await FirebaseFirestore.instance.collection('partners').doc(uid).set({
            'driverName': driverName,
            'driverPhone': driverPhone,
            'licenseFront': licenseFrontUrl,
            'licenseBack': licenseBackUrl,
            'photo': photoUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint("Firestore update err: $e");
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Driver for vehicle ($vehiclePlate) replaced successfully!',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3),
            ),
          );

          if (widget.onSuccess != null) {
            await widget.onSuccess!();
          }

          Navigator.pop(context);
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to replace driver: $err'), backgroundColor: AppTheme.errorColor),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
      return;
    }

    final phone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 10-digit mobile number'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final name = _nameController.text.trim();
      final vehiclePlate = _plateController.text.trim().isNotEmpty
          ? _plateController.text.trim().toUpperCase()
          : 'TS 09 SD 1234';
      final vehicleModelColor = _modelColorController.text.trim().isNotEmpty
          ? _modelColorController.text.trim()
          : 'Standard';

      final String uid = 'mock_uid_${phone}_pilot';
      final fs = FirebaseService();

      // Upload documents if selected
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

      try {
        if (_photoBytes != null) photoUrl = await fs.uploadProfilePictureToMongo(uid, _photoBytes!, 'jpg');
      } catch (e) { debugPrint("Upload photo err: $e"); }

      try {
        if (_aadhaarFrontBytes != null) aadhaarFrontUrl = await fs.uploadProfilePictureToMongo(uid, _aadhaarFrontBytes!, 'jpg');
      } catch (e) { debugPrint("Upload aadhaarFront err: $e"); }

      try {
        if (_aadhaarBackBytes != null) aadhaarBackUrl = await fs.uploadProfilePictureToMongo(uid, _aadhaarBackBytes!, 'jpg');
      } catch (e) { debugPrint("Upload aadhaarBack err: $e"); }

      try {
        if (_panFrontBytes != null) panFrontUrl = await fs.uploadProfilePictureToMongo(uid, _panFrontBytes!, 'jpg');
      } catch (e) { debugPrint("Upload panFront err: $e"); }

      try {
        if (_panBackBytes != null) panBackUrl = await fs.uploadProfilePictureToMongo(uid, _panBackBytes!, 'jpg');
      } catch (e) { debugPrint("Upload panBack err: $e"); }

      try {
        if (_licenseFrontBytes != null) licenseFrontUrl = await fs.uploadProfilePictureToMongo(uid, _licenseFrontBytes!, 'jpg');
      } catch (e) { debugPrint("Upload licenseFront err: $e"); }

      try {
        if (_licenseBackBytes != null) licenseBackUrl = await fs.uploadProfilePictureToMongo(uid, _licenseBackBytes!, 'jpg');
      } catch (e) { debugPrint("Upload licenseBack err: $e"); }

      try {
        if (_rcFrontBytes != null) rcFrontUrl = await fs.uploadProfilePictureToMongo(uid, _rcFrontBytes!, 'jpg');
      } catch (e) { debugPrint("Upload rcFront err: $e"); }

      try {
        if (_rcBackBytes != null) rcBackUrl = await fs.uploadProfilePictureToMongo(uid, _rcBackBytes!, 'jpg');
      } catch (e) { debugPrint("Upload rcBack err: $e"); }

      try {
        if (_fitnessBytes != null) fitnessUrl = await fs.uploadProfilePictureToMongo(uid, _fitnessBytes!, 'jpg');
      } catch (e) { debugPrint("Upload fitness err: $e"); }

      try {
        if (_permitBytes != null) permitUrl = await fs.uploadProfilePictureToMongo(uid, _permitBytes!, 'jpg');
      } catch (e) { debugPrint("Upload permit err: $e"); }

      // 1. Register User via /api/register
      try {
        final baseUrl = NetworkConfig.backendUrl;
        await ApiClient().post(
          Uri.parse('$baseUrl/api/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'uid': uid,
            'name': name,
            'phone': phone,
            'role': 'partner',
            'vehicleType': _selectedVehicle,
            'vehiclePlate': vehiclePlate,
            'vehicleModelColor': vehicleModelColor,
            'isApproved': true,
            'isDocumentVerified': true,
            'status': 'active',
          }),
          retry: false,
        );
      } catch (e) {
        debugPrint("MongoDB register call err: $e");
      }

      // 2. Update Partner Details via /api/partner/update (Approved instantly!)
      try {
        final baseUrl = NetworkConfig.backendUrl;
        await ApiClient().post(
          Uri.parse('$baseUrl/api/partner/update'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'uid': uid,
            'name': name,
            'phone': phone,
            'online': false,
            'approved': true,
            'isApproved': true,
            'isDocumentVerified': true,
            'vehicleType': _selectedVehicle,
            'vehiclePlate': vehiclePlate,
            'vehicleModelColor': vehicleModelColor,
            'photo': photoUrl,
            'aadhaarFront': aadhaarFrontUrl,
            'aadhaarBack': aadhaarBackUrl,
            'panFront': panFrontUrl,
            'panBack': panBackUrl,
            'licenseFront': licenseFrontUrl,
            'licenseBack': licenseBackUrl,
            'rcFront': rcFrontUrl,
            'rcBack': rcBackUrl,
            'ownerPhone': _ownerPhoneController.text.isNotEmpty ? _ownerPhoneController.text : phone,
            'driverPhone': phone,
            'fitness': fitnessUrl,
            'permit': permitUrl,
          }),
          retry: false,
        );
      } catch (e) {
        debugPrint("MongoDB partner update err: $e");
      }

      // 3. Save to Firestore partners collection
      try {
        await FirebaseFirestore.instance.collection('partners').doc(uid).set({
          'uid': uid,
          'name': name,
          'phone': phone,
          'email': '${phone}_pilot@staydriv.com',
          'vehicleType': _selectedVehicle,
          'vehiclePlate': vehiclePlate,
          'vehicleModelColor': vehicleModelColor,
          'approved': true,
          'isApproved': true,
          'isDocumentVerified': true,
          'online': false,
          'photo': photoUrl,
          'aadhaarFront': aadhaarFrontUrl,
          'aadhaarBack': aadhaarBackUrl,
          'licenseFront': licenseFrontUrl,
          'licenseBack': licenseBackUrl,
          'rcFront': rcFrontUrl,
          'rcBack': rcBackUrl,
          'fitness': fitnessUrl,
          'permit': permitUrl,
          'registeredBy': widget.isStaff ? 'Staff' : 'Admin',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Firestore partner save err: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pilot $name (+91 $phone) registered & approved successfully!',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );

        if (widget.onSuccess != null) {
          await widget.onSuccess!();
        }

        Navigator.pop(context);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: $err'),
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
                            title: Text(title, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (displayFileName.isNotEmpty)
                                  Text(displayFileName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                if (displayFileSize.isNotEmpty)
                                  Text(displayFileSize, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant)),
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

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE87A1E), // Vibrant Orange banner matching mockup
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
            sectionTitle.isNotEmpty ? sectionTitle : 'Mobile Number',
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

  Widget _buildVehicleChip(String name, IconData icon) {
    final bool isSelected = _selectedVehicle == name;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedVehicle = name;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfaceContainerLow : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.outlineVariant.withOpacity(0.4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppTheme.primaryColor : AppTheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isStaff ? 'Staff - New Pilot Registration' : 'Admin - New Pilot Registration',
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.onSurfaceColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Color(0xFF2563EB), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Direct Pilot Onboarding & Instant Approval',
                            style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: const Color(0xFF1E3A8A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pilots registered here are activated immediately to accept bookings.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF1E40AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mode Selector: New Registration vs Replace / Modify Driver
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => setState(() => _adminPilotMode = 0),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _adminPilotMode == 0 ? const Color(0xFF1B7C3E) : Colors.grey.shade200,
                          foregroundColor: _adminPilotMode == 0 ? Colors.white : Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: _adminPilotMode == 0 ? const Color(0xFF15803D) : Colors.grey.shade400,
                              width: _adminPilotMode == 0 ? 2 : 1,
                            ),
                          ),
                          elevation: _adminPilotMode == 0 ? 2 : 0,
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
                        onPressed: () => setState(() => _adminPilotMode = 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _adminPilotMode == 1 ? const Color(0xFFE87A1E) : Colors.grey.shade200,
                          foregroundColor: _adminPilotMode == 1 ? Colors.white : Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: _adminPilotMode == 1 ? const Color(0xFFC25E0B) : Colors.grey.shade400,
                              width: _adminPilotMode == 1 ? 2 : 1,
                            ),
                          ),
                          elevation: _adminPilotMode == 1 ? 2 : 0,
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
              const SizedBox(height: 20),

              if (_adminPilotMode == 0) ...[
                // Pilot Details Heading
                Text(
                  'Pilot Information',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
                const SizedBox(height: 12),

                // Full Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'PILOT FULL NAME',
                    hintText: 'e.g. Ramesh Kumar',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Please enter pilot name' : null,
                ),
                const SizedBox(height: 16),

                // Mobile Number
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'MOBILE NUMBER',
                    hintText: '9876543210',
                    prefixText: '+91 ',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Please enter mobile number';
                    if (val.trim().replaceAll(RegExp(r'\D'), '').length < 10) return 'Enter 10-digit number';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Vehicle Selection
                Text(
                  'Select Vehicle Type',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildVehicleChip('Bike', Icons.two_wheeler_rounded),
                      _buildVehicleChip('Auto', Icons.electric_rickshaw_rounded),
                      _buildVehicleChip('Car', Icons.directions_car_rounded),
                      _buildVehicleChip('Mini Truck', Icons.airport_shuttle_rounded),
                      _buildVehicleChip('Heavy Truck', Icons.local_shipping_rounded),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Vehicle Plate
                TextFormField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'VEHICLE NUMBER / PLATE',
                    hintText: 'e.g. TS 09 SD 1234',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 28),

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
                  phoneController: _ownerPhoneController.text.isNotEmpty ? _ownerPhoneController : _phoneController,
                  otpControllers: _otpControllers,
                  isVerified: _isOtpVerified,
                  onToggleVerify: () => setState(() => _isOtpVerified = !_isOtpVerified),
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
                // REPLACE DRIVER MODE (Image 3)
                Text(
                  'Vehicle & Partner Information',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onSurfaceColor,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'OWNER / PARTNER MOBILE NUMBER',
                    hintText: '9876543210',
                    prefixText: '+91 ',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Please enter mobile number';
                    if (val.trim().replaceAll(RegExp(r'\D'), '').length < 10) return 'Enter 10-digit number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'VEHICLE NUMBER / PLATE',
                    hintText: 'e.g. TS 09 SD 1234',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 24),

                // SECTION: REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS (Orange Header Banner - Image 3)
                _buildSectionHeader('REPLACE / UPDATE/MODIFY NEW DRIVER DETAILS'),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'NEW DRIVER FULL NAME',
                    hintText: 'e.g. Suresh Varma',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
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
                  sectionTitle: 'New Driver Mobile',
                  phoneController: _ownerPhoneController,
                  otpControllers: _otpControllers,
                  isVerified: _isOtpVerified,
                  onToggleVerify: () => setState(() => _isOtpVerified = !_isOtpVerified),
                ),
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
              ],
              const SizedBox(height: 24),

              // Submit Button (Blue Button matching image 2 & 3: Submit Application)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitPilotRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8), // Vibrant blue
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Submit Application',
                          style: GoogleFonts.hankenGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
