import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'data/ward_data.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'config/supabase_config.dart';
import 'Screens/login.dart';
import 'Screens/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Screens/splash_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'services/map_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/config.dart';

class TextBox {
  final LatLng center;
  final double width;
  final double height;

  const TextBox(this.center, this.width, this.height);
}

// Add a global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await SupabaseConfig.initialize();
    
    // Initialize deep link handling
    final appLinks = AppLinks();
    final initialUri = await appLinks.getInitialAppLink();
    
    // Set up deep link listener
    appLinks.uriLinkStream.listen((uri) {
      print('Got URI: $uri');
      // The deep link will be handled by the MapPage when it's created
    }, onError: (err) {
      print('Error handling deep link: $err');
    });

    runApp(MyApp(initialDeepLink: initialUri));
  } catch (e) {
    print('Error initializing Supabase: $e');
    // You might want to show an error screen here
    runApp(MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Madurai',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: Scaffold(
        body: Center(
          child: Text('Failed to initialize app: $e'),
        ),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  final Uri? initialDeepLink;
  
  const MyApp({super.key, this.initialDeepLink});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Madurai',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: SplashScreen(initialDeepLink: initialDeepLink),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final Uri? initialDeepLink;
  
  const AuthWrapper({super.key, this.initialDeepLink});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: SupabaseConfig.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final session = snapshot.data!.session;
          if (session != null) {
            return MapPage(initialDeepLink: initialDeepLink);
          }
        }
        return const CombinedLoginPage();
      },
    );
  }
}

class MapPage extends StatefulWidget {
  final Uri? initialDeepLink;
  
  const MapPage({super.key, this.initialDeepLink});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  final MapService _mapService = MapService();
  GoogleMapController? _mapController;
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

  // Add for Google Places API
  final String _placesApiKey = Config.googleMapsApiKey;

  // Enhanced ward colors with better visibility and contrast
  final List<Color> _wardColors = [
    const Color(0xFFE3F2FD).withOpacity(0.7), // Light Blue
    const Color(0xFFE8F5E9).withOpacity(0.7), // Light Green
    const Color(0xFFF3E5F5).withOpacity(0.7), // Light Purple
    const Color(0xFFFFEBEE).withOpacity(0.7), // Light Red
    const Color(0xFFFFF3E0).withOpacity(0.7), // Light Orange
    const Color(0xFFE0F7FA).withOpacity(0.7), // Light Cyan
    const Color(0xFFF1F8E9).withOpacity(0.7), // Light Lime
    const Color(0xFFFCE4EC).withOpacity(0.7), // Light Pink
    const Color(0xFFEFEBE9).withOpacity(0.7), // Light Brown
    const Color(0xFFE8EAF6).withOpacity(0.7), // Light Indigo
    const Color(0xFFF9FBE7).withOpacity(0.7), // Light Yellow
    const Color(0xFFE0F2F1).withOpacity(0.7), // Light Teal
    const Color(0xFFF5F5F5).withOpacity(0.7), // Light Grey
    const Color(0xFFEDE7F6).withOpacity(0.7), // Light Deep Purple
    const Color(0xFFE8F5E9).withOpacity(0.7), // Light Green
    const Color(0xFFE0F7FA).withOpacity(0.7), // Light Cyan
    const Color(0xFFF3E5F5).withOpacity(0.7), // Light Purple
    const Color(0xFFFFEBEE).withOpacity(0.7), // Light Red
    const Color(0xFFFFF3E0).withOpacity(0.7), // Light Orange
    const Color(0xFFE3F2FD).withOpacity(0.7), // Light Blue
  ];

