import 'package:flutter/material.dart';
import '../widgets/bottom_toolbar.dart';
import '../config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/map_picker.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'login.dart';
import '../main.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  User? _user;
  Map<String, dynamic>? _userProfile;
  bool _isEditing = false;
  double? _currentLat;
  double? _currentLng;
  int? _detectedWardNo;
  List<_WardPolygon> _wardPolygons = [];

  @override
  void initState() {
    super.initState();
    _loadWardPolygons();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
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

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        setState(() {
          _user = user;
        });

        // Fetch user profile from profiles table
        final response = await SupabaseConfig.client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .single();

        if (response != null) {
          setState(() {
            _userProfile = response;
            _nameController.text = response['name'] ?? '';
            _phoneController.text = response['phone'] ?? '';
            _addressController.text = response['address'] ?? '';
            _currentLat = response['latitude'];
            _currentLng = response['longitude'];
            if (_currentLat != null && _currentLng != null) {
              _detectedWardNo = _detectWardNo(_currentLat!, _currentLng!);
            }
            // Set isEditing to true if any required field is not set
            _isEditing = response['name'] == null || response['name'].isEmpty || 
                        response['phone'] == null || response['phone'].isEmpty ||
                        response['address'] == null || response['address'].isEmpty;
          });
        } else {
          setState(() {
            _isEditing = true;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.loadProfileError;
        _isEditing = true;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (_user == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Update user profile in profiles table
      await SupabaseConfig.client.from('profiles').upsert({
        'id': _user!.id,
        'name': _nameController.text,
        'phone': _phoneController.text,
        'address': _addressController.text,
        'latitude': _currentLat,
        'longitude': _currentLng,
        'ward_no': _detectedWardNo,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Reload user data
      await _loadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profileUpdated),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error updating profile: $e');
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.updateProfileError;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.profile,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.normal,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await SupabaseConfig.client.auth.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => const CombinedLoginPage()),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.logout),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            icon: const Icon(
              Icons.logout,
              color: Colors.red,
              size: 20,
            ),
            label: Text(
              l10n.logout,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 20.0, right: 20.0, top: 20.0, bottom: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.red,
                                child: Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _userProfile?['name'] ?? l10n.notSet,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _user?.email ?? '',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        if (!_isEditing)
                          Positioned(
                            top: -8,
                            right: -8,
                            child: IconButton(
                              onPressed: () {
                                setState(() {
                                  _isEditing = true;
                                });
                              },
                              icon: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.red,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isEditing ? _buildUpdateForm(l10n) : _buildProfileInfo(l10n),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: BottomToolbar(currentIndex: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildInfoRow(Icons.phone, l10n.phone, _userProfile?['phone'] ?? l10n.notSet),
              const Divider(height: 1),
              _buildInfoRow(
                Icons.location_on,
                l10n.address,
                _userProfile?['address'] ?? l10n.notSet,
                subtitle: _detectedWardNo != null ? l10n.wardNo(_detectedWardNo.toString()) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.red, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.green[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.updateProfile,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.name,
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
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  prefixIcon: const Icon(Icons.person, color: Colors.red),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: l10n.phoneNumber,
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
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  prefixIcon: const Icon(Icons.phone, color: Colors.red),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              Text(l10n.address, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700])),
              const SizedBox(height: 6),
              TextField(
                controller: _addressController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: l10n.selectLocationOnMap,
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
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.map, color: Colors.red),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapPicker(
                            onLocationSelected: (address, lat, lng) {
                              setState(() {
                                _addressController.text = address;
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
              if (_detectedWardNo != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    l10n.detectedWardNo(_detectedWardNo.toString()),
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          l10n.updateProfile,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WardPolygon {
  final int wardNo;
  final List<List<double>> points;
  _WardPolygon(this.wardNo, this.points);
} 