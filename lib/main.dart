import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'config/supabase_config.dart';
import 'Screens/login.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'Screens/splash_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'services/map_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'config/config.dart';
import 'package:flutter/widgets.dart';
import 'main.dart' show routeObserver; // Import the RouteObserver

// Add this at the top-level, before main()
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

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
      navigatorObservers: [routeObserver], // <-- Add this line
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

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
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

  // Add for Google Places API
  final String _placesApiKey = Config.googleMapsApiKey;

  // Add flag to track navigation state
  bool _isReturningFromNavigation = false;

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
    // Add observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    if (_placesApiKey.isEmpty) {
      print('Warning: Google Maps API key is empty!');
    }
    
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App has become active again, ensure map data is loaded
      print('App resumed, checking map data...');
      if (_mapService.polygons.isEmpty) {
        print('Polygons are empty on app resume, reinitializing...');
        _initializeMapData();
      }
    }
  }

  void _setupSearchController() {
    // Function removed - search functionality disabled
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to RouteObserver
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
    
    // Reinitialize map data when returning to the page to ensure polygons and ward data are loaded
    // This fixes the issue where location search shows "outside Madurai city limits" after navigation
    if (_mapService.isMapReady && _mapService.polygons.isEmpty) {
      print('Reinitializing map data on page re-entry...');
      _initializeMapData();
    }
    
    // If map controller exists but polygons are empty, reset and reinitialize
    if (_mapController != null && _mapService.polygons.isEmpty) {
      print('Map controller exists but polygons are empty, resetting map state...');
      _mapService.resetMapState();
      _initializeMapData();
    }
  }

  void _handleDeepLink(Uri uri) {
    print('Handling deep link: $uri');
    // Extract ward number from the URI if present
    final wardNumber = uri.queryParameters['ward'];
    if (wardNumber != null) {
      // Find the ward index by ward number
      final wardIndex = _wardNumbers.indexOf(wardNumber);
      if (wardIndex != -1) {
        // Ward dialog functionality removed
      }
    }
  }

  Future<void> _initializeMapData() async {
    print('Initializing map data...');
    
    // Always load GeoJSON data to ensure polygons are available for location search
    // This fixes the issue where location search fails after navigation
    await _loadGeoJSON();
    print('Map data initialization completed');
  }

  @override
  void dispose() {
    // Remove observer to prevent memory leaks
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this); // Unsubscribe from RouteObserver
    _animationController.dispose();
    _removeInfoWindow();
    _httpClient.close();
    // Don't dispose the map controller here as it's managed by MapService
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when coming back to this page (e.g., from Profile)
    _initializeMapData();
    setState(() {}); // Ensure UI updates if needed
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
    if (points.isEmpty) return const LatLng(0, 0);
    
    double sumLat = 0;
    double sumLng = 0;
    
    for (final point in points) {
      sumLat += point.latitude;
      sumLng += point.longitude;
    }
    
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  LatLng _findLabelPosition(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);

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
    // Ward dialog functionality removed
  }

  void _showSuggestions() {
    // Function removed - search functionality disabled
  }

  void _removeOverlay() {
    // Function removed - search functionality disabled
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

  void _setMapStyle() {
    print('Setting custom map style to hide default labels...');
    
    const String mapStyle = '''
    [
      {
        "featureType": "administrative",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "administrative",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "administrative",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "administrative",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "poi",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "poi",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "poi",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "poi",
        "elementType": "labels.text.stroke",
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
        "featureType": "road",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "labels.icon",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels.icon",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.natural",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.natural",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.natural",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.natural",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.man_made",
        "elementType": "labels",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.man_made",
        "elementType": "labels.text",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.man_made",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "landscape.man_made",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      }
    ]
    ''';
    
    if (_mapController != null) {
      _mapController!.setMapStyle(mapStyle);
      print('Custom map style applied successfully');
    } else {
      print('Map controller not available for style setting');
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
              ],
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
        // Ward dialog functionality removed
        break;
      }
    }
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * 
           (point.latitude - polygon[i].latitude) / 
           (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        inside = !inside;
      }
      j = i;
    }
    
    return inside;
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
    // Function removed - search functionality disabled
  }

  Future<BitmapDescriptor> _createCustomSearchMarker(String? wardNumber, String? wardName, String address) async {
    // Function removed - search functionality disabled
    return BitmapDescriptor.defaultMarker;
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
    // Function removed - search functionality disabled
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _mapService.setMapController(controller);
    _setMapStyle();
    
    // Always reinitialize map data to ensure polygons are available for location search
    // This fixes the issue where location search fails after navigation
    _initializeMapData();
    
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
    // Function removed - search functionality disabled
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