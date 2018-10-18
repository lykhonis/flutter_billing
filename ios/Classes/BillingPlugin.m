#import "BillingPlugin.h"

@interface BillingPlugin()

@property (atomic, retain) NSMutableArray<FlutterResult>* fetchPurchases;
@property (atomic, retain) NSMutableDictionary<NSValue*, FlutterResult>* fetchProducts;
@property (atomic, retain) NSMutableDictionary<SKPayment*, FlutterResult>* requestedPayments;
@property (atomic, retain) NSArray<SKProduct*>* products;
@property (atomic, retain) NSMutableSet<NSString*>* purchases;
@property (nonatomic, retain) FlutterMethodChannel* channel;

@end

@implementation BillingPlugin

@synthesize fetchPurchases;
@synthesize fetchProducts;
@synthesize requestedPayments;
@synthesize products;
@synthesize purchases;
@synthesize channel;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    BillingPlugin* instance = [[BillingPlugin alloc] init];
    instance.channel = [FlutterMethodChannel
                        methodChannelWithName:@"flutter_billing"
                        binaryMessenger:[registrar messenger]];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:instance];
    [registrar addMethodCallDelegate:instance channel:instance.channel];
}

- (instancetype)init {
    self = [super init];
    
    self.fetchPurchases = [[NSMutableArray alloc] init];
    self.fetchProducts = [[NSMutableDictionary alloc] init];
    self.requestedPayments = [[NSMutableDictionary alloc] init];
    self.products = [[NSArray alloc] init];
    self.purchases = [[NSMutableSet alloc] init];
    
    return self;
}

- (void)dealloc {
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
    [self.channel setMethodCallHandler:nil];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"fetchPurchases" isEqualToString:call.method]) {
        [self fetchPurchases:result];
    } else if ([@"getReceipt" isEqualToString:call.method]) {
        [self getReceipt:result];
    } else if ([@"purchase" isEqualToString:call.method]) {
        NSString* identifier = (NSString*)call.arguments[@"identifier"];
        if (identifier != nil) {
            [self purchase:identifier result:result];
        } else {
            result([FlutterError errorWithCode:@"ERROR" message:@"Invalid or missing arguments!" details:nil]);
        }
    } else if ([@"fetchProducts" isEqualToString:call.method]) {
        NSArray<NSString*>* identifiers = (NSArray<NSString*>*)call.arguments[@"identifiers"];
        if (identifiers != nil) {
            [self fetchProducts:identifiers result:result];
        } else {
            result([FlutterError errorWithCode:@"ERROR" message:@"Invalid or missing arguments!" details:nil]);
        }
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)getReceipt:(FlutterResult)result {
    NSData *dataReceipt = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] appStoreReceiptURL]];
    if (!dataReceipt) {
        result(@"");
    } else {
        result([dataReceipt base64EncodedStringWithOptions:0]);
    }
}

- (void)fetchPurchases:(FlutterResult)result {
    [fetchPurchases addObject:result];
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    [self purchased:[transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKPaymentTransaction* transaction, NSDictionary* bindings) {
        return [transaction transactionState] == SKPaymentTransactionStatePurchased;
    }]]];
    [self restored:[transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKPaymentTransaction* transaction, NSDictionary* bindings) {
        return [transaction transactionState] == SKPaymentTransactionStateRestored;
    }]]];
    [self failed:[transactions filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(SKPaymentTransaction* transaction, NSDictionary* bindings) {
        return [transaction transactionState] == SKPaymentTransactionStateFailed;
    }]]];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    FlutterError* resultError = [FlutterError errorWithCode:@"ERROR" message:@"Failed to restore purchases!" details:nil];
    NSArray<FlutterResult>* results = [NSArray arrayWithArray:fetchPurchases];
    [fetchPurchases removeAllObjects];

    [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL* stop) {
        result(resultError);
    }];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    NSArray<FlutterResult>* results = [NSArray arrayWithArray:fetchPurchases];
    [fetchPurchases removeAllObjects];

    NSArray<NSString*>* productIdentifiers = [purchases allObjects];
    [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL* stop) {
        result(productIdentifiers);
    }];
}

