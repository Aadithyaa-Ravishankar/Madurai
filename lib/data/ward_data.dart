class WardData {
  final String name;
  final String code;
  final List<String> areas;
  final List<String> facilities;
  final String population;
  final String? description;

  WardData({
    required this.name,
    required this.code,
    required this.areas,
    required this.facilities,
    required this.population,
    this.description,
  });
}

final Map<String, WardData> maduraiWards = {
  "Ward 1": WardData(
    name: "Ward 1",
    code: "MDR001",
    areas: ["Area 1", "Area 2", "Area 3"],
    facilities: ["School", "Hospital", "Library"],
    population: "45,000",
    description: "Located in the northern part of Madurai",
  ),
  "Ward 2": WardData(
    name: "Ward 2",
    code: "MDR002",
    areas: ["Area 4", "Area 5"],
    facilities: ["Park", "Market", "Bus Stand"],
    population: "38,500",
    description: "Central business district",
  ),
  "Ward 3": WardData(
    name: "Ward 3",
    code: "MDR003",
    areas: ["Area 6", "Area 7", "Area 8"],
    facilities: ["Mall", "Police Station"],
    population: "52,000",
    description: "Residential area with commercial zones",
  ),
  // Add more wards with default data
  "Ward 49": WardData(
    name: "Naahanakulam",
    code: "MDR049",
    areas: ["Naahanakulam", "Surrounding Areas"],
    facilities: ["Basic Amenities"],
    population: "35,000",
    description: "Residential area in Madurai",
  ),
  // Add more wards as needed
}; 