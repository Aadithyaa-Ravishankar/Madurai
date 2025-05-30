import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'data/ward_data.dart'; // Add this import
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as htmlParser;

void main() {
  runApp(const MyMapApp());
}

class MyMapApp extends StatelessWidget {
  const MyMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Madurai Ward Map',
      home: const MapPage(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final List<Polygon> _polygons = [];
  final List<Marker> _wardLabels = [];
  final List<String> _wardNames = [];
  final List<String> _wardDescriptions = [];
  final List<String> _displayNames = [];
  final LatLng _maduraiCenter = const LatLng(9.9252, 78.1198);
  double _currentZoom = 10.0;
  LatLngBounds? _mapBounds;
  static const double _minZoomForLabels = 12.0; // Add this constant for minimum zoom level to show labels
  String _councillorHtml = '';

  // Enhanced ward colors with better visibility and contrast
  final List<Color> _wardColors = [
    Colors.red.withOpacity(0.3),
    Colors.blue.withOpacity(0.3),
    Colors.green.withOpacity(0.3),
    Colors.orange.withOpacity(0.3),
    Colors.purple.withOpacity(0.3),
    Colors.teal.withOpacity(0.3),
    Colors.pink.withOpacity(0.3),
    Colors.indigo.withOpacity(0.3),
    Colors.brown.withOpacity(0.3),
    Colors.cyan.withOpacity(0.3),
  ];

  // Custom HTTP client with DNS configuration
  final _httpClient = http.Client();

  @override
  void initState() {
    super.initState();
    _loadGeoJson();
    _loadCouncillorHtml();
    // Add initial zoom to Madurai
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(_maduraiCenter, 12.0); // Set initial zoom level to 12
    });
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  Future<void> _loadGeoJson() async {
    try {
      debugPrint("Loading GeoJSON data...");
      final String data = await rootBundle.loadString('assets/madurai_wards.geojson');
      final Map<String, dynamic> geoJson = json.decode(data);

      if (geoJson['features'] == null) {
        debugPrint("No features found in GeoJSON");
        return;
      }

      debugPrint("Found ${geoJson['features'].length} features in GeoJSON");

      final List<List<LatLng>> wardPoints = [];
      final List<String> wardNames = [];
      final List<String> wardDescriptions = [];
      final List<String> displayNames = [];
      int unnamedWardCount = 1;

      // Calculate bounds for coordinate scaling
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      // First pass: collect all points and calculate bounds
      for (var feature in geoJson['features']) {
        try {
          final properties = feature['properties'];
          String wardName = properties['Name']?.toString().trim() ?? 'Unnamed Ward ${unnamedWardCount++}';
          String wardDescription = properties['Description']?.toString().trim() ?? 'No description available';
          String wardNo = properties['Ward_No']?.toString().trim() ?? '';
          
          // Remove any existing ward number from the name
          wardName = wardName.replaceAll(RegExp(r'^Ward\s+\d+:\s*', caseSensitive: false), '');
          wardName = wardName.replaceAll(RegExp(r'^WARD\s+NO:\s*\d+\s*', caseSensitive: false), '');
          
          // Store original ward name for map display
          displayNames.add(wardName);
          
          // Add ward number to the name only for councillor lookup
          if (wardNo.isNotEmpty) {
            wardName = 'Ward $wardNo: $wardName';
          }
          
          debugPrint("\nProcessing ward: $wardName");
          debugPrint("Display name: ${displayNames.last}");
          
          final geometry = feature['geometry'];
          if (geometry == null || geometry['coordinates'] == null) {
            debugPrint("Skipping feature with null geometry");
            continue;
          }

          List<LatLng> points = [];
          if (geometry['type'] == 'MultiPolygon') {
            debugPrint("Found MultiPolygon geometry");
            final List<dynamic> multiPolygon = geometry['coordinates'];
            for (var polygon in multiPolygon) {
              for (var ring in polygon) {
                for (var coord in ring) {
                  if (coord is List && coord.length >= 2) {
                    double lat = coord[1] as double;
                    double lng = coord[0] as double;
                    
                    if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                      points.add(LatLng(lat, lng));
                      
                      minLat = minLat < lat ? minLat : lat;
                      maxLat = maxLat > lat ? maxLat : lat;
                      minLng = minLng < lng ? minLng : lng;
                      maxLng = maxLng > lng ? maxLng : lng;
                    } else {
                      debugPrint("Invalid coordinates for ward $wardName: lat=$lat, lng=$lng");
                    }
                  }
                }
              }
            }
          } else if (geometry['type'] == 'Polygon') {
            debugPrint("Found Polygon geometry");
            final List<dynamic> polygon = geometry['coordinates'];
            for (var ring in polygon) {
              for (var coord in ring) {
                if (coord is List && coord.length >= 2) {
                  double lat = coord[1] as double;
                  double lng = coord[0] as double;
                  
                  if (lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180) {
                    points.add(LatLng(lat, lng));
                    
                    minLat = minLat < lat ? minLat : lat;
                    maxLat = maxLat > lat ? maxLat : lat;
                    minLng = minLng < lng ? minLng : lng;
                    maxLng = maxLng > lng ? maxLng : lng;
                  } else {
                    debugPrint("Invalid coordinates for ward $wardName: lat=$lat, lng=$lng");
                  }
                }
              }
            }
          } else {
            debugPrint("Unsupported geometry type: ${geometry['type']}");
          }

          if (points.isNotEmpty) {
            // Ensure the polygon is closed
            if (points.first.latitude != points.last.latitude || 
                points.first.longitude != points.last.longitude) {
              points.add(points.first);
            }
            
            wardPoints.add(points);
            wardNames.add(wardName);  // This is used for councillor lookup
            wardDescriptions.add(wardDescription);
            debugPrint("Successfully added ward $wardName with ${points.length} points");
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
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );

      final List<Color> colors = _colorWards(wardPoints);
      final List<Polygon> loadedPolygons = [];
      final List<Marker> loadedLabels = [];

      // Second pass: create polygons with improved visibility settings
      for (int i = 0; i < wardPoints.length; i++) {
        try {
          final polygon = Polygon(
            points: wardPoints[i],
            color: colors[i],
            borderColor: Colors.black,
            borderStrokeWidth: 1.0,
            isFilled: true,
          );
          loadedPolygons.add(polygon);

          // Calculate centroid and add label
          final centroid = _calculateCentroid(wardPoints[i]);
          final label = Marker(
            point: centroid,
            width: 100,
            height: 40,
            child: Text(
              displayNames[i],  // Use displayNames instead of wardNames
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _currentZoom * 0.8,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          );
          loadedLabels.add(label);
        } catch (e) {
          debugPrint("Error creating polygon for ${wardNames[i]}: $e");
        }
      }

      setState(() {
        _polygons.clear();
        _polygons.addAll(loadedPolygons);
        _wardLabels.clear();
        _wardLabels.addAll(loadedLabels);
        _wardNames.clear();
        _wardNames.addAll(wardNames);
        _wardDescriptions.clear();
        _wardDescriptions.addAll(wardDescriptions);
        _displayNames.clear();
        _displayNames.addAll(displayNames);
      });

      // Add a small delay before adjusting camera bounds
      await Future.delayed(const Duration(milliseconds: 500));
      if (_mapBounds != null) {
        _mapController.fitBounds(_mapBounds!, options: const FitBoundsOptions(
          padding: EdgeInsets.all(100),
        ));
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
      final String html = await rootBundle.loadString('assets/councillor.html');
      setState(() {
        _councillorHtml = html;
      });
    } catch (e) {
      debugPrint('Error loading councillor HTML: $e');
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
    double area = 0;
    double cx = 0;
    double cy = 0;

    for (int i = 0; i < points.length - 1; i++) {
      double x1 = points[i].longitude;
      double y1 = points[i].latitude;
      double x2 = points[i + 1].longitude;
      double y2 = points[i + 1].latitude;

      double f = x1 * y2 - x2 * y1;
      area += f;
      cx += (x1 + x2) * f;
      cy += (y1 + y2) * f;
    }

    area = area / 2;
    cx = cx / (6 * area);
    cy = cy / (6 * area);

    return LatLng(cy, cx);
  }

  void _showWardDialog(BuildContext context, String wardName) {
    final wardData = maduraiWards[wardName] ?? WardData(
      name: wardName,
      code: 'N/A',
      areas: ['Information not available'],
      facilities: ['Information not available'],
      population: 'Not available',
      description: 'No information available for this ward',
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            '${wardData.name} (${wardData.code})',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wardData.description != null) ...[
                  Text(
                    wardData.description!,
                    style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 12),
                ],
                _buildDetailSection('Areas', wardData.areas),
                const SizedBox(height: 12),
                _buildDetailSection('Facilities', wardData.facilities),
                const SizedBox(height: 12),
                Text(
                  'Population: ${wardData.population}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailSection(String title, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title:',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            '• $item',
            style: const TextStyle(fontSize: 16),
          ),
        )).toList(),
      ],
    );
  }

