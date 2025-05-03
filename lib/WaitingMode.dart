import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class WaitingMode extends StatefulWidget {
  @override
  _WaitingModeState createState() => _WaitingModeState();
}

class _WaitingModeState extends State<WaitingMode> with TickerProviderStateMixin {
  // Firebase reference
  late final DatabaseReference _databaseRef;
  
  // Map controller
  GoogleMapController? _mapController;
  
  // Map related variables
  List<Marker> _markers = [];
  Map<String, dynamic> _passengerData = {};
  bool _isLoading = true;
  LatLng _initialPosition = LatLng(36.8065, 10.1815); // Default location: Tunis
  bool _showInfoPanel = false;
  String _selectedPassengerId = '';
  Timer? _refreshTimer;
  
  // Animation controllers
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  
  // Custom marker icons
  BitmapDescriptor? _activePassengerIcon;
  BitmapDescriptor? _inactivePassengerIcon;

  @override
  void initState() {
    super.initState();
    
    // Initialize database with correct URL
    final FirebaseDatabase database = FirebaseDatabase.instance;
    database.databaseURL = 'https://studenist-61999-default-rtdb.europe-west1.firebasedatabase.app';
    _databaseRef = database.ref().child('passengers');
    
    // Load custom markers
    _loadCustomMarkers();
    
    // Initialize animations
    _slideController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 1), // Start from bottom
      end: Offset.zero,     // End at original position
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    ));
    
    // Start loading passenger data
    _getPassengerLocations();
    
    // Set up a refresh timer (every 30 seconds)
    _refreshTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _refreshPassengerData();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _mapController?.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  void _loadCustomMarkers() async {
    _activePassengerIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(48, 48)),
      'assets/active_passenger.png', // Make sure to add this asset
    ).catchError((error) {
      print("Error loading active passenger marker: $error");
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    });
    
    _inactivePassengerIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(48, 48)),
      'assets/inactive_passenger.png', // Make sure to add this asset
    ).catchError((error) {
      print("Error loading inactive passenger marker: $error");
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    });
    
    // If assets aren't available, use default colored markers
    _activePassengerIcon ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    _inactivePassengerIcon ??= BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
  }

  void _getPassengerLocations() {
    setState(() {
      _isLoading = true;
    });
    
    _databaseRef.onValue.listen((event) {
      if (!mounted) return;
      
      setState(() {
        _markers.clear();
        _passengerData.clear();
        
        if (event.snapshot.value != null) {
          Map<dynamic, dynamic> values = event.snapshot.value as Map;
          
          // Find a good initial position (use first active passenger)
          bool foundInitialPosition = false;
          
          // Process all passengers
          values.forEach((key, value) {
            if (value is Map && value.containsKey('location')) {
              // Store passenger data for later use
              _passengerData[key] = value;
              
              // Extract location
              Map<dynamic, dynamic> locationData = value['location'] as Map;
              double? lat = locationData['latitude'] as double?;
              double? lng = locationData['longitude'] as double?;
              
              if (lat != null && lng != null) {
                // Use first active passenger location as initial map position
                if (!foundInitialPosition && value['active'] == true) {
                  _initialPosition = LatLng(lat, lng);
                  foundInitialPosition = true;
                  
                  // Update map camera if controller is available
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(_initialPosition, 15)
                  );
                }
                
                // Create marker
                _addMarker(key, value, LatLng(lat, lng));
              }
            }
          });
        }
        
        _isLoading = false;
      });
    }, onError: (error) {
      print("Error loading passenger data: $error");
      setState(() {
        _isLoading = false;
      });
    });
  }
  
  void _refreshPassengerData() {
    _databaseRef.get().then((snapshot) {
      if (!mounted) return;
      
      if (snapshot.value != null) {
        setState(() {
          _markers.clear();
          _passengerData.clear();
          
          Map<dynamic, dynamic> values = snapshot.value as Map;
          values.forEach((key, value) {
            if (value is Map && value.containsKey('location')) {
              // Store passenger data
              _passengerData[key] = value;
              
              // Extract location
              Map<dynamic, dynamic> locationData = value['location'] as Map;
              double? lat = locationData['latitude'] as double?;
              double? lng = locationData['longitude'] as double?;
              
              if (lat != null && lng != null) {
                // Create marker
                _addMarker(key, value, LatLng(lat, lng));
              }
            }
          });
        });
      }
    }).catchError((error) {
      print("Error refreshing passenger data: $error");
    });
  }
  
  void _addMarker(String passengerId, Map<dynamic, dynamic> passengerInfo, LatLng position) {
    // Get passenger name and status
    String name = passengerInfo['name'] ?? 'Unknown';
    bool isActive = passengerInfo['active'] ?? false;
    String message = passengerInfo['message'] ?? '';
    
    // Choose marker icon based on active status
    BitmapDescriptor markerIcon = isActive
        ? (_activePassengerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen))
        : (_inactivePassengerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange));
    
    // Create the marker
    Marker marker = Marker(
      markerId: MarkerId(passengerId),
      position: position,
      icon: markerIcon,
      infoWindow: InfoWindow(
        title: name,
        snippet: isActive ? (message.isNotEmpty ? message : 'Active') : 'Inactive',
      ),
      onTap: () {
        _showPassengerDetails(passengerId);
        HapticFeedback.selectionClick();
      },
    );
    
    _markers.add(marker);
  }
  
  void _showPassengerDetails(String passengerId) {
    if (_passengerData.containsKey(passengerId)) {
      setState(() {
        _selectedPassengerId = passengerId;
        _showInfoPanel = true;
      });
      
      // Show sliding panel animation
      _slideController.forward();
    }
  }
  
  void _hidePassengerDetails() {
    _slideController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showInfoPanel = false;
        });
      }
    });
  }
  
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    try {
      // Convert Firebase timestamp to DateTime
      DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
      return DateFormat('MMM d, h:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bus Tracking'),
        backgroundColor: Colors.deepPurple,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _refreshPassengerData();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Refreshing passenger data...'),
                  duration: Duration(seconds: 1),
                )
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map View
          _isLoading
              ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
              : GoogleMap(
        initialCameraPosition: CameraPosition(
                    target: _initialPosition,
                    zoom: 14,
        ),
        markers: Set<Marker>.of(_markers),
                  myLocationButtonEnabled: true,
                  myLocationEnabled: true,
                  compassEnabled: true,
                  mapToolbarEnabled: true,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                  },
                ),
          
          // Passenger info panel
          _showInfoPanel && _selectedPassengerId.isNotEmpty
              ? Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: _buildPassengerDetailsPanel(),
                  ),
                )
              : Container(),
              
          // Loading indicator
          _isLoading
              ? Container(
                  color: Colors.black54,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              : Container(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        child: Icon(Icons.people),
        onPressed: () {
          _showPassengersList();
          HapticFeedback.mediumImpact();
        },
      ),
    );
  }
  
  Widget _buildPassengerDetailsPanel() {
    if (!_passengerData.containsKey(_selectedPassengerId)) {
      return Container();
    }
    
    Map<dynamic, dynamic> passengerInfo = _passengerData[_selectedPassengerId] as Map;
    String name = passengerInfo['name'] ?? 'Unknown';
    bool isActive = passengerInfo['active'] ?? false;
    String message = passengerInfo['message'] ?? '';
    
    // Location data
    Map<dynamic, dynamic>? locationData = passengerInfo['location'] as Map?;
    double? lat = locationData?['latitude'] as double?;
    double? lng = locationData?['longitude'] as double?;
    dynamic locationUpdatedAt = locationData?['updated_at'];
    
    // Last online timestamp
    dynamic lastOnline = passengerInfo['last_online'];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: _hidePassengerDetails,
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? Colors.green.shade100 : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                color: isActive ? Colors.green.shade800 : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 16),
          if (message.isNotEmpty) ...[
            Text(
              'Message:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 4),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message,
                style: TextStyle(fontSize: 16),
              ),
            ),
            SizedBox(height: 16),
          ],
          Text(
            'Location:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 4),
          if (lat != null && lng != null)
            Text('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}'),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Location updated: ${_formatTimestamp(locationUpdatedAt)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                'Last online: ${_formatTimestamp(lastOnline)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: Icon(Icons.navigation),
                label: Text('Navigate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: lat != null && lng != null ? () {
                  _mapController?.animateCamera(
                    CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17),
                  );
                  HapticFeedback.mediumImpact();
                } : null,
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.message),
                label: Text('Contact'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () {
                  // Contact feature to be implemented
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Contact feature coming soon')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showPassengersList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          List<MapEntry<String, dynamic>> passengers = _passengerData.entries.toList();
          
          // Sort passengers: active first, then by name
          passengers.sort((a, b) {
            bool aActive = a.value['active'] ?? false;
            bool bActive = b.value['active'] ?? false;
            
            if (aActive && !bActive) return -1;
            if (!aActive && bActive) return 1;
            
            String aName = a.value['name'] ?? '';
            String bName = b.value['name'] ?? '';
            return aName.compareTo(bName);
          });
          
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(top: 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'All Passengers',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: passengers.isEmpty
                      ? Center(child: Text('No passengers found'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: passengers.length,
                          itemBuilder: (context, index) {
                            String id = passengers[index].key;
                            Map<dynamic, dynamic> info = passengers[index].value;
                            String name = info['name'] ?? 'Unknown';
                            bool isActive = info['active'] ?? false;
                            String message = info['message'] ?? '';
                            
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Card(
                                elevation: 2,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isActive ? Colors.green : Colors.orange,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(name),
                                  subtitle: Text(
                                    message.isNotEmpty ? message : (isActive ? 'Active' : 'Inactive'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(Icons.arrow_forward_ios, size: 16),
                                  onTap: () {
                                    Navigator.pop(context);
                                    
                                    // Locate on map
                                    Map<dynamic, dynamic>? locationData = info['location'] as Map?;
                                    double? lat = locationData?['latitude'] as double?;
                                    double? lng = locationData?['longitude'] as double?;
                                    
                                    if (lat != null && lng != null) {
                                      _mapController?.animateCamera(
                                        CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16),
                                      );
                                    }
                                    
                                    // Show details panel
                                    _showPassengerDetails(id);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
