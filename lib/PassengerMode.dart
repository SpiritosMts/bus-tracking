import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class PassengerMode extends StatefulWidget {
  @override
  _PassengerModeState createState() => _PassengerModeState();
}

class _PassengerModeState extends State<PassengerMode> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Reference to the passengers node in Firebase Realtime Database
  late final DatabaseReference _passengersRef;
  
  // Reference to Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Get current user
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? get _currentUser => _auth.currentUser;
  
  Position? _currentPosition;
  bool _isLoading = true;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _locationUpdateTimer;
  bool _locationUpdatesActive = false;
  double _lastLat = 0;
  double _lastLng = 0;
  DateTime _lastUpdate = DateTime.now();
  
  // Text input controller and variables
  final TextEditingController _messageController = TextEditingController();
  String _passengerMessage = '';
  String _passengerName = '';
  bool _isEditingMessage = false;
  
  // Animation controllers
  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Register for lifecycle events
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize database with explicit URL
    final FirebaseDatabase database = FirebaseDatabase.instance;
    // Use your actual project ID in the database URL
    database.databaseURL = 'https://studenist-61999-default-rtdb.europe-west1.firebasedatabase.app';
    _passengersRef = database.ref().child('passengers');
    
    // Initialize animations
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut)
    );
    
    _loadUserDataFromFirestore();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    // Clean up resources when the screen is closed
    _stopLocationUpdates();
    _positionStreamSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    _messageController.dispose();
    _pulseAnimationController.dispose();
    
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
  }
  
  // Load user data from Firestore
  void _loadUserDataFromFirestore() async {
    if (_currentUser != null) {
      try {
        // First try to load from Firestore
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
        
        if (userDoc.exists) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _passengerName = userData['fullName'] ?? 'Anonymous';
            print("## Loaded name from Firestore: $_passengerName");
          });
          
          // Also check for existing message in Realtime Database
          _passengersRef.child(_currentUser!.uid).once().then((DatabaseEvent event) {
            final data = event.snapshot.value as Map<dynamic, dynamic>?;
            if (data != null) {
              setState(() {
                _passengerMessage = data['message'] ?? '';
              });
              print("## Loaded existing message from Realtime DB: $_passengerMessage");
            }
          }).catchError((error) {
            print("## Failed to load message from Realtime DB: $error");
          });
        } else {
          print("## User document does not exist in Firestore");
          setState(() {
            _passengerName = _currentUser?.displayName ?? 'Anonymous';
          });
        }
      } catch (e) {
        print("## Error loading user data from Firestore: $e");
        setState(() {
          _passengerName = _currentUser?.displayName ?? 'Anonymous';
        });
      }
    } else {
      print("## No user is signed in");
      // Show a message to the user
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please sign in to use Passenger Mode')),
        );
      });
    }
  }

  void _getCurrentLocation() async {
    try {
      // Request location permissions if not granted
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permissions are denied, handle this case
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Location permissions are denied')),
          );
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        // Permissions are permanently denied, handle this case
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location permissions are permanently denied')),
        );
        return;
      }
      
      // Get the initial position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
      
      setState(() {
        _currentPosition = position;
        _lastLat = position.latitude;
        _lastLng = position.longitude;
        _isLoading = false;
      });
      
      // Removed the initial location upload
      // The location will only be uploaded when the user presses "Start Sharing Location"
    } catch (e) {
      print("## Error getting location: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startLocationUpdates() {
    if (_locationUpdatesActive) return;
    
    _locationUpdatesActive = true;
    
    // Update user status to active in Firestore
    if (_currentUser != null) {
      _firestore.collection('users').doc(_currentUser!.uid).update({
        'userStatus': 'active'
      }).then((_) {
        print("## User status set to active in Firestore");
      }).catchError((error) {
        print("## Error updating status in Firestore: $error");
      });
    }
    
    // Play animation when active
    _pulseAnimationController.repeat(reverse: true);

    // Upload current location immediately when user starts sharing
    if (_currentPosition != null) {
      _uploadLocationToDatabase(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    // Update location every 45 seconds using a timer (less frequent updates)
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 45), (timer) {
      _updateLocation();
    });

    // Set up a location stream for more intelligence-based updates when movement is detected
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // Update if moved 20 meters (increased from 10)
    );
    
    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      // Check if we need to update (significant movement or time passed)
      bool shouldUpdate = _shouldUpdateLocation(position);
      
      if (shouldUpdate) {
        setState(() {
          _currentPosition = position;
          _lastLat = position.latitude;
          _lastLng = position.longitude;
          _lastUpdate = DateTime.now();
        });
        _uploadLocationToDatabase(position.latitude, position.longitude);
      } else {
        setState(() {
          _currentPosition = position; // Update UI without sending to database
        });
      }
    });
  }
  
  // Determine if we should update location based on movement and time
  bool _shouldUpdateLocation(Position position) {
    // Calculate distance moved
    double distMoved = Geolocator.distanceBetween(
      _lastLat, _lastLng, 
      position.latitude, position.longitude
    );
    
    // Time since last update
    Duration timeSinceUpdate = DateTime.now().difference(_lastUpdate);
    
    // Update if moved more than 25 meters or if 2 minutes passed
    return distMoved > 25 || timeSinceUpdate.inSeconds > 120;
  }

  void _stopLocationUpdates() {
    try {
      _locationUpdatesActive = false;
      _positionStreamSubscription?.cancel();
      _locationUpdateTimer?.cancel();
      
      if (_pulseAnimationController.isAnimating) {
        _pulseAnimationController.stop();
      }
      
      // Update status to offline in both Realtime Database and Firestore
      if (_currentUser != null) {
        // Update Realtime Database
        _passengersRef.child(_currentUser!.uid).update({
          'active': false,
          'last_online': ServerValue.timestamp,
        }).then((_) {
          print("## Updated user to inactive status in Realtime Database");
        }).catchError((error) {
          print("## Error updating status in Realtime Database: $error");
        });
        
        // Update Firestore
        _firestore.collection('users').doc(_currentUser!.uid).update({
          'userStatus': 'inactive'
        }).then((_) {
          print("## Updated user to inactive status in Firestore");
        }).catchError((error) {
          print("## Error updating status in Firestore: $error");
        });
      }
    } catch (e) {
      print("## Error stopping location updates: $e");
    }
  }

  void _updateLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      
      // Check if we need to update (significant movement or time passed)
      bool shouldUpdate = _shouldUpdateLocation(position);
      
      if (shouldUpdate) {
        setState(() {
          _currentPosition = position;
          _lastLat = position.latitude;
          _lastLng = position.longitude;
          _lastUpdate = DateTime.now();
        });
        
        _uploadLocationToDatabase(position.latitude, position.longitude);
      } else {
        setState(() {
          _currentPosition = position; // Update UI without sending to database
        });
      }
    } catch (e) {
      print("## Error updating location: $e");
    }
  }

  void _uploadLocationToDatabase(double latitude, double longitude) {
    try {
      // Check if user is logged in, if not, create a temporary ID
      if (_currentUser == null) {
        print("## Error: No user is logged in. Cannot upload location data.");
        Fluttertoast.showToast(
          msg: "Please sign in to share your location",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
        return;
      }
      
      String userId = _currentUser!.uid;
      
      // Prepare passenger data
      Map<String, dynamic> passengerData = {
        'location': {
      'latitude': latitude,
      'longitude': longitude,
          'updated_at': ServerValue.timestamp,
        },
        'name': _passengerName,
        'message': _passengerMessage,
        'active': true,
        'last_online': ServerValue.timestamp,
      };
      
      // Print debugging information
      print("## Uploading passenger data for user: $userId");
      print("## Data: $passengerData");
      print("## Database reference path: ${_passengersRef.child(userId).path}");
      
      // Update the database - first try a direct set for the first time
      _passengersRef.child(userId).set(passengerData).then((_) {
        print("## Successfully set passenger data for user: $userId");
        
        // Verify data was written by reading it back
        _passengersRef.child(userId).once().then((DatabaseEvent event) {
          if (event.snapshot.value != null) {
            print("## Verification read success: Data exists in database");
          } else {
            print("## Verification read concern: Data appears to be null after write");
          }
        }).catchError((error) {
          print("## Verification read error: $error");
        });
        
        // Show a success toast if first time writing
        if (!_locationUpdatesActive) {
          Fluttertoast.showToast(
            msg: "Location shared successfully",
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
          );
        }
      }).catchError((error) {
        print("## Error setting passenger data: ${error.toString()}");
        
        if (error.toString().contains('permission_denied')) {
          print("## PERMISSION DENIED: Check your Firebase Database Rules");
          
          // Show a toast about permissions
          Fluttertoast.showToast(
            msg: "Database permission error. Check app settings.",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.CENTER,
          );
          
          // Show the fix database rules button
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Database permission error. Tap "Set Database Rules to Public" button below.'),
                duration: Duration(seconds: 10),
              ),
            );
          });
          return;
        }
        
        // Try update instead of set if set fails
        print("## Attempting update operation instead");
        _passengersRef.child(userId).update(passengerData).then((_) {
          print("## Successfully updated passenger data for user: $userId");
        }).catchError((error) {
          print("## Error updating passenger data: ${error.toString()}");
          Fluttertoast.showToast(
            msg: "Failed to share location: ${error.toString().substring(0, 50)}...",
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
          );
        });
      });
    } catch (e) {
      print("## Exception in _uploadLocationToDatabase: ${e.toString()}");
    }
  }

  void _updateMessage(String message) {
    setState(() {
      _passengerMessage = message;
      _isEditingMessage = false;
    });
    
    // Only upload updated message if location sharing is active
    if (_locationUpdatesActive && _currentPosition != null) {
      _uploadLocationToDatabase(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    
    // Add haptic feedback
    HapticFeedback.lightImpact();
  }
  
  Widget _buildNameDisplay() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.person, color: Colors.deepPurple),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              _passengerName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: _isEditingMessage ? 8 : 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: _isEditingMessage 
        ? Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: "Enter your message",
                    border: InputBorder.none,
                  ),
                  maxLines: 1,
                  onSubmitted: (value) {
                    _updateMessage(value);
                  },
                  autofocus: true,
                ),
              ),
              IconButton(
                icon: Icon(Icons.check, color: Colors.deepPurple),
                onPressed: () {
                  _updateMessage(_messageController.text);
                }
              ),
            ],
          )
        : Row(
            children: [
              Icon(Icons.message, color: Colors.deepPurple),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  _passengerMessage.isEmpty 
                    ? "Tap to add a message" 
                    : _passengerMessage,
                  style: TextStyle(
                    color: _passengerMessage.isEmpty ? Colors.grey : Colors.black,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.edit, color: Colors.deepPurple),
                onPressed: () {
                  _messageController.text = _passengerMessage;
                  setState(() {
                    _isEditingMessage = true;
                  });
                  // Add haptic feedback
                  HapticFeedback.selectionClick();
                }
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
        : _currentPosition == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_off, size: 50, color: Colors.grey),
                SizedBox(height: 20),
                Text('Unable to get location.', style: TextStyle(fontSize: 16)),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _getCurrentLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: Text('Try Again', style: TextStyle(color: Colors.white)),
                )
              ],
            )
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.deepPurple.shade200, Colors.white],
                ),
              ),
              child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
                    SizedBox(height: 30),
                    // Animated Location Icon
                    _locationUpdatesActive
                      ? AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  size: 50,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            );
                          },
                        )
                      : Icon(
                          Icons.location_off,
                          size: 50,
                          color: Colors.grey,
                        ),
                    SizedBox(height: 20),
                    Text(
                      'Your Current Location:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      margin: EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        children: [
                          Text('Latitude: ${_currentPosition!.latitude.toStringAsFixed(6)}', 
                              style: TextStyle(fontSize: 16)),
                          SizedBox(height: 4),
                          Text('Longitude: ${_currentPosition!.longitude.toStringAsFixed(6)}', 
                              style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                    SizedBox(height: 30),
                    
                    // // Name display section - shows name loaded from Firestore
                    // Text(
                    //   'Passenger Name:',
                    //   style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    // ),
                    // SizedBox(height: 10),
                    // _buildNameDisplay(),
                    SizedBox(height: 20),
                    
                    // Message input section
                    Text(
                      'Share a message with your location:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    _buildMessageInput(),
                    SizedBox(height: 30),
                    
                    AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _locationUpdatesActive ? Colors.green.shade100 : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        _locationUpdatesActive
                          ? 'Location sharing is active'
                          : 'Location sharing is paused',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _locationUpdatesActive ? Colors.green.shade800 : Colors.orange.shade800,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    if (!_locationUpdatesActive)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Your location will only be shared with buses after you press the "Start Sharing Location" button',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    SizedBox(height: 30),
                    ElevatedButton.icon(
                      icon: Icon(
                        _locationUpdatesActive ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      label: Text(
                        _locationUpdatesActive ? 'Stop Sharing Location' : 'Start Sharing Location',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _locationUpdatesActive ? Colors.orange : Colors.green,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          if (_locationUpdatesActive) {
                            _stopLocationUpdates();
                          } else {
                            _startLocationUpdates();
                          }
                        });
                      },
                    ),
                    SizedBox(height: 30),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If app is paused, inactive, or detached, stop location updates and set user to inactive
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive || 
        state == AppLifecycleState.detached) {
      if (_locationUpdatesActive) {
        _stopLocationUpdates();
      }
    }
    // If app is resumed and was previously tracking, restart location updates
    else if (state == AppLifecycleState.resumed && _locationUpdatesActive) {
      _startLocationUpdates();
    }
  }
}
