import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../google_map_api.dart'; // Make sure this file returns your API key

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // Map controller
  GoogleMapController? _mapController;
  
  // Current user location
  Position? _currentPosition;
  bool _isLoading = true;
  String _errorMessage = '';
  
  // Map related variables
  Set<Marker> _markers = {};
  Set<Marker> _allMarkers = {}; // All markers including current user
  Set<Circle> _circles = {}; // For pulsing location indicator
  final LatLng _defaultLocation = LatLng(36.8065, 10.1815); // Default location: Tunis
  
  // Firebase references
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final DatabaseReference _databaseRef;
  User? get _currentUser => _auth.currentUser;

  // Custom marker icons
  BitmapDescriptor? _busMarkerIcon;
  BitmapDescriptor? _passengerMarkerIcon;
  
  // Timer for periodic location updates
  Timer? _locationUpdateTimer;
  
  // Animation for user marker
  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseAnimation;
  double _userMarkerScale = 1.0;
  
  // Add user type state
  bool? _isCurrentUserDriver;
  String? _currentUserName;

  // For bottom sheet info
  String? _selectedDriverName;
  double? _selectedDriverLat;
  double? _selectedDriverLng;
  double? _selectedDriverETA;
  String? _selectedDriverId;
  
  // For passenger info bottom sheet
  String? _selectedPassengerName;
  String? _selectedPassengerMessage;
  String? _selectedPassengerPhone;
  double? _selectedPassengerLat;
  double? _selectedPassengerLng;
  String? _selectedPassengerId;

  Set<Polyline> _polylines = {};
  List<LatLng> _polylineCoordinates = [];

  @override
  void initState() {
    super.initState();
    FirebaseDatabase database = FirebaseDatabase.instance;
    database.databaseURL = 'https://studenist-61999-default-rtdb.europe-west1.firebasedatabase.app';
    _databaseRef = database.ref();
    
    // Initialize pulse animation controller
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut)
    );
    
    // Update scale whenever animation changes
    _pulseAnimationController.addListener(() {
      setState(() {
        _userMarkerScale = _pulseAnimation.value;
      });
    });
    
    _fetchCurrentUserType();
    _createTinyMarkerIcons();
    _initMap();
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _updateCurrentLocation();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _locationUpdateTimer?.cancel();
    _pulseAnimationController.dispose();
    super.dispose();
  }
  
  Future<void> _updateCurrentLocation() async {
    if (_currentUser == null) return;
    
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      setState(() {
        _currentPosition = position;
      });
      
      // Update the user's location marker
      _updateMyLocationMarker();
      
      // Get user type and other details from Firestore
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      bool isDriver = false;
      String name = 'Unknown';
      String phone = '';
      
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        isDriver = userData['isDriver'] ?? false;
        name = userData['fullName'] ?? 'Unknown';
        phone = userData['phone'] ?? '';
      }
      
      // Update location in Realtime Database
      await _databaseRef.child('passengers').child(_currentUser!.uid).update({
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'updated_at': ServerValue.timestamp,
        },
        'name': name,
        'isDriver': isDriver,
        'phone': phone,
        'active': true,
        'last_online': ServerValue.timestamp,
      });
      
      print("Updated location in Realtime DB: lat=${position.latitude}, lng=${position.longitude}");
    } catch (e) {
      print("Error in periodic location update: $e");
    }
  }

  Future<void> _createTinyMarkerIcons() async {
    try {
      _busMarkerIcon = await _bitmapDescriptorFromAsset('assets/images/bus_marker.png', 100);
      _passengerMarkerIcon = await _bitmapDescriptorFromAsset('assets/images/passenger_marker.png', 100);
      print("Loaded asset images for markers");
    } catch (e) {
      print("Error loading marker images: $e");
      _busMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      _passengerMarkerIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
  }
  
  Future<BitmapDescriptor> _bitmapDescriptorFromAsset(String path, int width) async {
    final ByteData data = await rootBundle.load(path);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? bytes = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _initMap() async {
    try {
      await _getCurrentLocation();
      _listenToLocationUpdates();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing map: $e';
        _isLoading = false;
      });
      print("ERROR INITIALIZING MAP: $e");
      Fluttertoast.showToast(
        msg: "Map initialization error: $e",
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }
  
  // Get user's current location
  Future<void> _getCurrentLocation() async {
    try {
      print("Getting current location...");
      
      // Check location service enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Location services are disabled';
          _isLoading = false;
        });
        print("Location services are disabled");
        Fluttertoast.showToast(msg: "Location services are disabled");
        return;
      }
      
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permissions are denied';
            _isLoading = false;
          });
          print("Location permissions are denied");
          Fluttertoast.showToast(msg: "Location permissions are denied");
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Location permissions are permanently denied';
          _isLoading = false;
        });
        print("Location permissions are permanently denied");
        Fluttertoast.showToast(msg: "Location permissions are permanently denied");
        return;
      }
      
      print("Getting position...");
      // Get the position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      print("Position: Lat: ${position.latitude}, Long: ${position.longitude}");
      
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      
      // Add the user's location marker
      _updateMyLocationMarker();
      
      // Update user's location in Firestore and Realtime DB
      if (_currentUser != null) {
        try {
          // Get user info from Firestore to determine user type
          DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
          bool isDriver = false;
          String name = 'Unknown';
          String phone = '';
          
          if (userDoc.exists) {
            Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
            isDriver = userData['isDriver'] ?? false;
            name = userData['fullName'] ?? 'Unknown';
            phone = userData['phone'] ?? '';
          }
          
          // Update Realtime Database with location and active status
          await _databaseRef.child('passengers').child(_currentUser!.uid).update({
            'location': {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'updated_at': ServerValue.timestamp,
            },
            'name': name,
            'isDriver': isDriver,
            'phone': phone,
            'active': true,
            'last_online': ServerValue.timestamp,
          });
          
          print("Successfully updated user location in Realtime DB for user: ${_currentUser!.uid}");
          print("Location: lat=${position.latitude}, lng=${position.longitude}");
        } catch (error) {
          print("Error updating location: $error");
          Fluttertoast.showToast(msg: "Error updating your location");
        }
      } else {
        print("No current user found to update location");
      }
      
      // Move camera to current location (if controller is ready)
      if (_mapController != null) {
        print("Moving camera to current location...");
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            15.0
          )
        );
      } else {
        print("Map controller is null, can't move camera yet");
      }
    } catch (e) {
      print("Error getting location: $e");
      setState(() {
        _errorMessage = 'Error getting location: $e';
        _isLoading = false;
      });
      Fluttertoast.showToast(msg: "Error getting location: $e");
    }
  }
  
  // Add a method to update the user's location marker
  void _updateMyLocationMarker() {
    if (_currentPosition == null || _passengerMarkerIcon == null || _busMarkerIcon == null) return;
    
    // Choose the appropriate icon based on user role
    BitmapDescriptor markerIcon = _isCurrentUserDriver == true 
        ? _busMarkerIcon! 
        : _passengerMarkerIcon!;
    
    // Create a marker for the current user's position
    Marker myLocationMarker = Marker(
      markerId: MarkerId('my_location'),
      position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      icon: markerIcon,
      anchor: Offset(0.5, 0.5),
      flat: true,
      zIndex: 2.0, // Higher zIndex to show above other markers
      infoWindow: InfoWindow(title: 'Your Location'),
    );
    
    // Create a pulsing circle around the user's location
    Circle locationCircle = Circle(
      circleId: CircleId('my_location_circle'),
      center: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      radius: 80 * _userMarkerScale, // Larger animated radius
      fillColor: Colors.deepPurple.withOpacity(0.15),
      strokeColor: Colors.deepPurple.withOpacity(0.7),
      strokeWidth: 3,
      zIndex: 1, // Below the marker but above other elements
    );
    
    setState(() {
      // Update the allMarkers set which includes both user markers and the current user marker
      _allMarkers = Set.from(_markers); // Copy all other markers
      _allMarkers.add(myLocationMarker); // Add current user's marker
      
      // Update the circle
      _circles = {locationCircle};
    });
  }
  
  // Listen to users' location updates in Realtime Database
  void _listenToLocationUpdates() {
    try {
      _databaseRef.child('passengers').onValue.listen((event) {
        if (!mounted) return;
        DataSnapshot snapshot = event.snapshot;
        if (snapshot.value == null) {
          print("No data in passengers node");
          return;
        }
        Set<Marker> updatedMarkers = {};
        Map<dynamic, dynamic> values = snapshot.value as Map<dynamic, dynamic>;
        values.forEach((key, userData) {
          try {
            String userId = key.toString();
            bool isActive = userData['active'] ?? false;
            if (!isActive) return;
            bool isDriver = userData['isDriver'] ?? false;
            if (_currentUser != null && userId == _currentUser!.uid) return; // Don't show self
            // Filtering logic
            if (_isCurrentUserDriver == null) return; // Wait for user type
            if (_isCurrentUserDriver == true) {
              // Driver: show all except self - but only show passengers
              if (isDriver) return; // Don't show other drivers to drivers
            } else {
              // Passenger: show only drivers
              if (!isDriver) return;
            }
            if (userData.containsKey('location')) {
              Map<dynamic, dynamic>? locationData = userData['location'] as Map<dynamic, dynamic>?;
              if (locationData == null) return;
              double? lat = locationData['latitude'] as double?;
              double? lng = locationData['longitude'] as double?;
              if (lat != null && lng != null && (lat != 0 || lng != 0)) {
                String name = userData['name'] ?? 'Unknown';
                String message = userData['message'] ?? '';
                String phone = userData['phone'] ?? '';
                BitmapDescriptor icon = isDriver ?
                    (_busMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue)) :
                    (_passengerMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet));
                Marker marker = Marker(
                  markerId: MarkerId(userId),
                  position: LatLng(lat, lng),
                  icon: icon,
                  anchor: Offset(0.5, 0.5),
                  flat: true,
                  zIndex: 1.0,
                  consumeTapEvents: true,
                  infoWindow: InfoWindow(title: name, snippet: isDriver ? 'Bus Driver' : 'Passenger'),
                  onTap: () {
                    print('Marker tapped: $name, isDriver: $isDriver, currentUserDriver: $_isCurrentUserDriver');
                    HapticFeedback.selectionClick();
                    
                    // If passenger taps on driver marker, show driver info
                    if (_isCurrentUserDriver == false && isDriver) {
                      print('Showing driver info bottom sheet for $name');
                      _showDriverInfoBottomSheet(name, lat, lng, userId);
                    }
                    // If driver taps on passenger marker, show passenger info
                    else if (_isCurrentUserDriver == true && !isDriver) {
                      print('Showing passenger info bottom sheet for $name');
                      _showPassengerInfoBottomSheet(name, message, phone, lat, lng, userId);
                    }
                  },
                );
                updatedMarkers.add(marker);
              }
            }
          } catch (e) {
            print("Error processing user $key: $e");
          }
        });
        setState(() {
          _markers = updatedMarkers;
          // Update allMarkers to include both other users and current user
          _updateMyLocationMarker();
        });
      }, onError: (error) {
        print("Error listening to Realtime Database: $error");
        setState(() {
          _errorMessage = 'Error listening to user updates: $error';
        });
      });
    } catch (e) {
      print("Error in _listenToLocationUpdates: $e");
      setState(() {
        _errorMessage = 'Error listening for location updates: $e';
      });
    }
  }
  
  void _showDriverInfoBottomSheet(String name, double lat, double lng, String driverId) async {
    print('Bottom sheet called for $name at $lat, $lng');
    if (_currentPosition == null) {
      print('Current position is null');
      return;
    }
    double eta = _calculateETA(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
    setState(() {
      _selectedDriverName = name;
      _selectedDriverLat = lat;
      _selectedDriverLng = lng;
      _selectedDriverETA = eta;
      _selectedDriverId = driverId;
    });
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Image.asset('assets/images/bus_marker.png', width: 40, height: 40),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _selectedDriverName ?? '',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.directions_bus, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('Bus is $_selectedDriverETA min away', style: TextStyle(fontSize: 16)),
                ],
              ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(Icons.directions, color: Colors.white),
                label: Text('Show Route'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _drawRouteToDriver();
                  _centerMapOnDriver();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _centerMapOnDriver() {
    if (_selectedDriverLat != null && _selectedDriverLng != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_selectedDriverLat!, _selectedDriverLng!), 16.0),
      );
    }
  }

  double _calculateETA(double lat1, double lng1, double lat2, double lng2) {
    // Haversine formula for straight-line distance
    const double R = 6371; // Radius of Earth in km
    double dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    double dLon = (lng2 - lng1) * 3.141592653589793 / 180.0;
    double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.141592653589793 / 180.0) *
            cos(lat2 * 3.141592653589793 / 180.0) *
            (sin(dLon / 2) * sin(dLon / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = R * c; // in km
    double speed = 30; // Assume average bus speed 30km/h
    double eta = (distance / speed) * 60; // in minutes
    return eta < 1 ? 1 : eta.roundToDouble();
  }

  Future<void> _fetchCurrentUserType() async {
    if (_currentUser == null) return;
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _isCurrentUserDriver = userData['isDriver'] ?? false;
          _currentUserName = userData['fullName'] ?? '';
        });
        
        // After determining user role, update the marker
        if (_currentPosition != null) {
          _updateMyLocationMarker();
        }
      }
    } catch (e) {
      print('Error fetching user type: $e');
    }
  }

  // Helper to center map on current location
  void _centerOnCurrentLocation() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          15.0
        )
      );
      HapticFeedback.mediumImpact();
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _drawRouteToDriver() async {
    if (_currentPosition == null || _selectedDriverLat == null || _selectedDriverLng == null) return;

    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
     googleApiKey: GoogleMapApi().url,
      request: PolylineRequest(
        origin: PointLatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        destination: PointLatLng(_selectedDriverLat!, _selectedDriverLng!),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty) {
      _polylineCoordinates.clear();
      result.points.forEach((PointLatLng point) {
        _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });

      setState(() {
        _polylines = {
          Polyline(
            polylineId: PolylineId('route'),
            color: Colors.deepPurple,
            width: 6,
            points: _polylineCoordinates,
          ),
        };
      });
    }
  }

  void _showPassengerInfoBottomSheet(String name, String message, String phone, double lat, double lng, String passengerId) async {
    print('Bottom sheet called for passenger $name at $lat, $lng');
    if (_currentPosition == null) {
      print('Current position is null');
      return;
    }
    
    double distance = _calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
    double eta = _calculateETA(_currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
    
    setState(() {
      _selectedPassengerName = name;
      _selectedPassengerMessage = message;
      _selectedPassengerPhone = phone;
      _selectedPassengerLat = lat;
      _selectedPassengerLng = lng;
      _selectedPassengerId = passengerId;
    });
    
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Passenger name and image
              Row(
                children: [
                  Image.asset('assets/images/passenger_marker.png', width: 40, height: 40),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _selectedPassengerName ?? '',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 20),
              
              // Location information with icon
              Row(
                children: [
                  Icon(Icons.location_on, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Text('${distance.toStringAsFixed(1)} km away (about ${eta.round()} min)', 
                      style: TextStyle(fontSize: 16)),
                ],
              ),
              
              // Message section
              if (_selectedPassengerMessage != null && _selectedPassengerMessage!.isNotEmpty) 
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.message, color: Colors.grey[700]),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedPassengerMessage!,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Phone section
              if (_selectedPassengerPhone != null && _selectedPassengerPhone!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    children: [
                      Icon(Icons.phone, color: Colors.grey[700]),
                      SizedBox(width: 8),
                      Text(
                        _selectedPassengerPhone!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              
              SizedBox(height: 20),
              
              // Navigation button - centered at the bottom
              Center(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.directions, color: Colors.white),
                  label: Text('Navigate to Passenger'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _drawRouteToPassenger();
                    _centerMapOnPassenger();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _centerMapOnPassenger() {
    if (_selectedPassengerLat != null && _selectedPassengerLng != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(_selectedPassengerLat!, _selectedPassengerLng!), 16.0),
      );
    }
  }
  
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    // Haversine formula for straight-line distance
    const double R = 6371; // Radius of Earth in km
    double dLat = (lat2 - lat1) * 3.141592653589793 / 180.0;
    double dLon = (lng2 - lng1) * 3.141592653589793 / 180.0;
    double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.141592653589793 / 180.0) *
            cos(lat2 * 3.141592653589793 / 180.0) *
            (sin(dLon / 2) * sin(dLon / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = R * c; // in km
    return distance;
  }
  
  Future<void> _drawRouteToPassenger() async {
    if (_currentPosition == null || _selectedPassengerLat == null || _selectedPassengerLng == null) return;

    PolylinePoints polylinePoints = PolylinePoints();
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      googleApiKey: GoogleMapApi().url,
      request: PolylineRequest(
        origin: PointLatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        destination: PointLatLng(_selectedPassengerLat!, _selectedPassengerLng!),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty) {
      _polylineCoordinates.clear();
      result.points.forEach((PointLatLng point) {
        _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      });

      setState(() {
        _polylines = {
          Polyline(
            polylineId: PolylineId('route'),
            color: Colors.deepPurple,
            width: 6,
            points: _polylineCoordinates,
          ),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Map or Error message
        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
        else if (_errorMessage.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Map Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _initMap,
                    child: Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : _defaultLocation,
              zoom: 15.0,
            ),
            markers: _allMarkers, // Use allMarkers instead of markers
            circles: _circles, // Add the pulsing circle
            myLocationEnabled: false, // Disable default blue location marker
            myLocationButtonEnabled: false, // Disable default location button
            zoomControlsEnabled: false, // Disable zoom controls
            compassEnabled: true,
            mapToolbarEnabled: false,
            polylines: _polylines,
            onMapCreated: (GoogleMapController controller) {
              print("Map created successfully");
              _mapController = controller;
              if (_currentPosition != null) {
                print("Moving camera to initial position");
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    15.0
                  )
                );
              }
            },
          ),
        
        // Loading indicator
        if (_isLoading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
          
        // Legend
        Positioned(
          top: 20,
          right: 16,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/bus_marker.png',
                        width: 24,
                        height: 24,
                      ),
                      SizedBox(width: 8),
                      Text('Bus Driver', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/passenger_marker.png',
                        width: 24,
                        height: 24,
                      ),
                      SizedBox(width: 8),
                      Text('Other Passengers', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      // Custom animated indicator for current user's marker
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.deepPurple.withOpacity(0.2),
                          border: Border.all(
                            color: Colors.deepPurple.withOpacity(0.7),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Image.asset(
                            _isCurrentUserDriver == true
                                ? 'assets/images/bus_marker.png'
                                : 'assets/images/passenger_marker.png',
                            width: 16, 
                            height: 16,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('You', 
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepPurple
                        )
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Row of action buttons
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clear route button (only show if route is displayed)
              if (_polylines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: FloatingActionButton(
                    heroTag: "clearRoute",
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple,
                    mini: true,
                    child: Icon(Icons.clear),
                    onPressed: _clearRoute,
                  ),
                ),
              
              // Location button
              FloatingActionButton(
                heroTag: "location",
                backgroundColor: Colors.deepPurple,
                child: Icon(Icons.my_location),
                onPressed: _centerOnCurrentLocation,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  void _clearRoute() {
    setState(() {
      _polylines.clear();
      _polylineCoordinates.clear();
    });
    HapticFeedback.mediumImpact();
  }
} 