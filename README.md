## flutter_billing
A plugin for [Flutter](https://flutter.io) that enables communication with billing API in 
[iOS](https://developer.apple.com/in-app-purchase/) and 
[Android](https://developer.android.com/google/play/billing/billing_integrate.html).

This plugin implements in app purchases rather than Android Pay or Apple Pay. Both
Apple and Google collect fees upon each successful transaction made using this plugin.

*Warning*: This plugin is still under development, some billing features are not available yet and
testing has been limited.
[Feedback](https://github.com/VolodymyrLykhonis/flutter_billing/issues) and
[Pull Requests](https://github.com/VolodymyrLykhonis/flutter_billing/pulls) are welcome.

## Using
Add `flutter_billing` [![flutter_billing](https://img.shields.io/pub/v/flutter_billing.svg)](https://pub.dartlang.org/packages/flutter_billing) as a dependency in `pubspec.yaml`.

Create an instance of the plugin:
```dart
final Billing billing = new Billing(onError: (e) {
  // optionally handle exception
});
```

Request available products for purchase:
```dart
final List<BillingProduct> products = await billing.getProducts(<String>[
    'my.product.id',
    'my.other.product.id',
]);
```
or
```dart
final BillingProduct product = await billing.getProduct('my.product.id');
if (product != null) {
  // success
} else {
  // something went wrong
}
```

Request purchased products (each purchase is a product identifier):
```dart
final Set<String> purchases = await billing.getPurchases();
```

Check if a product is already purchased:
```dart
final bool purchased = purchases.contains('my.product.id');
```
or
```dart
final bool purchases = await billing.isPurchased('my.product.id');
```

Purchase a product:
```dart
final bool purchased = await billing.purchase(productId);
```

## Limitations
This is just an initial version of the plugin. There are still some limitations:

- ~~One time purchase products are not supported~~
- ~~Consumable products are not supported~~
- ~~Android subscription are not supported~~
- ~~iOS receipt request is not supported~~
- iOS subscriptions are not supported
