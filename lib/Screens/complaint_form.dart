// Required dependencies:
//   intl: ^0.18.0
//   image_picker: ^1.0.0
//   geolocator: ^9.0.2 (for real location)
//   geocoding: ^2.0.5 (for real address)
//
// TODO: Add these to your pubspec.yaml and run `flutter pub get`

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../config/supabase_config.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class ComplaintFormPage extends StatefulWidget {
  final String category;
  const ComplaintFormPage({Key? key, required this.category}) : super(key: key);

  @override
  State<ComplaintFormPage> createState() => _ComplaintFormPageState();
}

class _ComplaintFormPageState extends State<ComplaintFormPage> {
  DateTime? _selectedDate;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  File? _image;
  File? _video;
  bool _isGettingLocation = false;
  bool _isSubmitting = false;
  int? _detectedWardNo;
  List<_WardPolygon> _wardPolygons = [];
  double? _currentLat;
  double? _currentLng;

  @override
  void initState() {
    super.initState();
    _loadWardPolygons();
    final user = SupabaseConfig.client.auth.currentUser;
    if (user != null && user.email != null) {
      _emailController.text = user.email!;
    }
  }

  Future<void> _loadWardPolygons() async {
    final String jsonString = await rootBundle.loadString('assets/madurai_wards.geojson');
    final Map<String, dynamic> jsonData = json.decode(jsonString);
    final List<dynamic> features = jsonData['features'];
    List<_WardPolygon> polygons = [];
    for (var feature in features) {
      final properties = feature['properties'];
      final wardNo = int.tryParse(properties['Ward_No'].toString());
      final geometry = feature['geometry'];
      if (geometry['type'] != 'MultiPolygon') continue;
      final List<dynamic> multiPoly = geometry['coordinates'];
      for (var poly in multiPoly) {
        final List<dynamic> rings = poly;
        if (rings.isEmpty) continue;
        final List<dynamic> outerRing = rings[0];
        List<List<double>> points = [];
        for (var coord in outerRing) {
          if (coord is List && coord.length >= 2) {
            double? lng = (coord[0] is num) ? coord[0].toDouble() : double.tryParse(coord[0].toString());
            double? lat = (coord[1] is num) ? coord[1].toDouble() : double.tryParse(coord[1].toString());
            if (lat != null && lng != null) {
              points.add([lat, lng]);
            }
          }
        }
        if (points.isNotEmpty && wardNo != null) {
          polygons.add(_WardPolygon(wardNo, points));
        }
      }
    }
    setState(() {
      _wardPolygons = polygons;
    });
  }

  int? _detectWardNo(double lat, double lng) {
    for (final poly in _wardPolygons) {
      if (_isPointInPolygon(lat, lng, poly.points)) {
        return poly.wardNo;
      }
    }
    return null;
  }

  bool _isPointInPolygon(double lat, double lng, List<List<double>> polygon) {
    bool isInside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i][0] > lat) != (polygon[j][0] > lat) &&
          (lng < (polygon[j][1] - polygon[i][1]) * (lat - polygon[i][0]) /
                  (polygon[j][0] - polygon[i][0]) +
              polygon[i][1])) {
        isInside = !isInside;
      }
      j = i;
    }
    return isInside;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    // TODO: Use geolocator/geocoding to get real address and lat/lng
    await Future.delayed(const Duration(seconds: 1));
    // Demo: hardcoded Madurai lat/lng
    double lat = 9.9252;
    double lng = 78.1198;
    setState(() {
      _locationController.text = 'Madurai, TN, India';
      _currentLat = lat;
      _currentLng = lng;
      _detectedWardNo = _detectWardNo(lat, lng);
      _isGettingLocation = false;
    });
  }

  Future<void> _onManualAddressChanged(String value) async {
    // TODO: Use geocoding API to get lat/lng from address
    // For demo, use hardcoded Madurai center
    double lat = 9.9252;
    double lng = 78.1198;
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      _detectedWardNo = _detectWardNo(lat, lng);
    });
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null && File(picked.path).existsSync()) {
      setState(() => _image = File(picked.path));
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image selected or file not found.')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked != null && File(picked.path).existsSync()) {
        setState(() => _video = File(picked.path));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No video selected or file not found.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick video: $e')),
        );
      }
    }
  }

  Future<String?> _uploadFileToSupabase(File file, String folder) async {
    final ext = p.extension(file.path);
    final fileName = '${const Uuid().v4()}$ext';
    final storagePath = '$folder/$fileName';
    final bytes = await file.readAsBytes();
    final bucket = 'complaint-attachments';
    final response = await SupabaseConfig.client.storage
        .from(bucket)
        .uploadBinary(storagePath, bytes, fileOptions: const FileOptions(upsert: true));
    if (response.isEmpty) {
      final url = SupabaseConfig.client.storage.from(bucket).getPublicUrl(storagePath);
      return url;
    } else {
      return null;
    }
  }

  Future<void> _submitComplaint() async {
    if (_isSubmitting) return;
    if (_detectedWardNo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect ward number.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      String? imageUrl;
      String? videoUrl;
      if (_image != null) {
        imageUrl = await _uploadFileToSupabase(_image!, 'images');
      }
      if (_video != null) {
        videoUrl = await _uploadFileToSupabase(_video!, 'videos');
      }
      await SupabaseConfig.client.from('complaints').insert({
        'email_id': _emailController.text,
        'phone_no': _contactController.text,
        'address': _locationController.text,
        'ward_no': _detectedWardNo,
        'complaint_type': widget.category,
        'description': _descriptionController.text,
        'image_url': imageUrl,
        'video_url': videoUrl,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint submitted successfully!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit complaint: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _locationController.dispose();
    _contactController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Complaint'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      backgroundColor: const Color(0xFFF9FAFB),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Text('Category: ${widget.category}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 14),
            Text('Date issue arose', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: Colors.grey[700]),
                    const SizedBox(width: 12),
                    Text(_selectedDate == null
                        ? 'Select date'
                        : _selectedDate!.toLocal().toString().split(' ')[0]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Location', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _locationController,
                    onChanged: _onManualAddressChanged,
                    decoration: InputDecoration(
                      hintText: 'Enter address',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isGettingLocation ? null : _getCurrentLocation,
                  icon: _isGettingLocation
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.my_location, size: 18),
                  label: const Text('Current'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            if (_detectedWardNo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Detected Ward No: $_detectedWardNo', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 14),
            Text('Contact Number', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _contactController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'Enter contact number',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 14),
            Text('Description', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe the issue',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 14),
            Text('Attachment (1 image only, optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_image != null)
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_image!, width: 60, height: 60, fit: BoxFit.cover),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _image = null),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 16, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                if (_image == null)
                  IconButton(
                    icon: Icon(Icons.add_a_photo, color: Colors.red),
                    onPressed: _pickImage,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Video (1 only, optional)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_video != null)
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        width: 80,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.videocam, size: 36, color: Colors.black54),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _video = null),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, size: 16, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                if (_video == null)
                  IconButton(
                    icon: Icon(Icons.videocam, color: Colors.red),
                    onPressed: _pickVideo,
                  ),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitComplaint,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Submit Complaint', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WardPolygon {
  final int wardNo;
  final List<List<double>> points;
  _WardPolygon(this.wardNo, this.points);
} 