- (void)purchased:(NSArray<SKPaymentTransaction*>*)transactions {
    NSMutableArray<FlutterResult>* results = [[NSMutableArray alloc] init];
    
    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction* transaction, NSUInteger idx, BOOL* stop) {
        [self->purchases addObject:transaction.payment.productIdentifier];
        FlutterResult result = [self->requestedPayments objectForKey:transaction.payment];
        if (result != nil) {
            [self->requestedPayments removeObjectForKey:transaction.payment];
            [results addObject:result];
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }];

    NSArray<NSString*>* productIdentifiers = [purchases allObjects];
    [results enumerateObjectsUsingBlock:^(FlutterResult result, NSUInteger idx, BOOL* stop) {
        result(productIdentifiers);
    }];
}

- (void)restored:(NSArray<SKPaymentTransaction*>*)transactions {
    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction* transaction, NSUInteger idx, BOOL* stop) {
        SKPaymentTransaction* original = transaction.originalTransaction;
        if (original != nil) {
            [self->purchases addObject:original.payment.productIdentifier];
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }];
}

- (void)failed:(NSArray<SKPaymentTransaction*>*)transactions {
    [transactions enumerateObjectsUsingBlock:^(SKPaymentTransaction* transaction, NSUInteger idx, BOOL* stop) {
        FlutterResult result = [self->requestedPayments objectForKey:transaction.payment];
        if (result != nil) {
            [self->requestedPayments removeObjectForKey:transaction.payment];
            result([FlutterError errorWithCode:@"ERROR" message:@"Failed to make a payment!" details:nil]);
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
    }];
}

- (void)purchase:(NSString*)identifier result:(FlutterResult)result {
    SKProduct* product;
    for (SKProduct* p in products) {
        if ([p.productIdentifier isEqualToString:identifier]) {
            product = p;
            break;
        }
    }

    if (product != nil) {
        SKPayment* payment = [SKPayment paymentWithProduct:product];
        [self->requestedPayments setObject:result forKey:payment];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    } else {
        result([FlutterError errorWithCode:@"ERROR" message:@"Failed to make a payment!" details:nil]);
    }
}

- (void)fetchProducts:(NSArray<NSString*>*)identifiers result:(FlutterResult)result {
    SKProductsRequest* request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:identifiers]];
    [request setDelegate:self];
    
    [fetchProducts setObject:result forKey:[NSValue valueWithNonretainedObject:request]];
    
    [request start];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    NSValue* key = [NSValue valueWithNonretainedObject:request];
    FlutterResult result = [fetchProducts objectForKey:key];
    if (result != nil) {
        [fetchProducts removeObjectForKey:key];
        result([FlutterError errorWithCode:@"ERROR" message:@"Failed to make IAP request!" details:nil]);
    }
}

- (void)productsRequest:(nonnull SKProductsRequest *)request didReceiveResponse:(nonnull SKProductsResponse *)response {
    NSValue* key = [NSValue valueWithNonretainedObject:request];
    FlutterResult result = [fetchProducts objectForKey:key];
    if (result == nil) return;
    [fetchProducts removeObjectForKey:key];
    
    NSNumberFormatter* currencyFormatter = [[NSNumberFormatter alloc] init];
    [currencyFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    
    products = [response products];
    
    NSMutableArray<NSDictionary*>* allValues = [[NSMutableArray alloc] init];
    [[response products] enumerateObjectsUsingBlock:^(SKProduct* product, NSUInteger idx, BOOL* stop) {
        [currencyFormatter setLocale:product.priceLocale];
        
        if (product.productIdentifier == nil ||
            product.localizedTitle == nil ||
            product.localizedDescription == nil ||
            product.priceLocale == nil ||
            product.price == nil) {
            return;
        }

        NSMutableDictionary<NSString*, id>* values = [[NSMutableDictionary alloc] init];
        [values setObject:@"product" forKey:@"type"];
        [values setObject:product.productIdentifier forKey:@"identifier"];
        [values setObject:[currencyFormatter stringFromNumber:product.price] forKey:@"price"];
        [values setObject:product.localizedTitle forKey:@"title"];
        [values setObject:product.localizedDescription forKey:@"description"];
        [values setObject:[NSNumber numberWithInt:(int) ceil(product.price.doubleValue * 100)] forKey:@"amount"];
        if (@available(iOS 10.0, *)) {
            [values setObject:product.priceLocale.currencyCode forKey:@"currency"];
        } else {
             [values setObject:@"USD" forKey:@"currency"];
        }

        [allValues addObject:values];
    }];

    result(allValues);
}

@end
