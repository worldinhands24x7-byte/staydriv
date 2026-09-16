import 'dart:convert';
import 'dart:io';

class LatLng {
  final double latitude;
  final double longitude;
  const LatLng(this.latitude, this.longitude);
  @override
  String toString() => '$latitude,$longitude';
}

List<LatLng> decodePolyline(String encoded) {
  List<LatLng> poly = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
  }
  return poly;
}

void main() async {
  final apiKey = 'AIzaSyD2Lw1UPJAVtzSBY4JARHS6yV284w2hneg';
  final origin = '17.526372502339854,78.42397988065278';
  final destination = '17.5046831,78.521394';
  final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$apiKey';

  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  client.close();

  final data = json.decode(responseBody);
  if (data['status'] == 'OK') {
    final route = data['routes'][0];
    final String polylineStr = route['overview_polyline']['points'];
    print('Encoded Polyline: $polylineStr');
    final decoded = decodePolyline(polylineStr);
    print('Decoded Points Count: ${decoded.length}');
    print('First 5 points:');
    decoded.take(5).forEach(print);
    print('Last 5 points:');
    decoded.skip(decoded.length - 5).forEach(print);
  } else {
    print('Directions API error: ${data['status']}');
  }
}
