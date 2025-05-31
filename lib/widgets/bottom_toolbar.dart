import 'package:flutter/material.dart';
import '../Screens/complaints.dart';
import '../Screens/profile.dart';
import '../main.dart';
import '../services/map_service.dart';

class BottomToolbar extends StatefulWidget {
  final int currentIndex;

  const BottomToolbar({
    super.key,
    required this.currentIndex,
  });

  @override
  State<BottomToolbar> createState() => _BottomToolbarState();
}

class _BottomToolbarState extends State<BottomToolbar> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  int? _tappedIndex;
  final MapService _mapService = MapService();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _navigateToPage(int index) {
    if (widget.currentIndex == index) return;
    
    setState(() {
      _tappedIndex = index;
    });
    _animationController.forward(from: 0.0).then((_) {
      setState(() {
        _tappedIndex = null;
      });
    });

    // Reset map state when navigating to home
    if (index == 1) {
      _mapService.dispose();
    }

    // Determine the slide direction based on the current and target indices
    Offset offset;
    if (index > widget.currentIndex) {
      offset = const Offset(1.0, 0.0);
    } else {
      offset = const Offset(-1.0, 0.0);
    }

    Widget targetPage;
    switch (index) {
      case 0:
        targetPage = const ComplaintsPage();
        break;
      case 1:
        targetPage = const MapPage();
        break;
      case 2:
        targetPage = const ProfilePage();
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetPage,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: offset,
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildBottomBarButton({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final bool isActive = widget.currentIndex == index;
    final bool isTapped = _tappedIndex == index;
    
    return InkWell(
      onTap: () => _navigateToPage(index),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? Colors.red.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: isTapped ? [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3 * _animation.value),
                  blurRadius: 8,
                  spreadRadius: 2,
                  offset: const Offset(0, 2),
                ),
              ] : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isActive ? Colors.red : Colors.grey[600],
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.red : Colors.grey[600],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _buildBottomBarButton(
                icon: Icons.report_problem,
                label: 'Complaints',
                index: 0,
              ),
            ),
            Expanded(
              child: _buildBottomBarButton(
                icon: Icons.home,
                label: 'Home',
                index: 1,
              ),
            ),
            Expanded(
              child: _buildBottomBarButton(
                icon: Icons.person,
                label: 'Profile',
                index: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 