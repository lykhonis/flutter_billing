#import "BillingPlugin.h"
#import <flutter_billing/flutter_billing-Swift.h>

@implementation BillingPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftBillingPlugin registerWithRegistrar:registrar];
}
@end
