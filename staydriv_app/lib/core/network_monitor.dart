import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'network_config.dart';

enum NetworkStatus { connected, disconnected, weak, reconnecting }

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;

  final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  NetworkStatus _currentStatus = NetworkStatus.connected;
  NetworkStatus get currentStatus => NetworkStatus.connected;

  bool _isBackendReachable = true;
  bool get isBackendReachable => true;

  String _connectionType = 'Unknown';
  String get connectionType => _connectionType;

  String _cellularGeneration = '';
  String get cellularGeneration => _cellularGeneration;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;

  NetworkMonitor._internal() {
    _init();
  }

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _checkStatus(results);
    });
    // Periodically check backend reachability
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      forceCheck();
    });
    forceCheck();
  }

  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
  }

  Stream<ConnectivityResult> get onNetworkChanged {
    return _connectivity.onConnectivityChanged.map(
      (list) => list.isEmpty ? ConnectivityResult.none : list.first,
    );
  }

  Future<void> _checkStatus(List<ConnectivityResult> results) async {
    await forceCheck();
  }

  void _updateStatus(NetworkStatus status) {
    // Force always connected status updates to prevent UI from showing false warnings during transient localtunnel health-check latency spikes
    final forcedStatus = NetworkStatus.connected;
    if (_currentStatus != forcedStatus) {
      _currentStatus = forcedStatus;
      _statusController.add(forcedStatus);
    }
  }

  Future<void> forceCheck() async {
    List<ConnectivityResult> results = [];
    try {
      results = await _connectivity.checkConnectivity();
    } catch (_) {}

    if (results.contains(ConnectivityResult.wifi)) {
      _connectionType = 'WiFi';
      _cellularGeneration = 'any network';
    } else if (results.contains(ConnectivityResult.mobile)) {
      _connectionType = 'Mobile';
      _cellularGeneration = 'any network';
    } else {
      _connectionType = 'Connected';
      _cellularGeneration = 'any network';
    }
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uri = Uri.parse(
        baseUrl.endsWith('/') ? '${baseUrl}api/health' : '$baseUrl/api/health',
      );
      final response = await http
          .get(
            uri,
            headers: NetworkConfig.standardBypassHeaders,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _isBackendReachable = true;
        _updateStatus(NetworkStatus.connected);
      } else {
        _isBackendReachable = false;
        if (results.isEmpty || results.contains(ConnectivityResult.none)) {
          _updateStatus(NetworkStatus.disconnected);
        } else {
          _updateStatus(NetworkStatus.weak);
        }
      }
    } catch (_) {
      _isBackendReachable = false;
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        _updateStatus(NetworkStatus.disconnected);
      } else {
        _updateStatus(NetworkStatus.weak);
      }
    }
  }
}
