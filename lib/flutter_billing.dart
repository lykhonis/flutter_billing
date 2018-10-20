import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:synchronized/synchronized.dart';

enum BillingProductType { product, subscription }

/// A single product that can be purchased by a user in app.
class BillingProduct {
  BillingProduct({
    this.identifier,
    this.price,
    this.title,
    this.description,
    this.currency,
    this.amount,
    this.type,
  })  : assert(identifier != null),
        assert(price != null),
        assert(title != null),
        assert(description != null),
        assert(currency != null),
        assert(amount != null),
        assert(type != null);

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

  // Type of product.
  final BillingProductType type;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BillingProduct &&
          identifier == other.identifier &&
          price == other.price &&
          title == other.title &&
          description == other.description &&
          currency == other.currency &&
          amount == other.amount &&
          type == other.type;

  @override
  int get hashCode => hashValues(identifier, price, title, description, currency, amount, type);

  @override
  String toString() {
    return '$runtimeType(sku: $identifier, price: $price, title: $title, '
        'description: $description, currency: $currency, amount: $amount, type: $type)';
  }
}

/// A billing error callback to be called when any of billing operations fail.
typedef void BillingErrorCallback(dynamic e);

/// Billing plugin to enable communication with billing API in iOS and Android.
class Billing {
  static const MethodChannel _channel = const MethodChannel('flutter_billing');

  Billing({BillingErrorCallback onError}) : _onError = onError;

  final BillingErrorCallback _onError;
  final _lock = Lock();
  final _cachedProducts = <String, BillingProduct>{};
  final _purchasedProducts = Set<String>();
  bool _purchasesFetched = false;

  /// Products details of supplied product identifiers.
  ///
  /// Returns a list of products available to the app for a purchase.
  ///
  /// Note the behavior may differ from iOS and Android. Android most likely to throw in a case
  /// of error, while iOS would return a list of only products that are available. In a case of
  /// error, it would return simply empty list.
  Future<List<BillingProduct>> getProducts(List<String> identifiers) {
    return _fetch(method: 'fetchProducts', identifiers: identifiers);
  }

  /// Products details of supplied product identifiers.
  ///
  /// Returns a list of products available to the app for subscription.
  ///
  /// Note the behavior may differ from iOS and Android. Android most likely to throw in a case
  /// of error, while iOS would return a list of only products that are available. In a case of
  /// error, it would return simply empty list.
  Future<List<BillingProduct>> getSubscriptions(List<String> identifiers) {
    return _fetch(method: 'fetchSubscriptions', identifiers: identifiers);
  }

  Future<List<BillingProduct>> _fetch({String method, List<String> identifiers}) {
    assert(method != null);
    assert(identifiers != null);
    if (_cachedProducts.keys.toSet().containsAll(identifiers)) {
      return Future.value(identifiers.map((identifier) => _cachedProducts[identifier]).toList());
    }
    return _lock.synchronized(() async {
      try {
        final products = Map<String, BillingProduct>.fromIterable(
          await _channel.invokeMethod(method, {'identifiers': identifiers}),
          key: (product) => product['identifier'],
          value: (product) => BillingProduct(
                identifier: product['identifier'],
                price: product['price'],
                title: product['title'],
                description: product['description'],
                currency: product['currency'],
                amount: product['amount'],
                type: _getProductType(product['type']),
              ),
        );
        _cachedProducts.addAll(products);
        return products.values.toList();
      } catch (e) {
        if (_onError != null) _onError(e);
        return <BillingProduct>[];
      }
    });
  }

  BillingProductType _getProductType(String type) {
    if (type == 'product') return BillingProductType.product;
    if (type == 'subscription') return BillingProductType.subscription;
    throw ArgumentError('Unsupported product type: $type');
  }

  /// Product details of supplied product identifier.
  ///
  /// Returns a product details or null if one is not available or error occurred.
  Future<BillingProduct> getProduct(String identifier) async {
    final products = await getProducts(<String>[identifier]);
    return products.firstWhere((product) => product.identifier == identifier, orElse: () => null);
  }

  /// Purchased products identifiers.
  ///
  /// Returns products identifiers that are already purchased.
  Future<Set<String>> getPurchases() {
    if (_purchasesFetched) {
      return Future.value(Set.from(_purchasedProducts));
    }
    return _lock.synchronized(() async {
      try {
        final List purchases = await _channel.invokeMethod('fetchPurchases');
        _purchasedProducts.addAll(purchases.cast());
        _purchasesFetched = true;
        return _purchasedProducts;
      } catch (e) {
        if (_onError != null) _onError(e);
        return Set.identity();
      }
    });
  }

  /// Grab in app receipt for iOS.
  ///
  /// Returns a String containing the receipt, validity should be check on (your) server side.
  /// If receipt is unavailable or a call is made on Android it returns empty string.
  Future<String> getReceipt() async {
    final String receipt = await _channel.invokeMethod('getReceipt');
    return receipt;
  }

  /// Validate if a product is purchased.
  ///
  /// Returns true if a product is purchased, otherwise false.
  Future<bool> isPurchased(String identifier) async {
    assert(identifier != null);
    final purchases = await getPurchases();
    return purchases.contains(identifier);
  }

  /// Purchase a product. If it is a consumable, set consume to true. It will automatically consume it on Android, just after purchase!
  ///
  /// This would trigger platform UI to walk a user through steps of purchasing the product.
  /// Returns updated list of product identifiers that have been purchased.
  Future<bool> purchase(String identifier, {bool consume: false}) {
    return _purchase(method: 'purchase', identifier: identifier, consume: consume);
  }

  /// Subscribe to a product.
  ///
  /// This would trigger platform UI to walk a user through steps of subscribing to the product.
  /// Returns updated list of product identifiers that have been subscribed to.
  Future<bool> subscribe(String identifier) {
    return _purchase(method: 'subscribe', identifier: identifier);
  }

  Future<bool> _purchase({String method, String identifier, bool consume: false}) {
    assert(method != null);
    assert(consume != null);
    assert(identifier != null);
    if (_purchasedProducts.contains(identifier)) {
      return Future.value(true);
    }
    return _lock.synchronized(() async {
      try {
        final List subscriptions = await _channel.invokeMethod(method, {
          'identifier': identifier,
          'consume': consume,
        });
        _purchasedProducts.addAll(subscriptions.cast());
        return subscriptions.contains(identifier);
      } catch (e) {
        if (_onError != null) _onError(e);
        return false;
      }
    });
  }
}