  // Add stroke colors for better contrast
  final List<Color> _wardStrokeColors = [
    const Color(0xFF1976D2).withOpacity(0.9), // Blue
    const Color(0xFF388E3C).withOpacity(0.9), // Green
    const Color(0xFF7B1FA2).withOpacity(0.9), // Purple
    const Color(0xFFD32F2F).withOpacity(0.9), // Red
    const Color(0xFFF57C00).withOpacity(0.9), // Orange
    const Color(0xFF0097A7).withOpacity(0.9), // Cyan
    const Color(0xFF7CB342).withOpacity(0.9), // Lime
    const Color(0xFFC2185B).withOpacity(0.9), // Pink
    const Color(0xFF5D4037).withOpacity(0.9), // Brown
    const Color(0xFF3F51B5).withOpacity(0.9), // Indigo
    const Color(0xFFFBC02D).withOpacity(0.9), // Yellow
    const Color(0xFF00796B).withOpacity(0.9), // Teal
    const Color(0xFF616161).withOpacity(0.9), // Grey
    const Color(0xFF512DA8).withOpacity(0.9), // Deep Purple
    const Color(0xFF388E3C).withOpacity(0.9), // Green
    const Color(0xFF0097A7).withOpacity(0.9), // Cyan
    const Color(0xFF7B1FA2).withOpacity(0.9), // Purple
    const Color(0xFFD32F2F).withOpacity(0.9), // Red
    const Color(0xFFF57C00).withOpacity(0.9), // Orange
    const Color(0xFF1976D2).withOpacity(0.9), // Blue
  ];

  // Custom HTTP client with DNS configuration
  final _httpClient = http.Client();

  // Add a GlobalKey for the search bar
  final GlobalKey _searchBarKey = GlobalKey();

  late AnimationController _animationController;
  late Animation<double> _animation;
  int _currentIndex = 0; // 0: Home, 1: Profile

  // Add these fields at the top of the class with other fields
  OverlayEntry? _infoWindowOverlay;
  LatLng? _selectedLocation;
  String? _selectedWardNumber;
  String? _selectedWardName;
  String? _selectedAddress;
  Position? _currentPosition;

  // Add this field at the top of the class with other fields
  final Map<String, BitmapDescriptor> _markerIconCache = {};

  @override
  void initState() {
    super.initState();
    if (_placesApiKey.isEmpty) {
      print('Warning: Google Maps API key is empty!');
    }
    _setupSearchController();
    
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // Handle initial deep link if present
    if (widget.initialDeepLink != null) {
      _handleDeepLink(widget.initialDeepLink!);
    }

    // Load data in background
    _initializeMapData();
  }

<<<<<<< HEAD
  void _setupSearchController() {
    _searchController.addListener(() {
      if (!mounted) return;
      if (_searchController.text.isNotEmpty) {
        _fetchAddressSuggestions(_searchController.text);
      } else {
        setState(() {
          _searchSuggestions = [];
          _isSearching = false;
        });
        _removeOverlay();
      }
    });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reset search state when returning to the page
    if (!_isSearching && _searchController.text.isNotEmpty) {
      _searchController.clear();
      setState(() {
        _searchSuggestions = [];
      });
      _removeOverlay();
    }
  }

=======
>>>>>>> ebf7864dde84d5747059aa320beaa0ae9b4b6a4f
  void _handleDeepLink(Uri uri) {
    print('Handling deep link: $uri');
    // Extract ward number from the URI if present
    final wardNumber = uri.queryParameters['ward'];
    if (wardNumber != null) {
      // Find the ward index by ward number
      final wardIndex = _wardNumbers.indexOf(wardNumber);
      if (wardIndex != -1) {
        // Show ward details
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showWardDetails(wardIndex);
        });
  }

