/// Negocio registrado (puede tener varias sedes = restaurantes del catálogo).
class Business {
  Business({
    required this.id,
    required this.brand,
    required this.legalName,
    required this.nit,
    required this.cuisine,
    required this.description,
    required this.ownerName,
    required this.ownerDoc,
    required this.ownerPhone,
    required this.ownerEmail,
    this.bankName = 'Banco de demostración',
    this.accountType = 'Ahorros',
    this.accountNumber = '•••• 0000',
    this.legalDocs = const {},
    this.nutritionInfo = false,
    this.isDemo = false,
  });

  final String id;
  String brand;
  String legalName;
  String nit;
  String cuisine;
  String description;
  String ownerName;
  String ownerDoc;
  String ownerPhone;
  String ownerEmail;
  String bankName;
  String accountType;
  String accountNumber;

  /// Documentos seleccionados localmente (no se verifican ni transmiten).
  Map<String, String> legalDocs;
  bool nutritionInfo;
  final bool isDemo;
}
