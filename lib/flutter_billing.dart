import 'dart:async';

import 'package:flutter/services.dart';

/// A single product that can be purchased by a user in app.
class BillingProduct {
  BillingProduct({
    this.identifier,
    this.price,
    this.title,
    this.description,
    this.currency,
    this.amount,
  })
      : assert(identifier != null),
        assert(price != null),
        assert(title != null),
        assert(description != null),
        assert(currency != null),
        assert(amount != null);

  /// Unique product identifier.
  final String identifier;

  /// Localized formatted product price including currency sign. e.g. $2.49.
  final String price;

  /// Localized product title.
  final String title;

  /// Localized product description.
  final String description;

  /// ISO 4217 currency code for price.
  final String currency;

  /// Price in 100s. e.g. $2.49 equals 249.
  final int amount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingProduct &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier &&
          price == other.price &&
          title == other.title &&
          description == other.description &&
          currency == other.currency &&
          amount == other.amount;

  @override
  int get hashCode =>
      identifier.hashCode ^
      price.hashCode ^
      title.hashCode ^
      description.hashCode ^
      currency.hashCode ^
      amount.hashCode;

  @override
  String toString() {
    return 'BillingProduct{sku: $identifier, price: $price, title: $title, '
        'description: $description, currency: $currency, amount: $amount}';
  }
}

/// Billing plugin to enable communication with billing API in iOS and Android.
class Billing {
  const Billing._(MethodChannel channel)
      : assert(channel != null),
        _channel = channel;

  static final Billing _instance = new Billing._(const MethodChannel('flutter_billing'));

  factory Billing() => _instance;

  final MethodChannel _channel;

  /// Fetch purchased products.
  ///
  /// Returns a list of product identifiers that have been purchased.
  Future<List<String>> fetchPurchases() => _channel.invokeMethod('fetchPurchases');

  /// Purchase a product.
  ///
  /// This would trigger platform UI to walk a user through steps of purchasing the product.
  /// Returns updated list of product identifiers that have been purchased.
  Future<List<String>> purchase(String identifier) {
    assert(identifier != null);

    return _channel.invokeMethod('purchase', {'identifier': identifier});
  }

  /// Fetch details of supplied product identifiers.
  ///
  /// Returns a list of products available to the app for a purchase.
  ///
  /// Note the behavior may differ from iOS and Android. Android most likely to throw in a case
  /// of error, while iOS would return a list of only products that are available. In a case of
  /// error, it would return simply empty list.
  Future<List<BillingProduct>> fetchProducts(List<String> identifiers) async {
    assert(identifiers != null);

    final Map<String, Map<String, dynamic>> products =
        await _channel.invokeMethod('fetchProducts', {'identifiers': identifiers});

    final List<BillingProduct> result = <BillingProduct>[];

    for (String identifier in identifiers) {
      final Map<String, dynamic> product = products[identifier];
      if (product == null) continue;

      result.add(new BillingProduct(
        identifier: identifier,
        price: product['price'],
        title: product['title'],
        description: product['description'],
        currency: product['currency'],
        amount: product['amount'],
      ));
    }

    return result;
  }
}
