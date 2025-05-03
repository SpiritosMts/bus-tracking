class UserModel {
  String? uid;
  String? email;
  String? fullName;
  bool? isDriver;
  String? phoneNumber;
  String? profileImageUrl;
  String? address;
  Map<String, dynamic>? location;
  String? userStatus; // active, inactive
  String? userType; // regular, premium, admin
  List<String>? favoriteRoutes;
  DateTime? accountCreatedAt;
  DateTime? lastLoginAt;
  Map<String, dynamic>? preferences; // app preferences
  
  UserModel({
    this.uid, 
    this.email, 
    this.fullName, 
    this.isDriver = false,
    this.phoneNumber,
    this.profileImageUrl,
    this.address,
    this.location,
    this.userStatus = 'active',
    this.userType = 'regular',
    this.favoriteRoutes,
    this.accountCreatedAt,
    this.lastLoginAt,
    this.preferences,
  });

  // receiving data from server
  factory UserModel.fromMap(map) {
    return UserModel(
      uid: map['uid'],
      email: map['email'],
      fullName: map['fullName'],
      isDriver: map['isDriver'] ?? false,
      phoneNumber: map['phoneNumber'],
      profileImageUrl: map['profileImageUrl'],
      address: map['address'],
      location: map['location'],
      userStatus: map['userStatus'] ?? 'active',
      userType: map['userType'] ?? 'regular',
      favoriteRoutes: map['favoriteRoutes'] != null 
          ? List<String>.from(map['favoriteRoutes']) 
          : null,
      accountCreatedAt: map['accountCreatedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['accountCreatedAt']) 
          : null,
      lastLoginAt: map['lastLoginAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['lastLoginAt']) 
          : null,
      preferences: map['preferences'],
    );
  }

  // sending data to our server
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'isDriver': isDriver,
      'phoneNumber': phoneNumber,
      'profileImageUrl': profileImageUrl,
      'address': address,
      'location': location,
      'userStatus': userStatus,
      'userType': userType,
      'favoriteRoutes': favoriteRoutes,
      'accountCreatedAt': accountCreatedAt?.millisecondsSinceEpoch,
      'lastLoginAt': lastLoginAt?.millisecondsSinceEpoch,
      'preferences': preferences,
    };
  }
}