  Future<void> _initializeMapData() async {
    // Load councillor data first as it's smaller
    await _loadCouncillorHtml();
    
    // Then load GeoJSON data
    if (!_mapService.isMapReady) {
      await _loadGeoJSON();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _removeOverlay();
    _removeInfoWindow();
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

      // Process features in batches
      const int batchSize = 5;
      for (int i = 0; i < features.length; i += batchSize) {
        final end = (i + batchSize < features.length) ? i + batchSize : features.length;
        final batch = features.sublist(i, end);
        
        for (var feature in batch) {
          try {
            final properties = feature['properties'];
            final wardName = properties['Name']?.toString() ?? 'Unknown Ward';
            final wardDescription = properties['Description']?.toString() ?? '';
            final wardNo = properties['Ward_No']?.toString() ?? '';
            
            String displayName = wardName;
            if (wardName.startsWith('WARD NO:') || wardName.startsWith('Ward')) {
              displayName = wardName.split(':').last.trim();
            }
            displayNames.add(displayName);
            wardNumbers.add(wardNo);
            
            final geometry = feature['geometry'];
            if (geometry['type'] != 'MultiPolygon') continue;

            final List<dynamic> polygons = geometry['coordinates'];
            final List<LatLng> allPoints = [];

            for (var polygon in polygons) {
              final List<dynamic> rings = polygon;
              if (rings.isEmpty) continue;

              final List<dynamic> outerRing = rings[0];
              for (var coord in outerRing) {
                if (coord is! List || coord.length < 2) continue;

                double? lng;
                double? lat;
                try {
                  lng = (coord[0] is num) ? coord[0].toDouble() : double.tryParse(coord[0].toString());
                  lat = (coord[1] is num) ? coord[1].toDouble() : double.tryParse(coord[1].toString());
                } catch (e) {
                  continue;
                }

                if (lng == null || lat == null || 
                    lat < -90 || lat > 90 || 
                    lng < -180 || lng > 180) continue;
                
                minLat = minLat < lat ? minLat : lat;
                maxLat = maxLat > lat ? maxLat : lat;
                minLng = minLng < lng ? minLng : lng;
                maxLng = maxLng > lng ? maxLng : lng;
                
                allPoints.add(LatLng(lat, lng));
              }
            }

            if (allPoints.isNotEmpty) {
              if (allPoints.first.latitude != allPoints.last.latitude || 
                  allPoints.first.longitude != allPoints.last.longitude) {
                allPoints.add(allPoints.first);
              }
              
              wardPoints.add(allPoints);
              wardNames.add(wardName);
              wardDescriptions.add(wardDescription);
            }
          } catch (e) {
            continue;
          }
        }

        // Update UI after each batch
        if (mounted) {
          setState(() {
            _wardNames = wardNames;
            _wardDescriptions = wardDescriptions;
            _displayNames = displayNames;
            _wardNumbers = wardNumbers;
          });
        }
      }

      if (wardPoints.isEmpty) return;

      _mapBounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      // Create polygons and boundaries in batches
      final List<Color> colors = _colorWards(wardPoints);
      final Set<Polygon> loadedPolygons = {};
      final Set<Polyline> loadedBoundaries = {};
      final Set<Marker> loadedLabels = {};

      for (int i = 0; i < wardPoints.length; i += batchSize) {
        final end = (i + batchSize < wardPoints.length) ? i + batchSize : wardPoints.length;
        
        for (int j = i; j < end; j++) {
          try {
            // Create polygon with transparent stroke and lower z-index
            final polygon = Polygon(
              polygonId: PolygonId('ward_$j'),
              points: wardPoints[j],
              fillColor: colors[j],
              strokeColor: Colors.transparent,
              strokeWidth: 0,
              zIndex: 1, // Lower z-index for polygons
            );
            loadedPolygons.add(polygon);

            // Create boundary with higher z-index and slim stroke
            final boundary = Polyline(
              polylineId: PolylineId('boundary_$j'),
              points: wardPoints[j],
              color: _wardStrokeColors[j % _wardStrokeColors.length],
              width: 1, // Slimmer width
              patterns: [PatternItem.dash(3), PatternItem.gap(3)], // Smaller dash pattern
              zIndex: 2, // Higher z-index for boundaries
            );
            loadedBoundaries.add(boundary);

            final textBox = _findLargestTextBox(wardPoints[j]);
            final customIcon = await _createCustomMarkerIcon(displayNames[j], textBox.width, textBox.height);
            final label = Marker(
              markerId: MarkerId('label_$j'),
              position: textBox.center,
              infoWindow: InfoWindow(
                title: displayNames[j],
              ),
              visible: _currentZoom >= _minZoomForLabels,
              icon: customIcon,
              anchor: const Offset(0.5, 0.5),
              onTap: () {
                _showWardDetails(j);
              },
              zIndex: 3, // Highest z-index for labels
            );
            loadedLabels.add(label);
          } catch (e) {
            continue;
          }
        }

        // Update map after each batch
        if (mounted) {
          setState(() {
            _mapService.setPolygons(loadedPolygons);
            _mapService.setWardBoundaries(loadedBoundaries);
            _mapService.setWardLabels(loadedLabels);
          });
        }
      }

      if (_mapService.mapController != null) {
        await _mapService.mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(_mapBounds!, 50),
          duration: const Duration(milliseconds: 500),
        );
      }
      
      if (mounted) {
        setState(() {
          _mapService.setLoading(false);
        });
      }
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
      debugPrint('Row has ${cells.length} cells');
      
      if (cells.length >= 8) {
        final wardNoRaw = cells[0].text.trim();
        debugPrint('Raw ward number text: "$wardNoRaw"');
        
        // Handle different formats of ward numbers
        final wardNo = wardNoRaw
            .replaceAll(RegExp(r'[^0-9]'), '') // Remove all non-numeric characters
            .trim();
        
        debugPrint('Processed ward number: "$wardNo"');
        
        final name = cells[1].text.trim();
        final address = cells[2].text.trim();
        final contact = cells[3].text.trim();
        final email = cells[4].text.trim();
        final responsibility = cells[5].text.trim();
        final party = cells[6].text.trim();
        final photo = cells[7].querySelector('img')?.attributes['src'] ?? '';

        if (wardNo.isNotEmpty) {
          debugPrint('Adding data for ward $wardNo:');
          debugPrint('- Name: $name');
          debugPrint('- Party: $party');
          debugPrint('- Photo URL: $photo');
          
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
          debugPrint('Failed to parse ward number from: $wardNoRaw');
        }
      } else {
        debugPrint('Row has insufficient cells: ${cells.length}');
        if (cells.isNotEmpty) {
          debugPrint('First cell content: ${cells[0].text.trim()}');
        }
      }
    }
    
