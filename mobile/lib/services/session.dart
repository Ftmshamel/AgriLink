import 'package:flutter/foundation.dart';

import '../models/agri_models.dart';
import '../models/mobile_user.dart';
import 'local_auth_service.dart';

/// The signed-in account plus a change counter every live screen listens to.
///
/// Any write in the app calls [bump], which makes every [LiveBuilder] reload —
/// that is how a farmer packing an order immediately shows up in the rider
/// pool and on the buyer's tracking screen.
class AppSession extends ChangeNotifier {
  AppSession(this._user);

  MobileUser _user;
  int _revision = 0;

  MobileUser get user => _user;
  int get revision => _revision;

  void bump() {
    _revision++;
    notifyListeners();
  }

  void updateUser(MobileUser user) {
    _user = user;
    _revision++;
    notifyListeners();
  }

  /// Re-reads the account so profile edits and admin approvals take effect
  /// without forcing a log out.
  Future<void> reloadUser(LocalAuthService auth) async {
    final account = await auth.database.getAccount(_user.id);
    if (account == null) return;
    updateUser(MobileUser.fromJson(account));
  }
}

/// Market cart for the consumer shell.
class CartController extends ChangeNotifier {
  final List<CartLine> _lines = [];

  List<CartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get count => _lines.length;
  int get totalKg =>
      _lines.fold<int>(0, (total, line) => total + line.quantityKg);
  int get subtotal => _lines.fold<int>(0, (total, line) => total + line.subtotal);

  CartLine? lineFor(String cropId) {
    for (final line in _lines) {
      if (line.crop.id == cropId) return line;
    }
    return null;
  }

  void add(CropListing crop, int quantityKg) {
    final existing = lineFor(crop.id);
    if (existing != null) {
      existing.quantityKg += quantityKg;
    } else {
      _lines.add(CartLine(crop: crop, quantityKg: quantityKg));
    }
    notifyListeners();
  }

  void setQuantity(String cropId, int quantityKg) {
    final line = lineFor(cropId);
    if (line == null) return;
    if (quantityKg <= 0) {
      _lines.remove(line);
    } else {
      line.quantityKg = quantityKg;
    }
    notifyListeners();
  }

  void remove(String cropId) {
    _lines.removeWhere((line) => line.crop.id == cropId);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
