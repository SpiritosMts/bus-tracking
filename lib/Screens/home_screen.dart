import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import '../PassengerMode.dart';       // Import for PassengerMode
import '../Screens/map_screen.dart';  // Import for MapScreen
import '../Screens/settings_screen.dart'; // Import for SettingsScreen

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Index for the current selected tab
  int _selectedIndex = 0;
  
  // List of screens to display
  late List<Widget> _screens;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize the screens list
    _screens = [
      MapScreen(),
      PassengerMode(),
      SettingsScreen(),
    ];
  }

  Future<bool?> _onBackPressed() async {
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Do you want to exit?'),
            actions: <Widget>[
              TextButton(
                child: Text('No'),
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
              ),
              TextButton(
                child: Text('Yes'),
                onPressed: () {
                  Navigator.of(context).pop(true);
                  SystemNavigator.pop();
                },
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        bool? result = await _onBackPressed();
        if (result == null) {
          result = false;
        }
        return result;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            _selectedIndex == 0 ? "Bus Tracker" : 
            _selectedIndex == 1 ? "Be Seen" : "Settings",
            style: TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.notifications, color: Colors.deepPurple),
              onPressed: () {
                // Do nothing for now
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(3.0), // thickness of the underline
            child: Container(
              color: Colors.deepPurple,
              height: 3.0,
            ),
          ),
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: _screens,
        ),
        bottomNavigationBar: CurvedNavigationBar(
          index: _selectedIndex,
          backgroundColor: Colors.transparent,
          color: Colors.deepPurple,
          animationDuration: const Duration(milliseconds: 300),
          height: 60,
          items: [
            Icon(Icons.map, color: Colors.white),
            Icon(Icons.directions_bus, color: Colors.white),
            Icon(Icons.settings, color: Colors.white),
          ],
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      )
    );
  }
}