    debugPrint('\nFinal councillor data summary:');
    debugPrint('Total entries: ${_councillorData.length}');
    debugPrint('Available ward numbers: ${_councillorData.keys.join(', ')}');
    
    // Check specifically for ward 48
    if (_councillorData.containsKey('48')) {
      debugPrint('\nWard 48 data found:');
      debugPrint(_councillorData['48'].toString());
    } else {
      debugPrint('\nWard 48 data NOT found in _councillorData');
    }
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
    debugPrint('Dialog for wardNo: $wardNo, councillorInfo: $councillorInfo');
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
    _fetchAddressSuggestions(_searchController.text);
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
                final address = _searchSuggestions[index];
                return InkWell(
                  onTap: () async {
                    _searchController.text = address;
                    await _searchLocation(address);
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
                        const Icon(Icons.location_on, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            address,
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
    // Clear search markers when resetting the view
    _mapService.clearSearchMarkers();
    
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
        },
        {
          "featureType": "administrative",
          "elementType": "geometry",
          "stylers": [
            {
              "visibility": "off"
            }
          ]
        },
        {
          "featureType": "poi",
          "stylers": [
            {
              "visibility": "off"
            }
          ]
        },
        {
          "featureType": "road",
          "elementType": "labels",
          "stylers": [
            {
              "visibility": "off"
            }
          ]
        },
        {
          "featureType": "transit",
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
      drawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.5,
        child: Container(
          color: Colors.white,
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(
                  color: Colors.red,
                ),
                child: const Center(
                  child: Text(
                    'Madurai',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home, color: Colors.red),
                title: const Text('Home'),
                onTap: () {
                  Navigator.pop(context);
                  _resetView();
                },
              ),
              ListTile(
                leading: const Icon(Icons.person, color: Colors.red),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    CupertinoPageRoute(builder: (context) => const ProfilePage()),
                  );
                },
              ),
              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(context);
                  _signOut();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
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
              onMapCreated: (controller) {
                debugPrint('Map created with ${_mapService.wardBoundaries.length} boundaries');
                _onMapCreated(controller);
              },
              onCameraMove: (CameraPosition position) {
                _mapService.setCurrentZoom(position.zoom);
                _updateMarkerVisibility();
              },
              onCameraIdle: () {
                if (_mapService.isLoading && _mapService.polygons.isNotEmpty) {
                  setState(() {
                    _mapService.setLoading(false);
                  });
                }
              },
              polygons: _mapService.polygons,
              polylines: _mapService.wardBoundaries,
              markers: {..._mapService.wardLabels, ..._mapService.searchMarkers},
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
          // Zoom controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 80,
            right: 10,
            child: Column(
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
                    iconSize: 24,
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
                    iconSize: 24,
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
                    iconSize: 24,
                  ),
                ),
              ],
            ),
          ),
          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 10,
            right: 10,
            child: Row(
              children: [
                // Menu button
                Container(
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
                  child: Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu, color: Colors.red),
                      onPressed: () {
                        Scaffold.of(context).openDrawer();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Search bar
                Expanded(
                  child: Container(
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
                        hintText: 'Search for a location in Madurai',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(Icons.search, color: Colors.red),
                        suffixIcon: AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.my_location, color: Colors.red),
                                onPressed: _getCurrentLocation,
                                tooltip: 'Use current location',
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.red),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchSuggestions = [];
                                      _isSearching = false;
                                    });
                                    _removeOverlay();
                                  },
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      onTap: () {
                        if (_searchController.text.isNotEmpty) {
                          _fetchAddressSuggestions(_searchController.text);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search suggestions - moved to the end of the Stack to appear on top
          if (_isSearching && _searchSuggestions.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 10,
              right: 10,
              child: Container(
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
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _searchSuggestions.length,
                  itemBuilder: (context, index) {
                    return InkWell(
                      onTap: () {
                        _searchLocation(_searchSuggestions[index]);
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
                            const Icon(Icons.location_on, color: Colors.red, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _searchSuggestions[index],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
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
    _removeInfoWindow();
    // Clear search markers when tapping on the map
    _mapService.clearSearchMarkers();
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

  Future<void> _searchLocation(String address) async {
    if (!mounted) return;
    _mapService.clearSearchMarkers();
    
    final apiKey = _placesApiKey;
    if (apiKey.isEmpty) {
      print('Error: Cannot search location - API key is empty');
      return;
    }

    try {
      final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$apiKey'
      ));
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data["status"] == "OK" && 
          data["results"] != null && 
          data["results"] is List && 
          data["results"].isNotEmpty &&
          data["results"][0] is Map &&
          data["results"][0]["geometry"] is Map &&
          data["results"][0]["geometry"]["location"] is Map) {
        
        final location = data["results"][0]["geometry"]["location"];
        final lat = location["lat"];
        final lng = location["lng"];
        
        if (lat == null || lng == null) {
          throw Exception('Invalid location data received from API');
        }
        
        final searchLocation = LatLng(lat.toDouble(), lng.toDouble());
          }
        }

        if (!isInMadurai) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This location is outside of Madurai city limits',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
          return;
        }

        final customIcon = await _createCustomSearchMarker(wardNumber, wardName, address);
        if (!mounted) return;

        final marker = Marker(
          markerId: const MarkerId('search_location'),
          position: searchLocation,
          icon: customIcon,
          anchor: const Offset(0.5, 1.0),
          zIndex: 1000.0,
        );

        _mapService.addSearchMarker(marker);

        setState(() {
          _searchSuggestions = [];
          _isSearching = false;
          _searchController.clear();
        });

        if (_mapController != null) {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(searchLocation, 15),
          );
        }

        _removeOverlay();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location not found. Try again.")),
        );
      }
    } catch (e) {
      print('Error geocoding address: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error searching location: $e")),
      );
    }
  }

  Future<BitmapDescriptor> _createCustomSearchMarker(String? wardNumber, String? wardName, String address) async {
    final cacheKey = '${wardNumber}_${wardName}_$address';
    if (_markerIconCache.containsKey(cacheKey)) {
      return _markerIconCache[cacheKey]!;
    }

    const double width = 600.0;
    const double height = 240.0;
    const double pinHeight = 120.0;
    const double totalHeight = height + pinHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw info window background
    final rrect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(24),
    );
    canvas.drawRRect(rrect, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;
    canvas.drawRRect(rrect, borderPaint);

    // Draw pin
    final pinPath = Path()
      ..moveTo(width / 2 - 30, height)
      ..lineTo(width / 2, height + pinHeight)
      ..lineTo(width / 2 + 30, height)
      ..close();
    canvas.drawPath(pinPath, paint);
    canvas.drawPath(pinPath, borderPaint);

    // Draw ward number if available
    if (wardNumber != null) {
      final wardTextPainter = TextPainter(
        text: TextSpan(
          text: 'Ward $wardNumber',
          style: const TextStyle(
            color: Colors.red,
            fontSize: 38,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      wardTextPainter.layout();
      wardTextPainter.paint(
        canvas,
        Offset(24, 24),
      );
    }

    // Draw ward name
    final nameTextPainter = TextPainter(
      text: TextSpan(
        text: wardName ?? '',
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    nameTextPainter.layout(maxWidth: width - 48);
    nameTextPainter.paint(
      canvas,
      Offset(24, wardNumber != null ? 84 : 24),
    );

    // Draw address
    final addressTextPainter = TextPainter(
      text: TextSpan(
        text: address,
        style: const TextStyle(
          fontSize: 28,
          color: Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    );
    addressTextPainter.layout(maxWidth: width - 48);
    addressTextPainter.paint(
      canvas,
      Offset(24, wardNumber != null ? 132 : 72),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), totalHeight.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final descriptor = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    
    // Cache the result
    _markerIconCache[cacheKey] = descriptor;
    
    return descriptor;
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
    // Check cache first
    if (_markerIconCache.containsKey(text)) {
      return _markerIconCache[text]!;
    }

    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    
    // Find the ward number for this ward name
    int wardIndex = _displayNames.indexOf(text);
    String wardNumber = wardIndex >= 0 ? _wardNumbers[wardIndex] : '';
    
    // Split the ward name into words
    List<String> words = text.split(' ');
    
    // Create text painter with max width constraint
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          if (wardNumber.isNotEmpty) ...[
            TextSpan(
              text: 'Ward $wardNumber\n',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          ...words.map((word) => TextSpan(
            text: '$word\n',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.normal,
            ),
          )).toList(),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: words.length + (wardNumber.isNotEmpty ? 1 : 0),
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
    
    final descriptor = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    
    // Cache the result
    _markerIconCache[text] = descriptor;
    
    return descriptor;
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

  Future<void> _fetchAddressSuggestions(String query) async {
    if (!mounted) return;
    if (query.isEmpty) {
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      _removeOverlay();
      return;
    }

    final apiKey = _placesApiKey;
    if (apiKey.isEmpty) {
      print('Error: Cannot fetch address suggestions - API key is empty');
      if (!mounted) return;
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      _removeOverlay();
      return;
    }

    try {
      final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}&key=$apiKey&components=country:in'
      ));
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data["status"] == "OK" && data["predictions"] != null && data["predictions"] is List) {
        final predictions = data["predictions"] as List;
        setState(() {
          _searchSuggestions = predictions
              .where((prediction) => prediction is Map && prediction["description"] != null)
              .map((prediction) => prediction["description"].toString())
              .toList();
          _isSearching = true;
        });
        _showSuggestions();
      } else {
        setState(() {
          _searchSuggestions = [];
          _isSearching = false;
        });
        _removeOverlay();
      }
    } catch (e) {
      print('Error fetching address suggestions: $e');
      if (!mounted) return;
      setState(() {
        _searchSuggestions = [];
        _isSearching = false;
      });
      _removeOverlay();
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _mapService.setMapController(controller);
    _setMapStyle();
    
    // Only load data if not already loaded
    if (!_mapService.isMapReady) {
      _initializeMapData();
    }
    
    // Clear any existing search markers when map is created/reloaded
    _mapService.clearSearchMarkers();
  }

  // Update the _showCustomInfoWindow method to handle async screen coordinate
  void _showCustomInfoWindow(LatLng position, String? wardNumber, String? wardName, String address) async {
    _removeInfoWindow();
    
    _selectedLocation = position;
    _selectedWardNumber = wardNumber;
    _selectedWardName = wardName;
    _selectedAddress = address;

    if (_mapController == null) return;

    final ScreenCoordinate screenCoordinate = await _mapController!.getScreenCoordinate(position);
    final double x = screenCoordinate.x.toDouble();
    final double y = screenCoordinate.y.toDouble();

    // Position the info window relative to the marker pin
    final double infoWindowHeight = 100.0;
    final double pinHeight = 40.0;
    final double infoWindowWidth = 200.0;
    
    double left = x - (infoWindowWidth / 2);
    double top = y - infoWindowHeight - pinHeight;

    _infoWindowOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: infoWindowWidth,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (wardNumber != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red[100]!),
                    ),
                    child: Text(
                      'Ward $wardNumber',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  wardName ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (mounted) {
      Overlay.of(context).insert(_infoWindowOverlay!);
    }
  }

  void _removeInfoWindow() {
    _infoWindowOverlay?.remove();
    _infoWindowOverlay = null;
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission permanently denied. Please enable in settings.'),
          ),
        );
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
      });

      // Get address from coordinates
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
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

        _searchController.text = address;
        await _searchLocation(address);
      }
    } catch (e) {
      print('Error getting current location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting current location: $e')),
      );
    }
  }
}

class SplashScreen extends StatelessWidget {
  final Uri? initialDeepLink;
  
  const SplashScreen({super.key, this.initialDeepLink});

  @override
  Widget build(BuildContext context) {
    return AuthWrapper(initialDeepLink: initialDeepLink);
  }
}