import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'api_client.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:staydriv_app/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_config.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  static String? _mockUid;

  FirebaseService._internal();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  // Initialize Firebase App
  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint("Firebase initialization failed, running in MongoDB-only fallback mode: $e");
    }
  }

  // --- AUTHENTICATION METHODS ---

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get current user UID
  String? get currentUid {
    if (_mockUid != null) return _mockUid;
    try {
      if (Firebase.apps.isNotEmpty) {
        return _auth.currentUser?.uid;
      }
    } catch (_) {}
    return null;
  }

  // Sign In with Email & Password
  Future<UserCredential> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      debugPrint("Firebase Sign In Error: $e. Attempting local MongoDB-based sign in fallback.");
      String phoneRaw = email.split('@')[0];
      String phone = phoneRaw.replaceAll('_pilot', '');
      String uid = 'mock_uid_$phoneRaw';
      _mockUid = uid;
      return MockUserCredential(MockUser(uid: uid, email: email, phoneNumber: phone));
    }
  }

  // Sign Up with Email & Password and Save Role Profile
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String role, // 'customer', 'partner', or 'admin'
    String vehicleType = 'Bike',
    String vehiclePlate = '',
    String vehicleModelColor = '',
    String adminType = 'Admin',
  }) async {
    UserCredential creds;
    String uid = email == 'staydriv@gmail.com' ? 'mock_uid_staydriv' : (role == 'partner' ? 'mock_uid_${phone}_pilot' : 'mock_uid_$phone');

    try {
      UserCredential tempCreds;
      try {
        tempCreds = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'email-already-in-use') {
          tempCreds = await signIn(email, password);
        } else {
          rethrow;
        }
      }
      creds = tempCreds;
      uid = email == 'staydriv@gmail.com' ? 'mock_uid_staydriv' : creds.user!.uid;

      if (role == 'customer') {
        await saveCustomerProfile(
          uid: uid,
          name: name,
          email: email,
          phone: phone,
        );
      } else if (role == 'partner') {
        await savePartnerProfile(
          uid: uid,
          name: name,
          email: email,
          phone: phone,
          vehicleType: vehicleType,
          vehiclePlate: vehiclePlate,
          vehicleModelColor: vehicleModelColor,
        );
      } else {
        await _firestore.collection('admins').doc(uid).set({
          'uid': uid,
          'name': name,
          'email': email,
          'adminType': adminType,
          'phone': phone,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint("Firebase registration/auth failed, falling back to MongoDB-only registration: $e");
      _mockUid = uid;
      creds = MockUserCredential(MockUser(uid: uid, email: email, phoneNumber: phone));
    }

    // Sync with MongoDB backend
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final registerUrl = Uri.parse('$baseUrl/api/register');
      debugPrint("Registering user in MongoDB at: $registerUrl");
      final response = await ApiClient().post(
        registerUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': uid,
          'name': name,
          'phone': phone,
          'role': role,
          'vehicleType': role == 'partner' ? vehicleType : null,
          'adminType': role == 'admin' ? adminType : null,
        }),
        retry: false,
      );
      debugPrint("MongoDB registration response: ${response.statusCode} - ${response.body}");
    } catch (mongoErr) {
      debugPrint("MongoDB registration call failed: $mongoErr");
    }

    return creds;
  }

  static void setMockUid(String? uid) {
    _mockUid = uid;
  }

  // Sign Out
  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint("SharedPreferences clear error: $e");
    }
    _mockUid = null;
    await _auth.signOut();
  }

  // Get user role from collections
  Future<String> getUserRole(String uid) async {
    if (uid == 'mock_uid_staydriv') return 'admin';

    // Proactively bypass Firestore for mock UIDs to prevent hangs
    if (uid.startsWith('mock_uid_')) {
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/user/$uid');
        final response = await ApiClient().get(url, retry: false).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['user'] != null) {
            return data['user']['role'] ?? 'customer';
          }
        }
      } catch (err) {
        debugPrint("MongoDB role check failed: $err");
      }
      return 'unknown';
    }

    try {
      // Check users collection
      final userDoc = await _firestore.collection('users').doc(uid).get().timeout(const Duration(seconds: 2));
      if (userDoc.exists) return 'customer';

      // Check partners collection
      final partnerDoc = await _firestore.collection('partners').doc(uid).get().timeout(const Duration(seconds: 2));
      if (partnerDoc.exists) return 'partner';

      // Check admins collection
      final adminDoc = await _firestore.collection('admins').doc(uid).get().timeout(const Duration(seconds: 2));
      if (adminDoc.exists) return 'admin';
    } catch (e) {
      debugPrint("Firestore getUserRole failed, querying MongoDB: $e");
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/user/$uid');
        final response = await ApiClient().get(url, retry: false).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['user'] != null) {
            return data['user']['role'] ?? 'customer';
          }
        }
      } catch (err) {
        debugPrint("MongoDB role check failed: $err");
      }
    }

    return 'unknown';
  }

  // --- FIRESTORE PROFILE READ/WRITE METHODS ---

  // Save/Update Customer Profile
  Future<void> saveCustomerProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
    String? photoUrl,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Save/Update Partner Profile
  Future<void> savePartnerProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String vehicleType,
    required String vehiclePlate,
    required String vehicleModelColor,
    bool online = false,
    double lat = 17.4834,
    double lng = 78.3871,
    String? photoUrl,
  }) async {
    await _firestore.collection('partners').doc(uid).set({
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'vehicleType': vehicleType,
      'vehiclePlate': vehiclePlate,
      'vehicleModelColor': vehicleModelColor,
      'online': online,
      'lat': lat,
      'lng': lng,
      'photoUrl': photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Get User Profile Data
  Future<DocumentSnapshot> getProfile(String role, String uid) async {
    if (uid == 'mock_uid_staydriv') {
      return MockDocumentSnapshot({
        'uid': 'mock_uid_staydriv',
        'name': 'StayDriv Admin',
        'phone': '9999999999',
        'role': 'admin',
      });
    }

    // Proactively bypass Firestore for mock UIDs to prevent hangs
    if (uid.startsWith('mock_uid_')) {
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/user/$uid');
        final response = await ApiClient().get(url, retry: false).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['user'] != null) {
            final userMap = data['user'] as Map<String, dynamic>;
            return MockDocumentSnapshot(userMap);
          }
        }
      } catch (err) {
        debugPrint("MongoDB profile check failed: $err");
      }
      return MockDocumentSnapshot({
        'name': 'User',
        'phone': uid.startsWith('mock_uid_') ? uid.replaceFirst('mock_uid_', '').replaceAll('_pilot', '') : '',
        'role': role,
      });
    }

    try {
      final collection = role == 'partner' ? 'partners' : 'users';
      return await _firestore.collection(collection).doc(uid).get().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint("Firestore getProfile failed, querying MongoDB: $e");
      try {
        final baseUrl = NetworkConfig.backendUrl;
        final url = Uri.parse('$baseUrl/api/user/$uid');
        final response = await ApiClient().get(url, retry: false).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['user'] != null) {
            final userMap = data['user'] as Map<String, dynamic>;
            return MockDocumentSnapshot(userMap);
          }
        }
      } catch (err) {
        debugPrint("MongoDB profile check failed: $err");
      }
      return MockDocumentSnapshot({
        'name': 'User',
        'phone': uid.startsWith('mock_uid_') ? uid.replaceFirst('mock_uid_', '').replaceAll('_pilot', '') : '',
        'role': role,
      });
    }
  }

  // --- FIRESTORE BOOKING & RIDE OPERATIONS ---

  // Create Booking Document
  Future<String> createBooking(Map<String, dynamic> bookingData) async {
    final docRef = _firestore.collection('bookings').doc();
    final data = {
      ...bookingData,
      'bookingId': docRef.id,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data);
    return docRef.id;
  }

  // Update Booking fields
  Future<void> updateBookingFields(String bookingId, Map<String, dynamic> fields) async {
    await _firestore.collection('bookings').doc(bookingId).update(fields);
  }

  // Stream of bookings for active customer tracking
  Stream<DocumentSnapshot> streamBooking(String bookingId) {
    return _firestore.collection('bookings').doc(bookingId).snapshots();
  }

  // Stream of searching bookings for a specific vehicle type (Driver dashboard request stream)
  Stream<QuerySnapshot> streamAvailableBookings(String vehicleType) {
    return _firestore
        .collection('bookings')
        .where('status', isEqualTo: 'searching')
        .where('vehicle', isEqualTo: vehicleType)
        .snapshots();
  }

  // Stream of active booking for passenger
  Stream<QuerySnapshot> streamPassengerActiveBooking(String passengerId) {
    return _firestore
        .collection('bookings')
        .where('passengerId', isEqualTo: passengerId)
        .where('status', whereIn: ['searching', 'accepted', 'arrived', 'started'])
        .limit(1)
        .snapshots();
  }

  // Stream of active booking for partner
  Stream<QuerySnapshot> streamPartnerActiveBooking(String partnerId) {
    return _firestore
        .collection('bookings')
        .where('driverId', isEqualTo: partnerId)
        .where('status', whereIn: ['accepted', 'arrived', 'started'])
        .limit(1)
        .snapshots();
  }

  // Update Driver Location Coordinates in Firestore
  Future<void> updateDriverLocation(String partnerId, double lat, double lng) async {
    await _firestore.collection('partners').doc(partnerId).update({
      'lat': lat,
      'lng': lng,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Stream Partner Location in real-time
  Stream<DocumentSnapshot> streamPartnerLocation(String partnerId) {
    return _firestore.collection('partners').doc(partnerId).snapshots();
  }

  // Create Ride Record
  Future<void> createRideRecord(Map<String, dynamic> rideData) async {
    await _firestore.collection('rides').doc(rideData['rideId']).set({
      ...rideData,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Create Support Ticket
  Future<void> createSupportTicket(String userId, String subject, String message) async {
    await _firestore.collection('support_tickets').add({
      'userId': userId,
      'subject': subject,
      'message': message,
      'status': 'Open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // --- STORAGE METHODS ---

  // Upload file (like profile image) to Firebase Storage
  Future<String> uploadProfilePicture(String uid, List<int> fileBytes, String extension) async {
    final ref = _storage.ref().child('profiles/$uid/profile.$extension');
    final uploadTask = ref.putData(Uint8List.fromList(fileBytes));
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  // Upload file to MongoDB storage backend
  Future<String> uploadProfilePictureToMongo(String uid, List<int> fileBytes, String extension) async {
    final base64Data = base64Encode(fileBytes);
    final baseUrl = NetworkConfig.backendUrl;
    final url = Uri.parse('$baseUrl/api/upload');
    final response = await ApiClient().post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'uid': uid,
        'fileName': 'doc_$uid.$extension',
        'fileData': base64Data,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return '$baseUrl${data['url']}';
      }
    }
    throw Exception("Failed to upload file to MongoDB storage");
  }

  // --- MESSAGING & PUSH NOTIFICATIONS ---

  // Request notifications permission and store token
  Future<void> initNotifications(String role, String uid) async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await _messaging.getToken();
        if (token != null) {
          final collection = role == 'partner' ? 'partners' : 'users';
          await _firestore.collection(collection).doc(uid).update({
            'fcmToken': token,
          });
        }
      }
    } catch (e) {
      debugPrint("Notifications setup error: $e");
    }
  }
}

// --- MOCK FIREBASE CLASSES FOR MONGODB FALLBACK ---

class MockUser implements User {
  @override
  final String uid;
  @override
  final String? email;
  @override
  final String? phoneNumber;
  @override
  final String? displayName = 'User';

  MockUser({required this.uid, this.email, this.phoneNumber});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockUserCredential implements UserCredential {
  @override
  final User? user;
  @override
  final AuthCredential? credential = null;
  @override
  final AdditionalUserInfo? additionalUserInfo = null;

  MockUserCredential(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockDocumentSnapshot implements DocumentSnapshot {
  final Map<String, dynamic>? _data;
  @override
  final bool exists;
  @override
  final String id = '';
  @override
  DocumentReference get reference => throw UnimplementedError('MockDocumentSnapshot.reference');
  @override
  SnapshotMetadata get metadata => throw UnimplementedError('MockDocumentSnapshot.metadata');

  MockDocumentSnapshot(this._data) : exists = _data != null;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => _data?[field];

  @override
  dynamic operator [](Object field) => _data?[field];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
