import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:bus_tracking_new/model/user_model.dart';
import 'package:bus_tracking_new/model/routes.dart';
import 'package:bus_tracking_new/config/app_config.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? get _currentUser => _auth.currentUser;
  
  UserModel _userModel = UserModel();
  bool _isLoading = true;
  bool _isDarkMode = false;
  
  // Controllers for editing user info
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
  
  // Load user data from Firestore
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (_currentUser != null) {
        DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
          
        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          setState(() {
            _userModel = UserModel.fromMap(data);
            _nameController.text = _userModel.fullName ?? '';
            _phoneController.text = _userModel.phoneNumber ?? '';
            
            // Load dark mode preference if exists
            if (_userModel.preferences != null && 
                _userModel.preferences!.containsKey('darkMode')) {
              _isDarkMode = _userModel.preferences!['darkMode'] as bool;
            }
          });
        }
      }
    } catch (e) {
      print("Error loading user data: $e");
      Fluttertoast.showToast(msg: "Failed to load profile data");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Update dark mode preference
  Future<void> _updateDarkMode(bool value) async {
    setState(() {
      _isDarkMode = value;
    });
    
    try {
      if (_currentUser != null) {
        // Initialize preferences map if it doesn't exist
        Map<String, dynamic> preferences = _userModel.preferences ?? {};
        preferences['darkMode'] = value;
        
        await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .update({
            'preferences': preferences
          });
          
        Fluttertoast.showToast(
          msg: "Theme updated",
          toastLength: Toast.LENGTH_SHORT
        );
      }
    } catch (e) {
      print("Error updating dark mode: $e");
      Fluttertoast.showToast(msg: "Failed to update theme");
      // Revert UI state if update failed
      setState(() {
        _isDarkMode = !value;
      });
    }
  }
  
  // Show dialog to edit profile
  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateProfile();
            },
            child: Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
            ),
          ),
        ],
      ),
    );
  }
  
  // Update profile info in Firestore
  Future<void> _updateProfile() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (_currentUser != null) {
        String newName = _nameController.text.trim();
        String newPhone = _phoneController.text.trim();
        
        if (newName.isEmpty) {
          Fluttertoast.showToast(msg: "Name cannot be empty");
          return;
        }
        
        await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .update({
            'fullName': newName,
            'phoneNumber': newPhone,
          });
          
        // Update local model
        setState(() {
          _userModel.fullName = newName;
          _userModel.phoneNumber = newPhone;
        });
        
        Fluttertoast.showToast(msg: "Profile updated successfully");
      }
    } catch (e) {
      print("Error updating profile: $e");
      Fluttertoast.showToast(msg: "Failed to update profile");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Show confirmation dialog for account deletion
  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Account'),
        content: Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently lost.',
          style: TextStyle(
            color: Colors.red.shade800,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
  }
  
  // Delete user account and data
  Future<void> _deleteAccount() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (_currentUser != null) {
        // Delete user data from Firestore
        await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .delete();
          
        // Delete the user authentication account
        await _currentUser!.delete();
        
        Fluttertoast.showToast(msg: "Account deleted successfully");
        
        // Navigate to login screen
        Navigator.of(context).pushReplacementNamed(loginRoute);
      }
    } catch (e) {
      print("Error deleting account: $e");
      Fluttertoast.showToast(
        msg: "Failed to delete account. You may need to re-authenticate.",
        toastLength: Toast.LENGTH_LONG,
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Sign out the user
  Future<void> _signOut() async {
    try {
      // Update user status to inactive before signing out
      if (_currentUser != null) {
        await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .update({
            'userStatus': 'inactive'
          });
        print("User status set to inactive before logout");
      }
      
      await _auth.signOut();
      Navigator.of(context).pushReplacementNamed(loginRoute);
    } catch (e) {
      print("Error signing out: $e");
      Fluttertoast.showToast(msg: "Failed to sign out");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
        ? Center(child: CircularProgressIndicator(color: Colors.deepPurple))
        : SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile section
                Card(
                  elevation: 4,
                  margin: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.deepPurple.shade100,
                          child: Icon(
                            _userModel.isDriver == true
                                ? Icons.directions_bus
                                : Icons.person,
                            size: 50,
                            color: Colors.deepPurple,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          _userModel.fullName ?? 'User',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _userModel.email ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        SizedBox(height: 12),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _userModel.isDriver == true
                                ? 'Bus Driver'
                                : 'Passenger',
                            style: TextStyle(
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: Icon(Icons.edit, size: 18),
                          label: Text('Edit Profile'),
                          onPressed: _showEditProfileDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 20),
                Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                
                // Settings list
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Dark mode toggle
                      SwitchListTile(
                        title: Text('Dark Mode'),
                        subtitle: Text('Enable dark theme'),
                        secondary: Icon(Icons.dark_mode, color: Colors.deepPurple),
                        value: _isDarkMode,
                        onChanged: _updateDarkMode,
                        activeColor: Colors.deepPurple,
                      ),
                      Divider(),
                      
                      // About entry
                      ListTile(
                        leading: Icon(Icons.info_outline, color: Colors.deepPurple),
                        title: Text('About'),
                        subtitle: Text('Version ${AppConfig.appVersion}'),
                        onTap: () {
                       
                        },
                      ),
                      Divider(),
                      
                      // Logout option
                      ListTile(
                        leading: Icon(Icons.logout, color: Colors.deepPurple),
                        title: Text('Logout'),
                        subtitle: Text('Sign out of your account'),
                        onTap: _signOut,
                      ),
                      Divider(),
                      
                      // Delete account option
                      ListTile(
                        leading: Icon(Icons.delete_forever, color: Colors.red),
                        title: Text(
                          'Delete Account',
                          style: TextStyle(color: Colors.red),
                        ),
                        subtitle: Text('Permanently remove your account and data'),
                        onTap: _showDeleteAccountDialog,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
} 