import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/phone_formatter.dart';

import '../../../core/widgets/secondary_geometric_background.dart';

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SecondaryGeometricBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Profile Photo section
            Center(
              child: Stack(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blueGrey,
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Floating label styling with light-gray borders
            _buildTextField(context, "Full name", initialValue: "Admin User"),
            const SizedBox(height: 20),
            
            // Birthday and Gender side-by-side
            Row(
              children: [
                Expanded(child: _buildTextField(context, "Birthday", initialValue: "01/01/1990")),
                const SizedBox(width: 16),
                Expanded(child: _buildTextField(context, "Gender", initialValue: "Prefer not to say")),
              ],
            ),
            const SizedBox(height: 20),

            // Contact details stacked vertically
            _buildTextField(context, "Phone", initialValue: "+63 921 535 1298", inputFormatters: [PhilippinePhoneFormatter()]),
            const SizedBox(height: 20),
            _buildTextField(context, "Email", initialValue: "admin@example.com"),
            const SizedBox(height: 20),
            _buildTextField(context, "Username", initialValue: "admin123"),
            
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  "Save Changes",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(BuildContext context, String label, {String? initialValue, List<TextInputFormatter>? inputFormatters}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return TextFormField(
      initialValue: initialValue,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      ),
      inputFormatters: inputFormatters,
    );
  }
}
