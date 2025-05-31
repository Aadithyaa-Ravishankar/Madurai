import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'data/ward_data.dart'; // Add this import
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'config/supabase_config.dart';
import 'Screens/login.dart';
import 'Screens/complaints.dart';
import 'Screens/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/bottom_toolbar.dart';
import 'Screens/splash_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'services/map_service.dart';

class TextBox {
  final LatLng center;
  final double width;
  final double height;

  const TextBox(this.center, this.width, this.height);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await SupabaseConfig.initialize();
    runApp(const MyApp());
  } catch (e) {
    print('Error initializing Supabase: $e');
    // You might want to show an error screen here
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Failed to initialize app: $e'),
        ),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madurai',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const SplashScreen(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseConfig.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final session = snapshot.data!.session;
          if (session != null) {
            return const MapPage();
          }
        }
        return const CombinedLoginPage();
      },
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  final MapService _mapService = MapService();
  GoogleMapController? _mapController;
  Set<Polygon> _polygons = {};
  Set<Marker> _wardLabels = {};
  List<String> _wardNames = [];
  List<String> _wardDescriptions = [];
  List<String> _displayNames = [];
  List<String> _wardNumbers = [];
  final LatLng _maduraiCenter = const LatLng(9.9252, 78.1198);
  double _currentZoom = 13.0;
  LatLngBounds? _mapBounds;
  static const double _minZoomForLabels = 13.0;
  String? _councillorHtml;
  Map<String, Map<String, String>> _councillorData = {};

  // Add search-related variables
  final TextEditingController _searchController = TextEditingController();
  List<String> _searchSuggestions = [];
  bool _isSearching = false;
  OverlayEntry? _overlayEntry;

  // Enhanced ward colors with better visibility and contrast
  final List<Color> _wardColors = [
    const Color(0xFFE3F2FD).withOpacity(0.85), // Light Blue
    const Color(0xFFE8F5E9).withOpacity(0.85), // Light Green
    const Color(0xFFF3E5F5).withOpacity(0.85), // Light Purple
    const Color(0xFFFFEBEE).withOpacity(0.85), // Light Red
    const Color(0xFFFFF3E0).withOpacity(0.85), // Light Orange
    const Color(0xFFE0F7FA).withOpacity(0.85), // Light Cyan
    const Color(0xFFF1F8E9).withOpacity(0.85), // Light Lime
    const Color(0xFFFCE4EC).withOpacity(0.85), // Light Pink
    const Color(0xFFEFEBE9).withOpacity(0.85), // Light Brown
    const Color(0xFFE8EAF6).withOpacity(0.85), // Light Indigo
    const Color(0xFFF9FBE7).withOpacity(0.85), // Light Yellow
    const Color(0xFFE0F2F1).withOpacity(0.85), // Light Teal
    const Color(0xFFF5F5F5).withOpacity(0.85), // Light Grey
    const Color(0xFFEDE7F6).withOpacity(0.85), // Light Deep Purple
    const Color(0xFFE8F5E9).withOpacity(0.85), // Light Green
    const Color(0xFFE0F7FA).withOpacity(0.85), // Light Cyan
    const Color(0xFFF3E5F5).withOpacity(0.85), // Light Purple
    const Color(0xFFFFEBEE).withOpacity(0.85), // Light Red
    const Color(0xFFFFF3E0).withOpacity(0.85), // Light Orange
    const Color(0xFFE3F2FD).withOpacity(0.85), // Light Blue
  ];

  // Add stroke colors for better contrast
  final List<Color> _wardStrokeColors = [
    const Color(0xFF1976D2).withOpacity(0.8), // Blue
    const Color(0xFF388E3C).withOpacity(0.8), // Green
    const Color(0xFF7B1FA2).withOpacity(0.8), // Purple
    const Color(0xFFD32F2F).withOpacity(0.8), // Red
    const Color(0xFFF57C00).withOpacity(0.8), // Orange
    const Color(0xFF0097A7).withOpacity(0.8), // Cyan
    const Color(0xFF7CB342).withOpacity(0.8), // Lime
    const Color(0xFFC2185B).withOpacity(0.8), // Pink
    const Color(0xFF5D4037).withOpacity(0.8), // Brown
    const Color(0xFF3F51B5).withOpacity(0.8), // Indigo
    const Color(0xFFFBC02D).withOpacity(0.8), // Yellow
    const Color(0xFF00796B).withOpacity(0.8), // Teal
    const Color(0xFF616161).withOpacity(0.8), // Grey
    const Color(0xFF512DA8).withOpacity(0.8), // Deep Purple
    const Color(0xFF388E3C).withOpacity(0.8), // Green
    const Color(0xFF0097A7).withOpacity(0.8), // Cyan
    const Color(0xFF7B1FA2).withOpacity(0.8), // Purple
    const Color(0xFFD32F2F).withOpacity(0.8), // Red
    const Color(0xFFF57C00).withOpacity(0.8), // Orange
    const Color(0xFF1976D2).withOpacity(0.8), // Blue
  ];

  // Custom HTTP client with DNS configuration
  final _httpClient = http.Client();

  // Add a GlobalKey for the search bar
  final GlobalKey _searchBarKey = GlobalKey();

  late AnimationController _animationController;
  late Animation<double> _animation;
  int _currentIndex = 1; // 0: Complaints, 1: Home, 2: Profile

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _setMapStyle();
    
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // Load data if not already loaded
    if (!_mapService.isMapReady) {
      _loadGeoJSON();
      _loadCouncillorHtml();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _removeOverlay();
    _httpClient.close();
    // Don't dispose the map controller here as it's managed by MapService
    super.dispose();
  }

  Future<void> _loadGeoJSON() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/madurai_wards.geojson');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      final List<dynamic> features = jsonData['features'];
      
      final List<List<LatLng>> wardPoints = [];
      final List<String> wardNames = [];
      final List<String> wardDescriptions = [];
      final List<String> displayNames = [];
      final List<String> wardNumbers = [];
      
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      for (var feature in features) {
        try {
          final properties = feature['properties'];
          final wardName = properties['Name']?.toString() ?? 'Unknown Ward';
          final wardDescription = properties['Description']?.toString() ?? '';
          final wardNo = properties['Ward_No']?.toString() ?? '';
          
          // Clean the ward name by removing the ward number prefix if it exists
          String displayName = wardName;
          if (wardName.startsWith('WARD NO:') || wardName.startsWith('Ward')) {
            displayName = wardName.split(':').last.trim();
          }
          displayNames.add(displayName);
          wardNumbers.add(wardNo);
          
          final geometry = feature['geometry'];
          if (geometry['type'] != 'MultiPolygon') {
            debugPrint("Warning: Unexpected geometry type ${geometry['type']} for ward $wardName");
            continue;
          }

          // Process MultiPolygon coordinates
          final List<dynamic> polygons = geometry['coordinates'];
          final List<LatLng> allPoints = [];

          for (var polygon in polygons) {
            // Each polygon is a list of rings, where the first ring is the outer boundary
            final List<dynamic> rings = polygon;
            if (rings.isEmpty) continue;

            // Process the outer ring (first ring)
            final List<dynamic> outerRing = rings[0];
            for (var coord in outerRing) {
              if (coord is! List || coord.length < 2) {
                debugPrint("Invalid coordinate format: $coord");
                continue;
              }

              // GeoJSON uses [longitude, latitude] order
              double? lng;
              double? lat;
              try {
                lng = (coord[0] is num) ? coord[0].toDouble() : double.tryParse(coord[0].toString());
                lat = (coord[1] is num) ? coord[1].toDouble() : double.tryParse(coord[1].toString());
              } catch (e) {
                debugPrint("Error converting coordinates: $e");
                continue;
              }

              // Skip invalid coordinates
              if (lng == null || lat == null || 
                  lat < -90 || lat > 90 || 
                  lng < -180 || lng > 180) {
                debugPrint("Invalid coordinates: lat=$lat, lng=$lng");
                continue;
              }
              
              // Update bounds
              minLat = minLat < lat ? minLat : lat;
              maxLat = maxLat > lat ? maxLat : lat;
              minLng = minLng < lng ? minLng : lng;
              maxLng = maxLng > lng ? maxLng : lng;
              
              allPoints.add(LatLng(lat, lng));
            }
          }

          if (allPoints.isNotEmpty) {
            // Ensure the polygon is closed
            if (allPoints.first.latitude != allPoints.last.latitude || 
                allPoints.first.longitude != allPoints.last.longitude) {
              allPoints.add(allPoints.first);
            }
            
            wardPoints.add(allPoints);
            wardNames.add(wardName);
            wardDescriptions.add(wardDescription);
            debugPrint("Successfully added ward $wardName with ${allPoints.length} points");
          } else {
            debugPrint("No valid points found for ward $wardName");
          }
        } catch (e) {
          debugPrint("Error processing feature: $e");
        }
      }

      debugPrint("\nMap bounds: lat($minLat, $maxLat), lng($minLng, $maxLng)");
      debugPrint("Total wards processed: ${wardPoints.length}");

      if (wardPoints.isEmpty) {
        debugPrint("No valid wards found in GeoJSON");
        return;
      }

      // Store the bounds for later use
      _mapBounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      final List<Color> colors = _colorWards(wardPoints);
      final Set<Polygon> loadedPolygons = {};
      final Set<Marker> loadedLabels = {};

      // Second pass: create polygons with improved visibility settings
      for (int i = 0; i < wardPoints.length; i++) {
        try {
          final polygon = Polygon(
            polygonId: PolygonId('ward_$i'),
            points: wardPoints[i],
            fillColor: colors[i],
            strokeColor: _wardStrokeColors[i % _wardStrokeColors.length],
            strokeWidth: 1,
          );
          loadedPolygons.add(polygon);

          // Calculate position and add label
          final textBox = _findLargestTextBox(wardPoints[i]);
          final customIcon = await _createCustomMarkerIcon(displayNames[i], textBox.width, textBox.height);
          final label = Marker(
            markerId: MarkerId('label_$i'),
            position: textBox.center,
            infoWindow: InfoWindow(
              title: displayNames[i],
            ),
            visible: _currentZoom >= _minZoomForLabels,
            icon: customIcon,
            anchor: const Offset(0.5, 0.5),
            onTap: () {
              _showWardDetails(i);
            },
          );
          loadedLabels.add(label);
        } catch (e) {
          debugPrint("Error creating polygon for ${wardNames[i]}: $e");
        }
      }

      setState(() {
        _mapService.setPolygons(loadedPolygons);
        _mapService.setWardLabels(loadedLabels);
        _wardNames.clear();
        _wardNames.addAll(wardNames);
        _wardDescriptions.clear();
        _wardDescriptions.addAll(wardDescriptions);
        _displayNames.clear();
        _displayNames.addAll(displayNames);
        _wardNumbers.clear();
        _wardNumbers.addAll(wardNumbers);
      });

      // Wait for the map to be ready and rendered
      if (_mapService.mapController != null) {
        // First, ensure we're at the correct zoom level
        await _mapService.mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(_mapBounds!, 50),
          duration: const Duration(milliseconds: 500),
        );

        // Then wait for the map to be fully rendered
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      
      if (mounted) {
        setState(() {
          _mapService.setLoading(false);
        });
      }

      debugPrint("\nSuccessfully loaded ${loadedPolygons.length} polygons");
    } catch (e) {
      debugPrint('Error loading GeoJSON: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load map data: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadCouncillorHtml() async {
    try {
      debugPrint('Loading councillor HTML...');
      final String htmlContent = await rootBundle.loadString('assets/councillor.html');
      _councillorHtml = htmlContent;
      debugPrint('Successfully loaded councillor HTML');
      debugPrint('HTML content length: ${htmlContent.length}');
      _parseCouncillorData();
    } catch (e) {
      debugPrint('Error loading councillor HTML: $e');
    }
  }

  void _parseCouncillorData() {
    if (_councillorHtml == null) {
      debugPrint('Councillor HTML is null, cannot parse data');
      return;
    }

    debugPrint('Parsing councillor data...');
    final document = htmlParser.parse(_councillorHtml!);
    final rows = document.querySelectorAll('table tr');
    debugPrint('Found ${rows.length} rows in councillor table');

    for (var row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length >= 8) {
        final wardNoRaw = cells[0].text.trim();
        final wardNo = wardNoRaw.replaceAll(RegExp(r'[^0-9]'), '');
        final name = cells[1].text.trim();
        final address = cells[2].text.trim();
        final contact = cells[3].text.trim();
        final email = cells[4].text.trim();
        final responsibility = cells[5].text.trim();
        final party = cells[6].text.trim();
        final photo = cells[7].querySelector('img')?.attributes['src'] ?? '';

        debugPrint('Parsed ward $wardNo: $name');

        _councillorData[wardNo] = {
          'name': name,
          'address': address,
          'contact': contact,
          'email': email,
          'responsibility': responsibility,
          'party': party,
          'photo': photo,
        };
      } else {
        debugPrint('Row has insufficient cells: ${cells.length}');
      }
    }
    debugPrint('Finished parsing councillor data. Total entries: ${_councillorData.length}');
    debugPrint('Available ward numbers: ${_councillorData.keys.join(', ')}');
  }

  List<Color> _colorWards(List<List<LatLng>> wardPoints) {
    // Build adjacency list
    final List<List<int>> adjacencyList = List.generate(wardPoints.length, (_) => []);
    for (int i = 0; i < wardPoints.length; i++) {
      for (int j = i + 1; j < wardPoints.length; j++) {
        if (_shareBorder(wardPoints[i], wardPoints[j])) {
          adjacencyList[i].add(j);
          adjacencyList[j].add(i);
          debugPrint("Ward $i and Ward $j share a border");
        }
      }
    }

    // Sort vertices by degree (number of neighbors)
    final List<int> vertices = List.generate(wardPoints.length, (i) => i);
    vertices.sort((a, b) => adjacencyList[b].length.compareTo(adjacencyList[a].length));

    // Initialize colors array
    final List<int> colors = List.filled(wardPoints.length, -1);
    final List<bool> available = List.filled(_wardColors.length, true);

    // Color vertices in order of decreasing degree
    for (int vertex in vertices) {
      // Reset available colors
      available.fillRange(0, _wardColors.length, true);

      // Mark colors of adjacent vertices as unavailable
      for (int neighbor in adjacencyList[vertex]) {
        if (colors[neighbor] != -1) {
          available[colors[neighbor]] = false;
        }
      }

      // Find the first available color
      int colorIndex = 0;
      while (colorIndex < _wardColors.length && !available[colorIndex]) {
        colorIndex++;
      }

      if (colorIndex >= _wardColors.length) {
        // If no color is available, create a new shade
        colors[vertex] = _wardColors.length - 1;
        debugPrint("Warning: Had to use fallback color for ward $vertex");
      } else {
        colors[vertex] = colorIndex;
      }
    }

    // Convert color indices to actual colors
    final List<Color> result = colors.map((colorIndex) => _wardColors[colorIndex]).toList();

    // Verify the coloring
    for (int i = 0; i < wardPoints.length; i++) {
      for (int neighbor in adjacencyList[i]) {
        if (result[i] == result[neighbor]) {
          debugPrint("Warning: Ward $i and Ward $neighbor have the same color!");
        }
      }
    }

    return result;
  }

  bool _shareBorder(List<LatLng> poly1, List<LatLng> poly2) {
    // Improved shared border detection using multiple points
    const double threshold = 0.00001;
    int sharedPoints = 0;
    const int minSharedPoints = 2; // Require at least 2 shared points to consider it a border

    for (int i = 0; i < poly1.length; i++) {
      for (int j = 0; j < poly2.length; j++) {
        if ((poly1[i].latitude - poly2[j].latitude).abs() < threshold &&
            (poly1[i].longitude - poly2[j].longitude).abs() < threshold) {
          sharedPoints++;
          
          // Check if next points also match to confirm it's a shared edge
          final nextI = (i + 1) % poly1.length;
          final nextJ = (j + 1) % poly2.length;
          if ((poly1[nextI].latitude - poly2[nextJ].latitude).abs() < threshold &&
              (poly1[nextI].longitude - poly2[nextJ].longitude).abs() < threshold) {
            sharedPoints++;
          }
        }
      }
    }

    return sharedPoints >= minSharedPoints;
  }

  LatLng _calculateCentroid(List<LatLng> points) {
    if (points.isEmpty) return LatLng(0, 0);
    
    double sumLat = 0;
    double sumLng = 0;
    
    for (var point in points) {
      sumLat += point.latitude;
      sumLng += point.longitude;
    }
    
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  LatLng _findLabelPosition(List<LatLng> points) {
    if (points.isEmpty) return LatLng(0, 0);

    // First try the centroid
    LatLng centroid = _calculateCentroid(points);
    if (_isPointInPolygon(centroid, points)) {
      return centroid;
    }

    // If centroid is outside, find the point with maximum distance from the boundary
    double maxDistance = -1;
    LatLng bestPoint = points[0];

    // Create a grid of points within the bounding box
    double minLat = points.map((p) => p.latitude).reduce(min);
    double maxLat = points.map((p) => p.latitude).reduce(max);
    double minLng = points.map((p) => p.longitude).reduce(min);
    double maxLng = points.map((p) => p.longitude).reduce(max);

    // Use a grid of points to find the best position
    const int gridSize = 10;
    double latStep = (maxLat - minLat) / gridSize;
    double lngStep = (maxLng - minLng) / gridSize;

    for (int i = 0; i <= gridSize; i++) {
      for (int j = 0; j <= gridSize; j++) {
        LatLng testPoint = LatLng(
          minLat + i * latStep,
          minLng + j * lngStep,
        );

        if (_isPointInPolygon(testPoint, points)) {
          // Calculate minimum distance to boundary
          double minDistToBoundary = double.infinity;
          for (int k = 0; k < points.length; k++) {
            int nextK = (k + 1) % points.length;
            double dist = _distanceToLineSegment(
              testPoint,
              points[k],
              points[nextK],
            );
            minDistToBoundary = min(minDistToBoundary, dist);
          }

          if (minDistToBoundary > maxDistance) {
            maxDistance = minDistToBoundary;
            bestPoint = testPoint;
          }
        }
      }
    }

    return bestPoint;
  }

  double _distanceToLineSegment(LatLng point, LatLng lineStart, LatLng lineEnd) {
    double x = point.latitude;
    double y = point.longitude;
    double x1 = lineStart.latitude;
    double y1 = lineStart.longitude;
    double x2 = lineEnd.latitude;
    double y2 = lineEnd.longitude;

    double A = x - x1;
    double B = y - y1;
    double C = x2 - x1;
    double D = y2 - y1;

    double dot = A * C + B * D;
    double lenSq = C * C + D * D;
    double param = -1;

    if (lenSq != 0) {
      param = dot / lenSq;
    }

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    double dx = x - xx;
    double dy = y - yy;

    return sqrt(dx * dx + dy * dy);
  }

  double _calculateMaxTextWidth(LatLng center, List<LatLng> wardPoints) {
    // Convert text dimensions to approximate lat/lng offsets
    const double pixelsPerDegree = 100000.0; // Approximate pixels per degree at zoom level 13
    
    // Find the maximum width that fits within the ward
    double maxWidth = 0;
    double step = 0.0001; // Small step in degrees
    
    // Check width in both directions
    for (double offset = 0; offset < 0.01; offset += step) {
      // Check right side
      LatLng rightPoint = LatLng(center.latitude, center.longitude + offset);
      if (!_isPointInPolygon(rightPoint, wardPoints)) {
        maxWidth = offset;
        break;
      }
      
      // Check left side
      LatLng leftPoint = LatLng(center.latitude, center.longitude - offset);
      if (!_isPointInPolygon(leftPoint, wardPoints)) {
        maxWidth = offset;
        break;
      }
    }
    
    // Convert from degrees to pixels
    return maxWidth * pixelsPerDegree;
  }

  void _showWardDetails(int wardIndex) {
    _removeOverlay();
    final wardName = _wardNames[wardIndex];
    final wardDescription = _wardDescriptions[wardIndex];
    final displayName = _displayNames[wardIndex];
    final wardNo = _wardNumbers[wardIndex];

    Map<String, String>? councillorInfo = _councillorData[wardNo];
    String councillorName = councillorInfo?['name'] ?? 'No councillor details available';
    String councillorAddress = councillorInfo?['address'] ?? '';
    String councillorContact = councillorInfo?['contact'] ?? '';
    String councillorEmail = councillorInfo?['email'] ?? '';
    String councillorResponsibility = councillorInfo?['responsibility'] ?? '';
    String councillorParty = councillorInfo?['party'] ?? '';
    String councillorPhoto = councillorInfo?['photo'] ?? '';

    final wardData = maduraiWards[displayName] ?? maduraiWards[wardName];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Ward $wardNo',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (wardData != null) ...[
                          if (wardData.description != null && wardData.description!.isNotEmpty) ...[
                            _buildSectionHeader('Description'),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Text(
                                wardData.description!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _buildSectionHeader('Areas'),
                          _buildListSection(wardData.areas),
                          const SizedBox(height: 16),
                          _buildSectionHeader('Facilities'),
                          _buildListSection(wardData.facilities),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[100]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.people, color: Colors.red[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Population: ${wardData.population}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.red[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (councillorName != 'No councillor details available') ...[
                          const Divider(height: 24),
                          _buildSectionHeader('Councillor Information'),
                          const SizedBox(height: 16),
                          if (councillorPhoto.isNotEmpty)
                            Center(
                              child: Container(
                                height: 180,
                                width: 180,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.red, width: 2),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        councillorPhoto,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Container(
                                            color: Colors.grey[200],
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded /
                                                        loadingProgress.expectedTotalBytes!
                                                    : null,
                                                strokeWidth: 2,
                                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey[200],
                                            child: const Icon(Icons.person, size: 100, color: Colors.grey),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          _buildInfoCard([
                            _buildInfoRow(Icons.person, 'Name', councillorName),
                            if (councillorParty.isNotEmpty)
                              _buildInfoRow(Icons.flag, 'Party', councillorParty),
                            if (councillorAddress.isNotEmpty)
                              _buildInfoRow(Icons.location_on, 'Address', councillorAddress),
                            if (councillorContact.isNotEmpty)
                              _buildInfoRow(Icons.phone, 'Contact', councillorContact),
                            if (councillorEmail.isNotEmpty)
                              _buildInfoRow(Icons.email, 'Email', councillorEmail),
                            if (councillorResponsibility.isNotEmpty)
                              _buildInfoRow(Icons.work, 'Responsibility', councillorResponsibility),
                          ]),
                        ] else ...[
                          const Divider(height: 24),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.info_outline, size: 36, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                Text(
                                  'No councillor details available',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isSearching = false;
                            _searchSuggestions = [];
                          });
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: const Text(
                          'Close',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.red,
        ),
      ),
    );
  }

  Widget _buildListSection(List<dynamic> items) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.circle, size: 8, color: Colors.red[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.toString(),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.red[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      _removeOverlay();
      return;
    }

    // Filter ward names based on search query
    final suggestions = _displayNames.where((name) {
      final wardIndex = _displayNames.indexOf(name);
      final wardNo = _wardNumbers[wardIndex];
      return name.toLowerCase().contains(query) ||
          wardNo.toLowerCase().contains(query);
    }).toList();

    setState(() {
      _searchSuggestions = suggestions;
      _isSearching = true;
    });

    _showSuggestions();
  }

  void _showSuggestions() {
    _removeOverlay();

    if (_searchSuggestions.isEmpty) return;

    final RenderBox? searchBarBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (searchBarBox == null) return;

    final searchBarHeight = searchBarBox.size.height;
    final searchBarPosition = searchBarBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: searchBarPosition.dy + searchBarHeight + 4,
        left: 20,
        right: 16,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shrinkWrap: true,
              itemCount: _searchSuggestions.length,
              itemBuilder: (context, index) {
                final wardName = _searchSuggestions[index];
                final wardIndex = _displayNames.indexOf(wardName);
                final wardNo = _wardNumbers[wardIndex];
                return InkWell(
                  onTap: () {
                    _searchController.text = wardName;
                    _zoomToWard(wardIndex);
                    _removeOverlay();
                    setState(() {
                      _isSearching = false;
                      _searchSuggestions = [];
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey[200]!,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Ward $wardNo',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            wardName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _zoomToWard(int wardIndex) {
    if (_mapService.mapController == null || wardIndex < 0 || wardIndex >= _mapService.polygons.length) return;

    final polygon = _mapService.polygons.elementAt(wardIndex);
    final points = polygon.points;

    // Calculate bounds for the ward
    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (var point in points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapService.mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
      duration: const Duration(milliseconds: 500),
    );
  }

  void _zoomIn() {
    _mapService.mapController?.animateCamera(
      CameraUpdate.zoomIn(),
      duration: const Duration(milliseconds: 300),
    );
  }

  void _zoomOut() {
    _mapService.mapController?.animateCamera(
      CameraUpdate.zoomOut(),
      duration: const Duration(milliseconds: 300),
    );
  }

  void _resetView() {
    if (_mapService.mapBounds != null) {
      _mapService.mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(_mapService.mapBounds!, 50),
        duration: const Duration(milliseconds: 500),
      );
    } else {
      // If bounds are not set, reset to initial position
      _mapService.mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _maduraiCenter,
            zoom: 12.0,
          ),
        ),
        duration: const Duration(milliseconds: 500),
      );
    }
  }

  Future<void> _setMapStyle() async {
    String style = '''
      [
        {
          "featureType": "all",
          "elementType": "labels",
          "stylers": [
            {
              "visibility": "off"
            }
          ]
        }
      ]
    ''';
    if (_mapService.mapController != null) {
      await _mapService.mapController!.setMapStyle(style);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() {
                _isSearching = false;
                _searchSuggestions = [];
              });
              _removeOverlay();
            },
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _maduraiCenter,
                zoom: 12.0,
              ),
              onMapCreated: (GoogleMapController controller) async {
                _mapService.setMapController(controller);
                await _setMapStyle();
                if (!_mapService.isMapReady) {
                  _loadGeoJSON();
                  _loadCouncillorHtml();
                }
              },
              onCameraMove: (CameraPosition position) {
                _mapService.setCurrentZoom(position.zoom);
                _updateMarkerVisibility();
              },
              onCameraIdle: () {
                // Ensure the map is fully rendered before hiding the loading indicator
                if (_mapService.isLoading && _mapService.polygons.isNotEmpty) {
                  setState(() {
                    _mapService.setLoading(false);
                  });
                }
              },
              polygons: _mapService.polygons,
              markers: _mapService.wardLabels,
              onTap: (LatLng point) {
                _removeOverlay();
                setState(() {
                  _isSearching = false;
                });
                _handleMapTap(point);
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              mapType: MapType.normal,
              compassEnabled: true,
              tiltGesturesEnabled: true,
              rotateGesturesEnabled: true,
              scrollGesturesEnabled: true,
              zoomGesturesEnabled: true,
              buildingsEnabled: false,
              trafficEnabled: false,
              indoorViewEnabled: false,
              minMaxZoomPreference: const MinMaxZoomPreference(5, 20),
            ),
          ),
          if (_mapService.isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Loading ward boundaries...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 55,
            left: 20,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Logout button on the left
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    onPressed: _signOut,
                    tooltip: 'Logout',
                    color: Colors.red,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
                // Search bar on the right
                Expanded(
                  child: Container(
                    key: _searchBarKey,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search location...',
                        prefixIcon: Icon(Icons.search, color: Colors.red),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.only(right: 16, top: 14, bottom: 14),
                      ),
                      onSubmitted: _searchLocation,
                      onTap: () {
                        if (_searchController.text.isNotEmpty) {
                          _onSearchChanged();
                        }
                      },
                      onEditingComplete: () {
                        FocusScope.of(context).unfocus();
                        setState(() {
                          _isSearching = false;
                          _searchSuggestions = [];
                        });
                        _removeOverlay();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Zoom indicator with controls
          Positioned(
            top: 114,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.zoom_in,
                        size: 16,
                        color: _mapService.currentZoom >= _minZoomForLabels ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _mapService.currentZoom >= _minZoomForLabels ? 'Ward names visible' : 'Zoom in to see ward names',
                        style: TextStyle(
                          fontSize: 12,
                          color: _mapService.currentZoom >= _minZoomForLabels ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _zoomIn,
                        tooltip: 'Zoom In',
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _zoomOut,
                        tooltip: 'Zoom Out',
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _resetView,
                        tooltip: 'Reset View',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: const BottomToolbar(currentIndex: 1),
            ),
          ),
        ],
      ),
    );
  }

  void _updateMarkerVisibility() {
    if (_mapService.mapController == null) return;

    final Set<Marker> updatedMarkers = {};
    for (var marker in _mapService.wardLabels) {
      updatedMarkers.add(marker.copyWith(
        visibleParam: _mapService.currentZoom >= _minZoomForLabels,
      ));
    }

    setState(() {
      _mapService.setWardLabels(updatedMarkers);
    });
  }

  void _handleMapTap(LatLng point) {
    _removeOverlay();
    // Find the ward that contains the tapped point
    for (int i = 0; i < _mapService.polygons.length; i++) {
      if (_isPointInPolygon(point, _mapService.polygons.elementAt(i).points)) {
        _showWardDetails(i);
        break;
      }
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool isInside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * 
          (point.latitude - polygon[i].latitude) / 
          (polygon[j].latitude - polygon[i].latitude) + 
          polygon[i].longitude)) {
        isInside = !isInside;
      }
      j = i;
    }

    return isInside;
  }

  Future<void> _signOut() async {
    try {
      await SupabaseConfig.client.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const CombinedLoginPage()),
        );
      }
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;

    try {
      // You can implement location search logic here
      // For now, we'll just print the query
      print('Searching for: $query');
    } catch (e) {
      print('Error searching location: $e');
    }
  }

  TextBox _findLargestTextBox(List<LatLng> wardPoints) {
    if (wardPoints.isEmpty) return TextBox(LatLng(0, 0), 0, 0);

    // Get the bounding box of the ward
    double minLat = wardPoints.map((p) => p.latitude).reduce(min);
    double maxLat = wardPoints.map((p) => p.latitude).reduce(max);
    double minLng = wardPoints.map((p) => p.longitude).reduce(min);
    double maxLng = wardPoints.map((p) => p.longitude).reduce(max);

    // Convert to pixels (approximate)
    const double pixelsPerDegree = 100000.0;
    double maxWidth = 0;
    double maxHeight = 0;
    LatLng bestCenter = _calculateCentroid(wardPoints);

    // Grid search for the largest box
    const int gridSize = 20; // Increased grid size for better precision
    double latStep = (maxLat - minLat) / gridSize;
    double lngStep = (maxLng - minLng) / gridSize;

    for (int i = 0; i <= gridSize; i++) {
      for (int j = 0; j <= gridSize; j++) {
        LatLng testCenter = LatLng(
          minLat + i * latStep,
          minLng + j * lngStep,
        );

        if (!_isPointInPolygon(testCenter, wardPoints)) continue;

        // Find maximum width at this center
        double width = 0;
        double step = 0.0001;
        for (double offset = 0; offset < 0.01; offset += step) {
          LatLng rightPoint = LatLng(testCenter.latitude, testCenter.longitude + offset);
          LatLng leftPoint = LatLng(testCenter.latitude, testCenter.longitude - offset);
          
          if (!_isPointInPolygon(rightPoint, wardPoints) || 
              !_isPointInPolygon(leftPoint, wardPoints)) {
            width = offset * 2;
            break;
          }
        }

        // Find maximum height at this center
        double height = 0;
        for (double offset = 0; offset < 0.01; offset += step) {
          LatLng topPoint = LatLng(testCenter.latitude + offset, testCenter.longitude);
          LatLng bottomPoint = LatLng(testCenter.latitude - offset, testCenter.longitude);
          
          if (!_isPointInPolygon(topPoint, wardPoints) || 
              !_isPointInPolygon(bottomPoint, wardPoints)) {
            height = offset * 2;
            break;
          }
        }

        // Calculate area of this box
        double area = width * height;
        double maxArea = maxWidth * maxHeight;

        // Update if this box is larger
        if (area > maxArea) {
          maxWidth = width;
          maxHeight = height;
          bestCenter = testCenter;
        }
      }
    }

    // Convert to pixels
    return TextBox(
      bestCenter,
      maxWidth * pixelsPerDegree,
      maxHeight * pixelsPerDegree,
    );
  }

  Future<BitmapDescriptor> _createCustomMarkerIcon(String text, double maxWidth, double maxHeight) async {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    
    // Create text painter with max width constraint
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    );
    
    // Layout with max width constraint
    textPainter.layout(maxWidth: maxWidth);
    
    // Draw text
    textPainter.paint(
      canvas,
      Offset(0, 0),
    );
    
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(textPainter.width.toInt(), textPainter.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  bool _isLabelInWard(LatLng labelPosition, List<LatLng> wardPoints) {
    // Convert text dimensions to approximate lat/lng offsets
    // This is a rough approximation - you may need to adjust these values
    const double pixelsPerDegree = 100000.0; // Approximate pixels per degree at zoom level 13
    const double textWidth = 200.0; // Max width from _createCustomMarkerIcon
    const double textHeight = 28.0; // Approximate height for font size 20
    
    double latOffset = textHeight / pixelsPerDegree;
    double lngOffset = textWidth / pixelsPerDegree;
    
    // Check if all corners of the text box are within the ward
    List<LatLng> textCorners = [
      labelPosition, // Top-left
      LatLng(labelPosition.latitude, labelPosition.longitude + lngOffset), // Top-right
      LatLng(labelPosition.latitude - latOffset, labelPosition.longitude), // Bottom-left
      LatLng(labelPosition.latitude - latOffset, labelPosition.longitude + lngOffset), // Bottom-right
    ];
    
    // Check if all corners are within the ward
    return textCorners.every((corner) => _isPointInPolygon(corner, wardPoints));
  }
}