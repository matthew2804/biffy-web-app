import '../../data/models/catalog.dart';

const kCategories = <FoodCategory>[
  FoodCategory(
    'sandwich',
    'Sándwiches',
    '🥪',
    'assets/images/demo-qbano-sandwich.jpg',
  ),
  FoodCategory(
    'pizza',
    'Pizza',
    '🍕',
    'assets/images/dishes/pizza-margarita.jpg',
  ),
  FoodCategory(
    'hamburguesa',
    'Hamburguesas',
    '🍔',
    'assets/images/dishes/smash-doble.jpg',
  ),
  FoodCategory(
    'saludable',
    'Saludable',
    '🥗',
    'assets/images/dishes/bowl-vegano.jpg',
  ),
  FoodCategory(
    'almuerzo',
    'Almuerzos',
    '🍛',
    'assets/images/dishes/almuerzo.jpg',
  ),
  FoodCategory('cafe', 'Café', '☕', 'assets/images/dishes/capuchino.jpg'),
  FoodCategory('postres', 'Postres', '🍩', 'assets/images/dishes/dona.jpg'),
  FoodCategory('mexicana', 'Mexicana', '🌮', 'assets/images/dishes/tacos.jpg'),
  FoodCategory('asiatica', 'Asiática', '🍜', 'assets/images/dishes/ramen.jpg'),
];

FoodCategory categoryById(String id) => kCategories.firstWhere(
  (c) => c.id == id,
  orElse: () => FoodCategory(id, id, '🍽️'),
);

const kLifestyleOptions = [
  'vegano',
  'vegetariano',
  'sin gluten',
  'alto en proteína',
  'bajo en calorías',
];

/// Estilos que se tratan como restricción estricta en recomendaciones.
const kStrictLifestyles = {'vegano', 'vegetariano', 'sin gluten'};

const kAllergyOptions = [
  'gluten',
  'lácteos',
  'maní',
  'mariscos',
  'huevo',
  'soya',
  'sésamo',
];

/// Ícono de comida para cada alergia y estilo de vida (se ve en los chips).
const kOptionEmoji = {
  'gluten': '🌾',
  'lácteos': '🥛',
  'maní': '🥜',
  'mariscos': '🦐',
  'huevo': '🥚',
  'soya': '🫘',
  'sésamo': '🥯',
  'vegano': '🌱',
  'vegetariano': '🥦',
  'sin gluten': '🌽',
  'alto en proteína': '🍗',
  'bajo en calorías': '🥗',
};

const kUniversities = <University>[
  University(
    id: 'icesi',
    name: 'Universidad Icesi',
    domain: 'icesi.edu.co',
    city: 'Cali',
  ),
  University(
    id: 'unal',
    name: 'Universidad Nacional',
    domain: 'unal.edu.co',
    city: 'Bogotá',
  ),
  University(
    id: 'andes',
    name: 'Universidad de los Andes',
    domain: 'uniandes.edu.co',
    city: 'Bogotá',
  ),
  University(
    id: 'javeriana',
    name: 'Pontificia Universidad Javeriana',
    domain: 'javeriana.edu.co',
    city: 'Bogotá',
  ),
];

University? universityById(String? id) {
  for (final u in kUniversities) {
    if (u.id == id) return u;
  }
  return null;
}

const kDeliveryPoints = <DeliveryPoint>[
  DeliveryPoint(
    id: 'icesi-biblioteca',
    name: 'Icesi · Biblioteca',
    detail: 'Punto de encuentro demo · Cali',
    lat: 3.3415,
    lng: -76.5305,
    campusId: 'icesi',
  ),
  DeliveryPoint(
    id: 'icesi-plazoleta',
    name: 'Icesi · Plazoleta',
    detail: 'Punto de encuentro demo · Cali',
    lat: 3.3421,
    lng: -76.5298,
    campusId: 'icesi',
  ),
  DeliveryPoint(
    id: 'icesi-entrada',
    name: 'Icesi · Entrada principal',
    detail: 'Punto de encuentro demo · Cali',
    lat: 3.3409,
    lng: -76.5309,
    campusId: 'icesi',
  ),
  DeliveryPoint(
    id: 'biblio',
    name: 'Biblioteca Central',
    detail: 'Entrada principal · Bogotá',
    lat: 4.6355,
    lng: -74.083,
    campusId: 'unal',
  ),
  DeliveryPoint(
    id: 'inge',
    name: 'Edificio Ingeniería',
    detail: 'Hall piso 1 · Bogotá',
    lat: 4.6378,
    lng: -74.0825,
    campusId: 'unal',
  ),
  DeliveryPoint(
    id: 'plazoleta-che',
    name: 'Plazoleta Che',
    detail: 'Junto a las bancas · Bogotá',
    lat: 4.6362,
    lng: -74.0815,
    campusId: 'unal',
  ),
  DeliveryPoint(
    id: 'chapinero',
    name: 'Casa · Chapinero',
    detail: 'Cra 7 #60-20 · Bogotá',
    lat: 4.6465,
    lng: -74.0628,
  ),
  DeliveryPoint(
    id: 'suba',
    name: 'Casa · Suba',
    detail: 'Cl 145 #91-10 · Bogotá',
    lat: 4.7405,
    lng: -74.0835,
  ),
];

DeliveryPoint pointById(String id) => kDeliveryPoints.firstWhere(
  (p) => p.id == id,
  orElse: () => kDeliveryPoints.first,
);

/// Valor de referencia de demostración: 1 Gota = $10 COP.
const kGotaValue = 10;
const kWelcomeGotas = 450;
const kSurveyGotas = 300;

const kDemoPassword = 'biffy123';
