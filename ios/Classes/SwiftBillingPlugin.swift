import Flutter
import StoreKit

public class SwiftBillingPlugin: NSObject, FlutterPlugin, SKRequestDelegate, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    var fetchPurchases = [FlutterResult]()
    var fetchProducts = [SKRequest: FlutterResult]()
    var requestedPayments = [SKPayment: FlutterResult]()
    var products = [SKProduct]()
    var purchases = Set<String>()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_billing", binaryMessenger: registrar.messenger())
        let instance = SwiftBillingPlugin()

        SKPaymentQueue.default().add(instance)

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "fetchPurchases":
            fetchPurchases(result)
        case "purchase":
            if let arguments = call.arguments as? [String: Any?],
                let identifier = arguments["identifier"] as? String {
                purchase(identifier, result: result)
            } else {
                result(FlutterError(code: "ERROR", message: "Invalid or missing arguments!", details: nil))
            }
        case "fetchProducts":
            if let arguments = call.arguments as? [String: Any?],
                let identifiers = arguments["identifiers"] as? [String] {
                fetchProducts(identifiers, result: result)
            } else {
                result(FlutterError(code: "ERROR", message: "Invalid or missing arguments!", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func fetchPurchases(_ result: @escaping FlutterResult) {
        fetchPurchases.append(result)
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        purchased(transactions.filter { $0.transactionState == .purchased })
        restored(transactions.filter { $0.transactionState == .restored })
        failed(transactions.filter { $0.transactionState == .failed })
    }

    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        let resultError = FlutterError(code: "ERROR", message: "Failed to restore purchases!", details: nil)
        let results = Array(fetchPurchases)
        fetchPurchases.removeAll()
        
        results.forEach { result in result(resultError) }
    }
    
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        let results = Array(fetchPurchases)
        fetchPurchases.removeAll()
        
        let productIndentifiers = Array(purchases)
        results.forEach { result in result(productIndentifiers) }
    }
    
    private func restored(_ transactions: [SKPaymentTransaction]) {
        transactions.forEach { transaction in
            if let productIdentifier = transaction.original?.payment.productIdentifier { purchases.insert(productIdentifier) }
            SKPaymentQueue.default().finishTransaction(transaction)
        }
    }
    
    private func failed(_ transactions: [SKPaymentTransaction]) {
        transactions.forEach { transaction in
            if let result = requestedPayments.removeValue(forKey: transaction.payment) {
                result(FlutterError(code: "ERROR", message: "Failed to make a payment!", details: nil))
            }
            SKPaymentQueue.default().finishTransaction(transaction)
        }
    }
    
    private func purchased(_ transactions: [SKPaymentTransaction]) {
        var results = [FlutterResult]()
        
        for transaction in transactions {
            purchases.insert(transaction.payment.productIdentifier)
            if let result = requestedPayments.removeValue(forKey: transaction.payment) { results.append(result) }
            SKPaymentQueue.default().finishTransaction(transaction)
        }
        
        let productIndentifiers = Array(purchases)
        results.forEach { $0(productIndentifiers) }
    }
    
    private func purchase(_ identifier: String, result: @escaping FlutterResult) {
        guard let product = products.first(where: { product -> Bool in product.productIdentifier == identifier }) else { return }
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    private func fetchProducts(_ identifiers: [String], result: @escaping FlutterResult) {
        let request = SKProductsRequest(productIdentifiers: Set(identifiers));
        request.delegate = self
        
        fetchProducts[request] = result
        
        request.start();
    }
    
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        if let result = fetchProducts.removeValue(forKey: request) {
            result(FlutterError(code: "ERROR", message: "Failed to make IAP request!", details: nil))
        }
    }

    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        guard let result = fetchProducts.removeValue(forKey: request) else { return }
        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency

        products = response.products

        let values = response.products.reduce(into: [String: Any]()) { values, product in
            currencyFormatter.locale = product.priceLocale

            values["price"] = currencyFormatter.string(from: product.price)
            values["title"] = product.localizedTitle
            values["description"] = product.localizedDescription
            values["currency"] = product.priceLocale.currencyCode
            values["amount"] = product.price
        }
        
        result(values)
    }
}
