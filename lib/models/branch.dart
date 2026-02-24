class Company {
  final String? name;
  final String? category;
  final String? description;
  final String? logoUrl;
  final int? discountPercentage;

  Company({
    this.name,
    this.category,
    this.description,
    this.logoUrl,
    this.discountPercentage,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      name: json['name'] as String?,
      category: json['category'] as String?,
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      discountPercentage: json['discount_percentage'] as int?,
    );
  }
}

class Branch {
  final dynamic id; // Explicitly dynamic to handle String (UUID) or int
  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final int mapPriority;
  final Company? company;

  Branch({
    required this.id,
    this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.mapPriority = 3,
    this.company,
  });

  factory Branch.fromJson(Map<String, dynamic> json) {
    return Branch(
      id: json['id'],
      name: json['name'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      mapPriority: json['map_priority'] as int? ?? 3,
      company:
          json['companies'] != null
              ? Company.fromJson(json['companies'] as Map<String, dynamic>)
              : null,
    );
  }
}
