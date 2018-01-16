import 'dart:async';

import 'package:flutter/services.dart';

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

  final String identifier;
  final String price;
  final String title;
  final String description;
  final String currency;
  final int amount;

  double get roundAmount => amount / 100;

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

class Billing {
  const Billing._(MethodChannel channel)
      : assert(channel != null),
        _channel = channel;

  static final Billing _instance = new Billing._(const MethodChannel('flutter_billing'));

  factory Billing() => _instance;

  final MethodChannel _channel;

  Future<List<String>> fetchPurchases() => _channel.invokeMethod('fetchPurchases');

  Future<List<String>> purchase(String identifier) {
    assert(identifier != null);

    return _channel.invokeMethod('purchase', {'identifier': identifier});
  }

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
