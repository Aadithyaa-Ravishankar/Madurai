// Reminder: complaint_form.dart requires intl, image_picker, geolocator, geocoding in pubspec.yaml
// See complaint_form.dart for details
import 'package:flutter/material.dart';
import 'complaint_form.dart';

class ComplaintsPage extends StatelessWidget {
  const ComplaintsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final categories = [
      _ComplaintCategory('Road Damage', Icons.alt_route),
      _ComplaintCategory('Street Light Not Working', Icons.lightbulb_outline),
      _ComplaintCategory('Garbage Collection', Icons.delete_outline),
      _ComplaintCategory('Water Supply Issues', Icons.opacity),
      _ComplaintCategory('Power Outage', Icons.power_settings_new),
      _ComplaintCategory('Noise Complaint', Icons.volume_up_outlined),
      _ComplaintCategory('Public Transport Issues', Icons.directions_bus),
      _ComplaintCategory('Stray Animals', Icons.pets),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Report an Issue',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Select a category',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 18,
                  childAspectRatio: 2.3,
                  children: categories.map((cat) => _CategoryCard(cat: cat)).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComplaintCategory {
  final String title;
  final IconData icon;
  const _ComplaintCategory(this.title, this.icon);
}

class _CategoryCard extends StatelessWidget {
  final _ComplaintCategory cat;
  const _CategoryCard({required this.cat});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ComplaintFormPage(category: cat.title),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(cat.icon, color: Colors.black, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cat.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 