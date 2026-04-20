import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'email_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Firebase Realtime DB REST API Base URL
  final String _dbBaseUrl = 'https://crowdsense-db-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Logs a user in using either their Email or their Username.
  /// Returns a Map payload containing the raw Firebase `User` object and the `userData` mapping.
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    
    String loginEmail = identifier.trim();
    
    if (!loginEmail.contains('@')) {
      // It's a username! We must securely look up the associated email in the database via REST
      try {
        final queryUrl = Uri.parse('$_dbBaseUrl/users.json?orderBy="username"&equalTo="${Uri.encodeQueryComponent(loginEmail)}"');
        final response = await http.get(queryUrl);

        if (response.statusCode != 200 || response.body == 'null' || response.body.isEmpty) {
          throw Exception('User with this username not found. (Check Firebase Rules if this is incorrect)');
        }

        // Extract the exact email address tied to this username
        final usersMap = json.decode(response.body) as Map<String, dynamic>;
        
        if (usersMap.isEmpty) {
          throw Exception('Username search yielded zero profiles.');
        }

        final userRecord = usersMap.values.first as Map<String, dynamic>;
        
        if (userRecord['email'] == null) {
          throw Exception('Account configuration error: No email attached.');
        }
        
        loginEmail = userRecord['email'] as String;
      } catch (e) {
        throw Exception('REST Lookup Failed: $e');
      }
    }

    // 2. Perform the actual Firebase Authentication with Email and Password
    try {
      // CRITICAL FIX: Disconnect RTDB BEFORE the auth state change.
      // The Firebase C++ RTDB SDK asserts connection_state_ == kDisconnected
      // when it tries to reconnect after an auth change. If the persistent
      // connection is still active, the assertion fails and abort() is called,
      // crashing the Windows app. Going offline first ensures a clean state.
      FirebaseDatabase.instance.goOffline();

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: loginEmail,
        password: password,
      );
      
      // 3. Verify they actually exist in the DB and pull their FULL data profile securely using pure REST HTTP
      final uid = userCredential.user!.uid;
      // Get a fresh ID token to authenticate the RTDB read (required by security rules: auth != null)
      final idToken = await userCredential.user!.getIdToken(true);
      final profileUrl = Uri.parse('$_dbBaseUrl/users/$uid.json?auth=$idToken');

      // TRACK SECURITY DATA: Capture actual login time and public IP
      String publicIp = 'Unknown';
      try {
        final ipResponse = await http.get(Uri.parse('https://api.ipify.org')).timeout(const Duration(seconds: 3));
        if (ipResponse.statusCode == 200) publicIp = ipResponse.body;
      } catch (_) {}

      final now = DateTime.now().toIso8601String();
      await http.patch(profileUrl, body: json.encode({
        'lastLogin': now,
        'lastIp': publicIp,
      }));
      
      final profileResponse = await http.get(profileUrl);
      
      final rawUserData = Map<String, dynamic>.from(json.decode(profileResponse.body) as Map<String, dynamic>);
      
      // EMAIL SYNCHRONIZATION (Free Tier Fallback)
      // Check if the Auth email (verified) has changed compared to the DB record.
      final authEmail = userCredential.user!.email;
      if (authEmail != null && authEmail != rawUserData['email']) {
        print('[AuthService] Email mismatch detected! Auth: $authEmail, DB: ${rawUserData['email']}');
        try {
          // Perform a sync patch to RTDB using the authenticated UID and a fresh token
          final idToken = await userCredential.user!.getIdToken(true);
          final syncUrl = Uri.parse('$_dbBaseUrl/users/$uid.json?auth=$idToken');
          final syncResponse = await http.patch(syncUrl, body: json.encode({'email': authEmail}));
          
          if (syncResponse.statusCode == 200) {
            print('[AuthService] RTDB successfully synchronized with new email.');
            // Update the local data map so the UI reflects it immediately
            rawUserData['email'] = authEmail;
          } else {
            print('[AuthService] RTDB sync failed with status: ${syncResponse.statusCode}');
          }
        } catch (e) {
          print('[AuthService] Email synchronization failure: $e');
        }
      }

      // Re-establish RTDB connection now that auth is fully settled.
      // This reconnects with the new credentials so the persistent connection
      // transitions from kDisconnected -> kConnecting -> kConnected cleanly.
      FirebaseDatabase.instance.goOnline();

      // Return a convenient bundle containing both the secure auth reference and UI data 
      return {
        'user': userCredential.user,
        'userData': rawUserData,
      };
      
    } on FirebaseAuthException catch (e) {
      // Provide clean error messages for the UI
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        throw Exception('Incorrect email or password.');
      } else if (e.code == 'wrong-password') {
        throw Exception('Incorrect password.');
      } else if (e.code == 'too-many-requests') {
        throw Exception('Too many failed attempts. Please try again later.');
      }
      throw Exception(e.message ?? 'Authentication failed.');
    }
  }

  /// Logs the current user out
  Future<void> logout() async {
    await _auth.signOut();
  }

  /// Creates a persistent user profile in the database via REST and Auth via Secondary App.
  Future<String> createUserRecord(Map<String, dynamic> userData, String tempPassword) async {
    final email = userData['email'] as String;
    
    // Inject the flag that forces the new user to reset their password on first login
    userData['requiresPasswordChange'] = true;
    
    // 1. Get the current admin's auth token for the secure RTDB write.
    // We do this before creating the secondary app just to be safe.
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Must be logged in to create a user.');
    }
    final adminToken = await currentUser.getIdToken(true);

    FirebaseApp? secondaryApp;
    String newUid = '';
    try {
      // 2. Initialize a secondary Firebase App to create the user without logging out the Admin
      secondaryApp = await Firebase.initializeApp(
        name: 'SecondaryAppRegistration',
        options: Firebase.app().options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      // 3. Create the user in Auth
      final userCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: tempPassword,
      );

      newUid = userCredential.user!.uid;

      // 4. Securely write the data to RTDB using PUT on the specific $uid node, authenticated by the Admin
      final url = Uri.parse('$_dbBaseUrl/users/$newUid.json?auth=$adminToken');
      final response = await http.put(
        url,
        body: json.encode(userData),
      );

      if (response.statusCode != 200) {
        throw Exception('Database Write Error: Status Code ${response.statusCode} - ${response.body}');
      }

      // 5. Send custom HTML welcome email via SMTP directly from app
      try {
        await EmailService.sendWelcomeEmail(
          targetEmail: email,
          name: userData['name']?.toString() ?? '',
          username: userData['username']?.toString() ?? '',
          tempPassword: tempPassword,
          role: userData['role']?.toString() ?? '',
        );
      } catch (e) {
        // Re-throw and surface the real error so we can see WHY it failed
        throw Exception('User created successfully, but email failed: $e');
      }

      return newUid;

    } finally {
      // 6. Gracefully clean up the temporary app instance
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  /// Deletes a user profile from the database and attempts to trigger the auth wipe.
  Future<void> deleteUser(String targetUid) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Authorization Error: Must be logged in as Admin to perform deletions.');
    }

    // 1. Get Admin Token for RTDB REST authentication
    final adminToken = await currentUser.getIdToken(true);

    // 2. Perform the Database Wipe (Soft Delete - Immediate ban)
    final profileUrl = Uri.parse('$_dbBaseUrl/users/$targetUid.json?auth=$adminToken');
    final response = await http.delete(profileUrl);

    if (response.statusCode != 200) {
      throw Exception('Database Deletion Failed: ${response.statusCode} - ${response.body}');
    }

    // 3. Attempt the Cloud Function (Hard Delete - Auth account wipe)
    // This will gracefully fail with a log if the user hasn't upgraded to Blaze yet.
    try {
      final cloudUrl = Uri.parse('https://us-central1-crowdsense-db.cloudfunctions.net/deleteUserAccount');
      await http.post(
        cloudUrl,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $adminToken', // Cloud functions require Bearer auth for onCall
        },
        body: json.encode({'data': {'targetUid': targetUid}}),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      print('Cloud Function trigger skipped/failed (Blaze Plan required): $e');
    }
  }
}