  void _zoomIn() {
    _mapController.move(_mapController.center, _mapController.zoom + 1);
  }

  void _zoomOut() {
    _mapController.move(_mapController.center, _mapController.zoom - 1);
  }

  void _adjustCameraToBounds() {
    if (_mapBounds != null) {
      _mapController.fitBounds(_mapBounds!);
    }
  }

  void _showWardDetails(String wardName, String description) {
    // Extract ward number from ward name - improved extraction
    final wardNo = wardName.replaceAll(RegExp(r'[^0-9]'), '');
    debugPrint('Looking for ward number: $wardNo');
    
    if (wardNo.isEmpty) {
        debugPrint('Could not extract ward number from ward name: $wardName');
        showDialog(
            context: context,
            builder: (BuildContext context) {
                return AlertDialog(
                    title: Text(wardName),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(description.isEmpty ? 'No description available' : description),
                            const SizedBox(height: 16),
                            const Text(
                                'Councillor Information',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Could not find ward number. Please try again.'),
                        ],
                    ),
                    actions: [
                        TextButton(
                            onPressed: () {
                                Navigator.of(context).pop();
                            },
                            child: const Text('Close'),
                        ),
                    ],
                );
            },
        );
        return;
    }
    
    // Parse the HTML content
    final document = htmlParser.parse(_councillorHtml);
    
