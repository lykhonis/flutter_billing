## flutter_billing

A plugin for [Flutter](https://flutter.io) that enables communication with billing API in 
[iOS](https://developer.apple.com/in-app-purchase/) and 
[Android](https://developer.android.com/google/play/billing/billing_integrate.html).

*Warning*: This plugin is still under development, some billing features are not available yet and
testing has been limited.
[Feedback](https://github.com/VolodymyrLykhonis/flutter_billing/issues) and
[Pull Requests](https://github.com/VolodymyrLykhonis/flutter_billing/pulls) are welcome.

## Using
Add `flutter_billing` as a dependency in `pubspec.yaml`.

Create an instance of the plugin:
```dart
final Billing billing = new Billing();
```

Request available products and details:
```dart
final List<BillingProduct> skuDetails = await billing.fetchProducts(<String>[
    'my.product.id',
]);
```

Request purchased products (each purchase is a product id):
```dart
final List<String> purchases = await billing.fetchPurchases();
```

Make a product purchase. It throws in a case of error or returns a list of purchased products on success:
```dart
final List<String> purchases = await billing.purchase(productId);
```

## Tips

Billing issues calls to App Store and Play Store accordingly. e.g. When fetch products are called more 
than once it may request products from a Store and not cache. To prevent such situations one could use
[synchronized](https://pub.dartlang.org/packages/synchronized) package and implement similar solution:

```dart
class BillingRepository {
  final Billing _billing = new Billing();
  List<BillingProduct> _cachedProducts;

  Future<List<BillingProduct>> getProducts() {
    return synchronized(this, () async {
      if (_cachedProducts == null) {
        _cachedProducts = await _billing.fetchProducts(<String>[
          'my.product.id',
        ]);
      }

      return _cachedProducts;
    });
  }

  Future<BillingProduct> purchase(BillingProduct product) async {
    final List<String> purchases = await _billing.purchase(product.identifier);
    // update purchased products

    return product;
  }

  Future<BillingProduct> get(String identifier) async {
    final List<BillingProduct> products = await getProducts();

    return products.firstWhere((_) => _.identifier == identifier, orElse: () => null);
  }
}
```

## Limitations

This is just an initial version of the plugin. There are still some limitiations:

- iOS implementation is currently under testing
- Only non-consumable in app products are supported
