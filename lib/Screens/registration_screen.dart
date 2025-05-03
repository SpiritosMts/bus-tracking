import 'package:cloud_firestore/cloud_firestore.dart' hide Query;
import 'package:bus_tracking_new/model/routes.dart';
import 'package:bus_tracking_new/model/user_model.dart';
import 'package:bus_tracking_new/screens/welcome_screen.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:bus_tracking_new/config/app_config.dart';
import 'login_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({Key? key}) : super(key: key);

  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _auth = FirebaseAuth.instance;
  FirebaseDatabase database = FirebaseDatabase.instance;

  // string for displaying the error Message
  String? errorMessage;

  bool _obscureText = true;
  bool __obscureText = true;
  
  // User type selection
  bool _isDriver = false;

  var _fullname = '';
  var _email = '';

  // our form key
  final _formKey = GlobalKey<FormState>();

  // editing Controller
  final fullnameEditingController = new TextEditingController();
  final emailEditingController = new TextEditingController();
  final phoneNumberEditingController = new TextEditingController();
  final passwordEditingController = new TextEditingController();
  final confirmPasswordEditingController = new TextEditingController();

  final Stream<QuerySnapshot> users =
      FirebaseFirestore.instance.collection('users').snapshots();

  @override
  Widget build(BuildContext context) {
    // User type selection field
    final userTypeField = Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(15),
      ),
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                "User Type:",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                decoration: BoxDecoration(
                  color: _isDriver ? Colors.blue.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isDriver ? "Driver" : "Passenger",
                  style: TextStyle(
                    color: _isDriver ? Colors.blue.shade700 : Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Passenger radio
              Radio<bool>(
                value: false,
                groupValue: _isDriver,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  setState(() {
                    _isDriver = value!;
                  });
                },
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isDriver = false;
                  });
                },
                child: Text(
                  "Passenger",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(width: 30),
              // Driver radio
              Radio<bool>(
                value: true,
                groupValue: _isDriver,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  setState(() {
                    _isDriver = value!;
                  });
                },
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isDriver = true;
                  });
                },
                child: Text(
                  "Driver",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isDriver ? Icons.directions_bus : Icons.person,
                  color: Colors.deepPurple,
                  size: 18,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isDriver
                        ? "Drivers can share their bus location and see passenger requests."
                        : "Passengers can share their location and view bus positions on the map.",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    
    //phone number field
    final phoneNumberField = TextFormField(
        autofocus: false,
        controller: phoneNumberEditingController,
        keyboardType: TextInputType.phone,
        validator: (value) {
          if (value!.isEmpty) {
            return ("Phone number is required");
          }
          // You can add more validation for phone number format if needed
          return null;
        },
        onSaved: (value) {
          phoneNumberEditingController.text = value!;
        },
        textInputAction: TextInputAction.next,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.phone, color: Colors.grey.shade700),
          contentPadding: EdgeInsets.fromLTRB(20, 15, 20, 15),
          hintText: "Phone Number",
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
        ));

    //first name field
    final fullnameField = TextFormField(
        autofocus: false,
        controller: fullnameEditingController,
        keyboardType: TextInputType.name,
        validator: (value) {
          RegExp regex = new RegExp(r'^.{3,}$');
          if (value!.isEmpty) {
            return ("Full Name cannot be Empty");
          }
          if (!regex.hasMatch(value)) {
            return ("Enter Valid name(Min. 3 Character)");
          }
          return null;
        },
        onSaved: (value) {
          fullnameEditingController.text = value!;
        },
        textInputAction: TextInputAction.next,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.account_circle, color: Colors.grey.shade700),
          contentPadding: EdgeInsets.fromLTRB(20, 15, 20, 15),
          hintText: "Full Name",
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
        ));

    //email field
    final emailField = TextFormField(
        autofocus: false,
        controller: emailEditingController,
        keyboardType: TextInputType.emailAddress,
        validator: (value) {
          if (value!.isEmpty) {
            return ("Please Enter Your Email");
          }
          // reg expression for email validation
          if (!RegExp("^[a-zA-Z0-9+_.-]+@[a-zA-Z0-9.-]+.[a-z]")
              .hasMatch(value)) {
            return ("Please Enter a valid email");
          }
          return null;
        },
        onSaved: (value) {
          fullnameEditingController.text = value!;
        },
        textInputAction: TextInputAction.next,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.mail, color: Colors.grey.shade700),
          contentPadding: EdgeInsets.fromLTRB(20, 15, 20, 15),
          hintText: "Email",
          hintStyle: TextStyle(color: Colors.grey.shade500),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
        ));

    //password field
    final passwordField = TextFormField(
        autofocus: false,
        controller: passwordEditingController,
        obscureText: _obscureText,
        validator: (value) {
          RegExp regex = new RegExp(r'^.{6,}$');
          if (value!.isEmpty) {
            return ("Password is required");
          }
          if (!regex.hasMatch(value)) {
            return ("Enter Valid Password(Min. 6 Character)");
          }
          return null;
        },
        onSaved: (value) {
          fullnameEditingController.text = value!;
        },
        textInputAction: TextInputAction.next,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.vpn_key, color: Colors.grey.shade700),
          contentPadding: EdgeInsets.fromLTRB(20, 15, 20, 15),
          hintText: "Password",
          hintStyle: TextStyle(color: Colors.grey.shade500),
          suffixIcon: GestureDetector(
            onTap: () {
              setState(() {
                _obscureText = !_obscureText;
              });
            },
            child: Icon(
              _obscureText ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey.shade600,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
        ));

    //confirm password field
    final confirmPasswordField = TextFormField(
        autofocus: false,
        controller: confirmPasswordEditingController,
        obscureText: __obscureText,
        validator: (value) {
          if (value!.isEmpty) {
            return ("Password is required");
          }
          if (confirmPasswordEditingController.text !=
              passwordEditingController.text) {
            return "Password don't match";
          }
          return null;
        },
        onSaved: (value) {
          confirmPasswordEditingController.text = value!;
        },
        textInputAction: TextInputAction.done,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.vpn_key, color: Colors.grey.shade700),
          contentPadding: EdgeInsets.fromLTRB(20, 15, 20, 15),
          hintText: "Confirm Password",
          hintStyle: TextStyle(color: Colors.grey.shade500),
          suffixIcon: GestureDetector(
            onTap: () {
              setState(() {
                __obscureText = !__obscureText;
              });
            },
            child: Icon(
              __obscureText ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey.shade600,
            ),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.deepPurple, width: 1.5),
          ),
        ));

    //signup button
    final signUpButton = Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(30),
      color: Colors.deepPurple,
      child: MaterialButton(
          padding: EdgeInsets.fromLTRB(20, 15, 20, 15),
          minWidth: MediaQuery.of(context).size.width,
          onPressed: () {
            signUp(emailEditingController.text, passwordEditingController.text);
          },
          child: Text(
            "SignUp",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
          )),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.deepPurple,
            size: 28,
          ),
          onPressed: () {
            // passing this to our root
            Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => welcomeScreen()));
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Lottie.asset(
                      'assets/images/register-anim.json',
                      width: 180,
                      height: 180,
                    ),
                    SizedBox(
                      height: 15,
                    ),
                    Text(
                      'Registeration',
                      style: GoogleFonts.poppins(
                          color: Colors.black,
                          fontSize: 34,
                          fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 45),
                    userTypeField,
                    SizedBox(height: 20),
                    fullnameField,
                    SizedBox(height: 20),
                    phoneNumberField,
                    SizedBox(height: 20),
                    emailField,
                    SizedBox(height: 20),
                    passwordField,
                    SizedBox(height: 20),
                    confirmPasswordField,
                    SizedBox(height: 20),
                    signUpButton,
                    SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          "Already registered? ",
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => LoginScreen()));
                          },
                          child: Text(
                            "Login",
                            style: TextStyle(
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void signUp(String email, String password) async {
    if (_formKey.currentState!.validate()) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return Center(
              child: CircularProgressIndicator(
                color: Colors.deepPurple,
              ),
            );
          },
        );

        // Create user with email and password
        UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: email, 
          password: password
        );
        
        // Post details to Firestore
        await postDetailsToFirestore();
        
        // Send email verification if OTP verification is enabled
        if (AppConfig.enableOtpVerification) {
          await _auth.currentUser!.sendEmailVerification();
          // Close loading dialog
          Navigator.of(context).pop();
          
          // Navigate to login page with verification message
          Fluttertoast.showToast(msg: "Account created! Please verify your email");
          Navigator.of(context).pushReplacementNamed(loginRoute);
        } else {
          // Skip email verification if OTP verification is disabled
          // Close loading dialog
          Navigator.of(context).pop();
          
          // Navigate directly to home screen
          Fluttertoast.showToast(msg: "Registration Successful!");
          Navigator.of(context).pushReplacementNamed(homeRoute);
        }
        
      } on FirebaseAuthException catch (error) {
        // Close loading dialog if it's open
        Navigator.of(context).pop();
        
        switch (error.code) {
          case "invalid-email":
            errorMessage = "Your email address appears to be malformed.";
            break;
          case "wrong-password":
            errorMessage = "Your password is wrong.";
            break;
          case "user-not-found":
            errorMessage = "User with this email doesn't exist.";
            break;
          case "user-disabled":
            errorMessage = "User with this email has been disabled.";
            break;
          case "too-many-requests":
            errorMessage = "Too many requests";
            break;
          case "operation-not-allowed":
            errorMessage = "Signing in with Email and Password is not enabled.";
            break;
          case "email-already-in-use":
            errorMessage = "Email is already in use by another account.";
            break;
          default:
            errorMessage = "An undefined Error happened.";
        }
        Fluttertoast.showToast(msg: errorMessage!);
        print(error.code);
      } catch (e) {
        // Close loading dialog if it's open
        Navigator.of(context).pop();
        
        Fluttertoast.showToast(msg: "An error occurred: ${e.toString()}");
        print(e);
      }
    }
  }

  void afterThen() {
    // This function is no longer needed
  }

  Future<void> postDetailsToFirestore() async {
    FirebaseFirestore firebaseFirestore = FirebaseFirestore.instance;
    User? user = _auth.currentUser;

    UserModel userModel = UserModel();

    // writing all the values
    userModel.email = user!.email;
    userModel.uid = user.uid;
    userModel.fullName = fullnameEditingController.text;
    userModel.isDriver = _isDriver;
    userModel.phoneNumber = phoneNumberEditingController.text;
    userModel.accountCreatedAt = DateTime.now();
    userModel.lastLoginAt = DateTime.now();
    userModel.userStatus = 'active';
    
    // Initialize location map
    userModel.location = {
      'latitude': 0.0,
      'longitude': 0.0,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch
    };
    
    // Set default preferences
    userModel.preferences = {
      'notifications': true,
      'darkMode': false,
      'language': 'en'
    };

    // If user is a driver, add driver-specific fields
    if (_isDriver) {
      userModel.userType = 'driver';
      // Additional driver properties can be added directly to the user model
    } else {
      userModel.userType = 'passenger';
    }

    // Save everything to a single collection
    await firebaseFirestore
        .collection("users")
        .doc(user.uid)
        .set(userModel.toMap());
  }
}