    // Get councillor information from the HTML table
    final rows = document.querySelectorAll('tr');
    Map<String, dynamic>? councillorInfo;
    
    for (var row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.isNotEmpty) {
            final cellText = cells[0].text.trim();
            debugPrint('Checking cell: $cellText');
            
            // Extract ward number from the cell text - handle "WARD NO: X" format
            final cellWardNo = cellText.replaceAll(RegExp(r'[^0-9]'), '');
            debugPrint('Cell ward number: $cellWardNo');
            
            // Compare the ward numbers
            if (cellWardNo == wardNo) {
                debugPrint('Found matching ward row for ward $wardNo');
                councillorInfo = {
                    'name': cells[1].text.trim(),
                    'address': cells[2].text.trim(),
                    'contact': cells[3].text.trim(),
                    'email': cells[4].text.trim(),
                    'responsibility': cells[5].text.trim(),
                    'party': cells[6].text.trim(),
                    'photo': cells[7].querySelector('img')?.attributes['src'],
                };
                break;
            }
        }
    }

    if (councillorInfo == null) {
        debugPrint('No councillor info found for ward $wardNo');
        showDialog(
            context: context,
            builder: (BuildContext context) {
                return AlertDialog(
                    title: Text('Ward $wardNo: $wardName'),
                    content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(description.isEmpty ? 'No description available' : description),
                            const SizedBox(height: 16),
                            const Text(
                                'Councillor Information',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                ),
                            ),
                            const SizedBox(height: 8),
                            const Text('No councillor information available for this ward.'),
                        ],
                    ),
                    actions: [
                        TextButton(
                            onPressed: () {
                                Navigator.of(context).pop();
                            },
                            child: const Text('Close'),
                        ),
                    ],
                );
            },
        );
        return;
    }

    final name = councillorInfo['name'] as String? ?? 'N/A';
    final address = councillorInfo['address'] as String? ?? 'N/A';
    final contact = councillorInfo['contact'] as String? ?? 'N/A';
    final email = councillorInfo['email'] as String?;
    final responsibility = councillorInfo['responsibility'] as String? ?? 'N/A';
    final party = councillorInfo['party'] as String? ?? 'N/A';
    final photo = councillorInfo['photo'] as String?;

    // Strip any leading 'WARD NO:' or 'Ward' prefix from wardName
    final cleanWardName = wardName.replaceAll(RegExp(r'^(WARD\s+NO:|Ward\s+\d+:)\s*', caseSensitive: false), '');

    showDialog(
        context: context,
        builder: (BuildContext context) {
            return AlertDialog(
                title: Text('Ward $wardNo: $cleanWardName'),
                content: SingleChildScrollView(
                    child: SizedBox(
                        width: 500, // Set a fixed width for the details box
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                if (description.isNotEmpty)
                                    Padding(
                                        padding: const EdgeInsets.only(bottom: 16.0),
                                        child: Text(description),
                                    ),
                                const Divider(),
                                const Text(
                                    'Councillor Information',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                    ),
                                ),
                                const SizedBox(height: 8),
                                if (photo != null)
                                    Padding(
                                        padding: const EdgeInsets.only(bottom: 16.0),
                                        child: Image.network(
                                            photo,
                                            width: 200,
                                            height: 200,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                                debugPrint('Error loading image: $error');
                                                return const SizedBox.shrink();
                                            },
                                        ),
                                    ),
                                _buildInfoRow('Name', name),
                                _buildInfoRow('Address', address),
                                _buildInfoRow('Contact', contact),
                                _buildInfoRow('Email', email?.isEmpty ?? true ? 'N/A' : email!),
                                _buildInfoRow('Responsibility', responsibility),
                                _buildInfoRow('Party', party),
                            ],
                        ),
                    ),
                ),
                actions: [
                    TextButton(
                        onPressed: () {
                            Navigator.of(context).pop();
                        },
                        child: const Text('Close'),
                    ),
                ],
            );
        },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Madurai Ward Map'),
        centerTitle: true,
        elevation: 2,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _maduraiCenter,
              zoom: _currentZoom,
              onTap: (tapPosition, point) {
                // Check if tap is inside any ward polygon
                for (int i = 0; i < _polygons.length; i++) {
                  if (_isPointInPolygon(point, _polygons[i].points)) {
                    // Add visual feedback when a ward is tapped
                    setState(() {
                      // Reset all polygons to their original color
                      for (int j = 0; j < _polygons.length; j++) {
                        _polygons[j] = Polygon(
                          points: _polygons[j].points,
                          color: _wardColors[j % _wardColors.length],
                          borderColor: Colors.black,
                          borderStrokeWidth: 1.0,
                          isFilled: true,
                        );
                      }
                      // Highlight the selected ward
                      _polygons[i] = Polygon(
                        points: _polygons[i].points,
                        color: _wardColors[i % _wardColors.length].withOpacity(0.7),
                        borderColor: Colors.blue,
                        borderStrokeWidth: 2.0,
                        isFilled: true,
                      );
                    });
                    _showWardDetails(_wardNames[i], _wardDescriptions[i]);
                    break;
                  }
                }
              },
              onPositionChanged: (position, hasGesture) {
                setState(() {
                  _currentZoom = position.zoom!;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.madurai_flutter_app',
                tileProvider: NetworkTileProvider(
                  headers: {
                    'User-Agent': 'Madurai Ward Map App/1.0',
                  },
                ),
              ),
              PolygonLayer(
                polygons: _polygons,
              ),
              if (_currentZoom >= _minZoomForLabels)
                MarkerLayer(
                  markers: _wardLabels,
                ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 100,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: 'zoomIn',
                  mini: true,
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'zoomOut',
                  mini: true,
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'reset',
                  mini: true,
                  onPressed: () {
                    _mapController.move(_maduraiCenter, 12.0);
                  },
                  child: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ),
          // Add a help text overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Tap on any ward to view its details and councillor information',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) /
              (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        inside = !inside;
      }
    }
    return inside;
  }
}