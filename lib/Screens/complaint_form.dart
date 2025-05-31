// Required dependencies:
//   intl: ^0.18.0
//   image_picker: ^1.0.0
//   geolocator: ^9.0.2
//   geocoding: ^2.0.5
//   uuid: ^4.0.0
//   video_player: ^2.8.2

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:video_player/video_player.dart';
import '../config/supabase_config.dart';
import '../config/api_config.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../widgets/map_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/bottom_toolbar.dart';

class LatLng {
  final double lat;
  final double lng;
  LatLng(this.lat, this.lng);
}

Future<LatLng?> geocodeAddressWithGoogle(String address) async {
  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=${ApiConfig.googleMapsApiKey}'
  );
  final response = await http.get(url);
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['status'] == 'OK' && data['results'].isNotEmpty) {
      final location = data['results'][0]['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    }
  }
  return null;
}

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
  final _formKey = GlobalKey<FormState>();
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  String? _videoError;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadWardPolygons();
    _loadUserProfile();
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

  Future<void> _loadUserProfile() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        // Set email from auth
        if (user.email != null) {
          _emailController.text = user.email!;
        }

        // Fetch user profile from profiles table
        final response = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .single();

        if (response != null && mounted) {
          setState(() {
            _contactController.text = response['phone'] ?? '';
            // Set the location from profile address if available
            if (response['address'] != null && response['address'].isNotEmpty) {
              _locationController.text = response['address'];
              // Try to geocode the address to get coordinates
              _onManualAddressChanged(response['address']);
            }
          });
        }
      }
    } catch (e) {
      print('Error loading user profile: $e');
    }
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
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );

      // Get address from coordinates
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = [
          if (place.street?.isNotEmpty ?? false) place.street,
          if (place.subLocality?.isNotEmpty ?? false) place.subLocality,
          if (place.locality?.isNotEmpty ?? false) place.locality,
          if (place.administrativeArea?.isNotEmpty ?? false) place.administrativeArea,
          if (place.country?.isNotEmpty ?? false) place.country,
        ].where((s) => s != null).join(', ');

        setState(() {
          _locationController.text = address;
          _currentLat = position.latitude;
          _currentLng = position.longitude;
          _detectedWardNo = _detectWardNo(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }

  Future<void> _onManualAddressChanged(String value) async {
    final latLng = await geocodeAddressWithGoogle(value);
    if (latLng != null) {
      setState(() {
        _currentLat = latLng.lat;
        _currentLng = latLng.lng;
        _detectedWardNo = _detectWardNo(latLng.lat, latLng.lng);
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not geocode address.')),
        );
      }
    }
  }

  Future<bool> _requestStoragePermissions() async {
    if (Platform.isAndroid) {
      // For Android 13 and above (API level 33+)
      if (await Permission.photos.request().isGranted &&
          await Permission.videos.request().isGranted) {
        return true;
      }
      // For Android 12 and below
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      return false;
    } else if (Platform.isIOS) {
      if (await Permission.photos.request().isGranted) {
        return true;
      }
      return false;
    }
    return false;
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to take photos and videos'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record videos with sound'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _pickImage() async {
    // Request camera and storage permissions
    final cameraGranted = await _requestCameraPermission();
    final storageGranted = await _requestStoragePermissions();
    
    if (!cameraGranted || !storageGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant the required permissions in Settings'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: openAppSettings,
            ),
          ),
        );
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFFDC2626)),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1920,
                      maxHeight: 1080,
                      imageQuality: 85,
                    );
    if (picked != null && File(picked.path).existsSync()) {
      setState(() => _image = File(picked.path));
                    }
                  } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error selecting image: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFFDC2626)),
                title: const Text('Take a Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                      maxWidth: 1920,
                      maxHeight: 1080,
                      imageQuality: 85,
                    );
                    if (picked != null && File(picked.path).existsSync()) {
                      setState(() => _image = File(picked.path));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error taking photo: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showImagePreview() {
    if (_image != null) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Stack(
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_image!, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  void _videoListener() {
    if (mounted) {
      setState(() {
        _isPlaying = _videoController?.value.isPlaying ?? false;
      });
    }
  }

  void _showVideoPreview() async {
    if (_video != null) {
      try {
        _videoController?.dispose();
        _videoController = VideoPlayerController.file(_video!);
        
        await _videoController!.initialize();
        
        if (!mounted) return;
        
        setState(() {
          _isVideoInitialized = true;
          _videoError = null;
          _isPlaying = false;
        });
        
        _videoController!.addListener(_videoListener);
        _videoController!.play();
        _videoController!.setLooping(true);

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Stack(
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.8,
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _isVideoInitialized
                          ? AspectRatio(
                              aspectRatio: _videoController!.value.aspectRatio,
                              child: VideoPlayer(_videoController!),
                            )
                          : _videoError != null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                      const SizedBox(height: 16),
                                      Text(
                                        _videoError!,
                                        style: const TextStyle(color: Colors.white),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        _videoController?.removeListener(_videoListener);
                        _videoController?.pause();
                        _videoController?.dispose();
                        _videoController = null;
                        _isVideoInitialized = false;
                        _videoError = null;
                        _isPlaying = false;
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  if (_isVideoInitialized)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: () {
                                if (_isPlaying) {
                                  _videoController?.pause();
                                } else {
                                  _videoController?.play();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _videoError = 'Failed to load video: ${e.toString()}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    // Request camera, microphone, and storage permissions
    final cameraGranted = await _requestCameraPermission();
    final microphoneGranted = await _requestMicrophonePermission();
    final storageGranted = await _requestStoragePermissions();
    
    if (!cameraGranted || !microphoneGranted || !storageGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant the required permissions in Settings'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Settings',
              textColor: Colors.white,
              onPressed: openAppSettings,
            ),
          ),
        );
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.video_library, color: Color(0xFFDC2626)),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final picked = await ImagePicker().pickVideo(
                      source: ImageSource.gallery,
                      maxDuration: const Duration(minutes: 5),
                    );
      if (picked != null && File(picked.path).existsSync()) {
                      setState(() {
                        _video = File(picked.path);
                        _isVideoInitialized = false;
                        _videoError = null;
                      });
                    }
                  } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error selecting video: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Color(0xFFDC2626)),
                title: const Text('Record a Video'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final picked = await ImagePicker().pickVideo(
                      source: ImageSource.camera,
                      maxDuration: const Duration(minutes: 5),
                    );
                    if (picked != null && File(picked.path).existsSync()) {
                      setState(() {
                        _video = File(picked.path);
                        _isVideoInitialized = false;
                        _videoError = null;
                      });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error recording video: ${e.toString()}'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _uploadFileToSupabase(File file, String folder) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final ext = p.extension(file.path);
      final fileName = '${const Uuid().v4()}$ext';
      final storagePath = '${user.id}/$folder/$fileName';
      final bytes = await file.readAsBytes();

      // Upload the file
      final response = await SupabaseConfig.client.storage
          .from('complaint-attachments')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'application/octet-stream',
            ),
          );

      // The response contains the path of the uploaded file
      if (response.isNotEmpty) {
        // Get the public URL
        final url = SupabaseConfig.client.storage
            .from('complaint-attachments')
            .getPublicUrl(response);
        print('File uploaded successfully: $url');
        return url;
      } else {
        print('Upload response is empty');
        throw Exception('Upload failed: Empty response');
      }
    } catch (e, stackTrace) {
      print('Upload error: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload file: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _submitComplaint() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_detectedWardNo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect ward number'), backgroundColor: Colors.red),
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

      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final response = await SupabaseConfig.client.from('complaints').insert({
        'user_id': user.id,
        'email_id': _emailController.text,
        'phone_no': _contactController.text,
        'address': _locationController.text,
        'ward_no': _detectedWardNo,
        'complaint_type': widget.category,
        'description': _descriptionController.text,
        'image_url': imageUrl,
        'video_url': videoUrl,
        'date_occurred': _selectedDate!.toIso8601String(),
        'latitude': _currentLat,
        'longitude': _currentLng,
        'status': 'pending',
      }).select();

      if (response.isEmpty) {
        throw Exception('Failed to create complaint');
      }

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
    _videoController?.removeListener(_videoListener);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          'Submit Complaint',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _emailController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFDC2626)),
                            ),
                            prefixIcon: const Icon(Icons.email, color: Color(0xFFDC2626)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.category, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                widget.category,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Date issue arose',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 20, color: Color(0xFFDC2626)),
                                const SizedBox(width: 12),
                                Text(
                                  _selectedDate == null
                                  ? 'Select date'
                                  : _selectedDate!.toLocal().toString().split(' ')[0],
                                  style: TextStyle(
                                    color: _selectedDate == null ? Colors.grey[600] : Color(0xFF1F2937),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Location',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _locationController,
                                readOnly: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please select a location';
                                  }
                                  return null;
                                },
                                decoration: InputDecoration(
                                  hintText: 'Select location on map',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Color(0xFFDC2626)),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.map, color: Color(0xFFDC2626)),
                                    onPressed: () async {
                                      final result = await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => MapPicker(
                                            onLocationSelected: (address, lat, lng) {
                                              setState(() {
                                                _locationController.text = address;
                                                _currentLat = lat;
                                                _currentLng = lng;
                                                _detectedWardNo = _detectWardNo(lat, lng);
                                              });
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
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
                                backgroundColor: const Color(0xFFDC2626).withOpacity(0.1),
                                foregroundColor: const Color(0xFFDC2626),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                        if (_detectedWardNo != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Ward No: $_detectedWardNo',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contact Number',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _contactController,
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a contact number';
                            }
                            if (!RegExp(r'^\+?[\d\s-]{10,}$').hasMatch(value)) {
                              return 'Please enter a valid phone number';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Enter contact number',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFDC2626)),
                            ),
                            prefixIcon: const Icon(Icons.phone, color: Color(0xFFDC2626)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 4,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a description';
                            }
                            if (value.length < 10) {
                              return 'Description must be at least 10 characters';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Describe the issue',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFDC2626)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Attachments',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Image (Optional)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_image != null)
                                  GestureDetector(
                                    onTap: _showImagePreview,
                                    child: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.file(_image!, width: 60, height: 60, fit: BoxFit.cover),
                                        ),
                                        GestureDetector(
                                          onTap: () => setState(() => _image = null),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close, size: 16, color: Color(0xFFDC2626)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_image == null)
                                  IconButton(
                                    icon: const Icon(Icons.add_a_photo, color: Color(0xFFDC2626)),
                                    onPressed: _pickImage,
                                  ),
                              ],
                            ),
                            const SizedBox(width: 24),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Video (Optional)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_video != null)
                                  GestureDetector(
                                    onTap: _showVideoPreview,
                                    child: Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        Container(
                                          width: 80,
                                          height: 60,
                                          decoration: BoxDecoration(
                                            color: Colors.black12,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.videocam, size: 36, color: Color(0xFFDC2626)),
                                        ),
                                        GestureDetector(
                                          onTap: () => setState(() => _video = null),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close, size: 16, color: Color(0xFFDC2626)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_video == null)
                                  IconButton(
                                    icon: const Icon(Icons.add_photo_alternate, color: Color(0xFFDC2626)),
                                    onPressed: _pickVideo,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitComplaint,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Submit Complaint',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: BottomToolbar(currentIndex: 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _WardPolygon {
  final int wardNo;
  final List<List<double>> points;
  _WardPolygon(this.wardNo, this.points);
} 