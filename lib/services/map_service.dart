import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapService {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  GoogleMapController? _mapController;
  Set<Polygon> _polygons = {};
  Set<Polyline> _wardBoundaries = {};
  Set<Marker> _wardLabels = {};
  Set<Marker> _searchMarkers = {};
  bool _isMapReady = false;
  bool _isLoading = true;
  double _currentZoom = 12.0;
  LatLngBounds? _mapBounds;

  GoogleMapController? get mapController => _mapController;
  Set<Polygon> get polygons => _polygons;
  Set<Polyline> get wardBoundaries => _wardBoundaries;
  Set<Marker> get wardLabels => _wardLabels;
  Set<Marker> get searchMarkers => _searchMarkers;
  bool get isMapReady => _isMapReady;
  bool get isLoading => _isLoading;
  double get currentZoom => _currentZoom;
  LatLngBounds? get mapBounds => _mapBounds;

  void setMapController(GoogleMapController controller) {
    _mapController = controller;
    _isMapReady = true;
    _isLoading = false;
  }

  void setPolygons(Set<Polygon> polygons) {
    _polygons = polygons;
  }

  void setWardBoundaries(Set<Polyline> boundaries) {
    debugPrint('Setting ${boundaries.length} ward boundaries in MapService');
    _wardBoundaries = boundaries;
  }

  void setWardLabels(Set<Marker> labels) {
    _wardLabels = labels;
  }

  void setSearchMarkers(Set<Marker> markers) {
    _searchMarkers = markers;
  }

  void addSearchMarker(Marker marker) {
    _searchMarkers.add(marker);
  }

  void clearSearchMarkers() {
    _searchMarkers.clear();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
  }

  void setCurrentZoom(double zoom) {
    _currentZoom = zoom;
  }

  void setMapBounds(LatLngBounds bounds) {
    _mapBounds = bounds;
  }

  void dispose() {
    _mapController?.dispose();
    _mapController = null;
    _isMapReady = false;
    _isLoading = true;
    _polygons.clear();
    _wardBoundaries.clear();
    _wardLabels.clear();
    _searchMarkers.clear();
  }
} 