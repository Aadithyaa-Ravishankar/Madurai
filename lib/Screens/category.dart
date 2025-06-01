import 'package:flutter/material.dart';

class CategoryItem {
  final IconData icon;
  final String name;

  CategoryItem({
    required this.icon,
    required this.name,
  });
}

class CategoryCard extends StatelessWidget {
  final CategoryItem category;

  const CategoryCard({
    super.key,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF7F9FC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(
          color: Color(0xFFD1DBE8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              category.icon,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CategorySelectionScreen extends StatelessWidget {
  const CategorySelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = [
      CategoryItem(
        icon: Icons.star,
        name: 'Star Damage',
      ),
      CategoryItem(
        icon: Icons.lightbulb_outline,
        name: 'Street Light Not Working',
      ),
      CategoryItem(
        icon: Icons.delete_outline,
        name: 'Garbage Collection',
      ),
      CategoryItem(
        icon: Icons.water_drop_outlined,
        name: 'Water Supply Issues',
      ),
      CategoryItem(
        icon: Icons.power_outlined,
        name: 'Power Outage',
      ),
      CategoryItem(
        icon: Icons.volume_up_outlined,
        name: 'Noise Complaint',
      ),
      CategoryItem(
        icon: Icons.directions_bus_outlined,
        name: 'Public Transport Issues',
      ),
      CategoryItem(
        icon: Icons.pets_outlined,
        name: 'Stray Animals',
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Report an Issue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                'Select a category',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    return CategoryCard(category: categories[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Add just these 3 lines at the VERY BOTTOM of your existing file:
void main() => runApp(
    MaterialApp(debugShowCheckedModeBanner: false, home: CategorySelectionScreen())
);