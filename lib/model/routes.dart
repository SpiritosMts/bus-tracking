import 'package:bus_tracking_new/screens/home_screen.dart';
import 'package:bus_tracking_new/screens/login_screen.dart';
import 'package:bus_tracking_new/screens/splash_screen.dart';
import 'package:bus_tracking_new/screens/welcome_screen.dart';

const String welcomeRoute = "/welcome";
const String homeRoute = "/home";
const String loginRoute = "/login";
const String splashRoute = "/splash";

final routes = {
  welcomeRoute: (context) => welcomeScreen(),
  homeRoute: (context) => HomeScreen(),
  loginRoute: (context) => LoginScreen(),
  splashRoute: (context) => splashScreen()
};
