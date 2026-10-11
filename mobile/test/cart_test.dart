import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/session.dart';
import 'package:flutter_test/flutter_test.dart';

CropListing _crop({int price = 75, int stock = 300}) => CropListing.fromMap({
      'id': 'crop-1',
      'name': 'Red Onions',
      'pricePerKg': price,
      'quantityKg': stock,
      'moqKg': 10,
      'status': 'active',
    });

void main() {
  test('refreshing a line takes the new price but keeps the quantity', () {
    final cart = CartController()..add(_crop(), 20);
    expect(cart.subtotal, 1500);

    cart.refresh(_crop(price: 80, stock: 15));

    expect(cart.lines.single.quantityKg, 20);
    expect(cart.lines.single.crop.pricePerKg, 80);
    expect(cart.lines.single.crop.quantityKg, 15);
    expect(cart.subtotal, 1600);
  });

  test('refreshing a crop that is not in the cart changes nothing', () {
    final cart = CartController()..add(_crop(), 20);
    cart.refresh(CropListing.fromMap({'id': 'other', 'pricePerKg': 1}));
    expect(cart.lines.single.crop.id, 'crop-1');
  });
}
