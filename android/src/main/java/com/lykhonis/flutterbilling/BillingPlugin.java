package com.lykhonis.flutterbilling;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.util.Log;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClient.BillingResponse;
import com.android.billingclient.api.BillingClient.SkuType;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.SkuDetails;
import com.android.billingclient.api.SkuDetailsParams;
import com.android.billingclient.api.SkuDetailsResponseListener;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

public final class BillingPlugin implements MethodCallHandler {
    private final String TAG = BillingPlugin.class.getSimpleName();

    private final Activity activity;
    private final BillingClient billingClient;
    private final Map<String, Result> pendingPurchaseRequests;
    private boolean billingServiceConnected;

    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "flutter_billing");
        channel.setMethodCallHandler(new BillingPlugin(registrar.activity()));
    }

    private BillingPlugin(Activity activity) {
        this.activity = activity;

        pendingPurchaseRequests = new HashMap<>();

        billingClient = BillingClient.newBuilder(activity)
                                     .setListener(new BillingListener())
                                     .build();

        final Application application = activity.getApplication();

        application.registerActivityLifecycleCallbacks(new LifecycleCallback() {
            @Override
            public void onActivityDestroyed(Activity activity) {
                if (activity == BillingPlugin.this.activity) {
                    application.unregisterActivityLifecycleCallbacks(this);

                    stopServiceConnection();
                }
            }
        });

        startServiceConnection(new Request() {
            @Override
            public void execute() {
                Log.d(TAG, "Billing service is ready.");
            }

            @Override
            public void failed() {
                Log.d(TAG, "Failed to setup billing service!");
            }
        });
    }

    @Override
    public void onMethodCall(MethodCall methodCall, Result result) {
        if ("fetchPurchases".equals(methodCall.method)) {
            fetchPurchases(result);
        } else if ("purchase".equals(methodCall.method)) {
            purchase(methodCall.<String>argument("identifier"), result);
        } else if ("fetchProducts".equals(methodCall.method)) {
            fetchProducts(methodCall.<List<String>>argument("identifiers"), result);
        } else {
            result.notImplemented();
        }
    }

    private void fetchProducts(final List<String> identifiers, final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                billingClient.querySkuDetailsAsync(
                        SkuDetailsParams.newBuilder()
                                        .setSkusList(identifiers)
                                        .setType(SkuType.INAPP)
                                        .build(),
                        new SkuDetailsResponseListener() {
                            @Override
                            public void onSkuDetailsResponse(int responseCode, List<SkuDetails> skuDetailsList) {
                                if (responseCode == BillingResponse.OK) {
                                    final Map<String, Map<String, Object>> products = new HashMap<>();

                                    for (SkuDetails details : skuDetailsList) {
                                        final Map<String, Object> product = new HashMap<>();
                                        product.put("price", details.getPrice());
                                        product.put("title", details.getTitle());
                                        product.put("description", details.getDescription());
                                        product.put("currency", details.getPriceCurrencyCode());
                                        product.put("amount", details.getPriceAmountMicros() / 10_000L);

                                        products.put(details.getSku(), product);
                                    }

                                    result.success(products);
                                } else {
                                    result.error("ERROR", "Failed to fetch products!", null);
                                }
                            }
                        });
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private void purchase(final String identifier, final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                final int responseCode = billingClient.launchBillingFlow(
                        activity,
                        BillingFlowParams.newBuilder()
                                         .setSku(identifier)
                                         .setType(SkuType.INAPP)
                                         .build());

                if (responseCode == BillingResponse.OK) {
                    pendingPurchaseRequests.put(identifier, result);
                } else {
                    result.error("ERROR", "Failed to launch billing flow to purchase an item with error " + responseCode, null);
                }
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private void fetchPurchases(final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                final Purchase.PurchasesResult purchasesResult = billingClient.queryPurchases(SkuType.INAPP);
                final int responseCode = purchasesResult.getResponseCode();

                if (responseCode == BillingResponse.OK) {
                    result.success(getIdentifiers(purchasesResult.getPurchasesList()));
                } else {
                    result.error("ERROR", "Failed to query purchases with error " + responseCode, null);
                }
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private List<String> getIdentifiers(List<Purchase> purchases) {
        if (purchases == null) return Collections.emptyList();

        final List<String> identifiers = new ArrayList<>(purchases.size());

        for (Purchase purchase : purchases) {
            identifiers.add(purchase.getSku());
        }

        return identifiers;
    }

    private void stopServiceConnection() {
        if (billingClient.isReady()) {
            Log.d(TAG, "Stopping billing service.");

            billingClient.endConnection();

            billingServiceConnected = false;
        }
    }

    private void startServiceConnection(final Request request) {
        billingClient.startConnection(new BillingClientStateListener() {
            @Override
            public void onBillingSetupFinished(@BillingResponse int billingResponseCode) {
                Log.d(TAG, "Billing service was setup with code " + billingResponseCode);

                if (billingResponseCode == BillingResponse.OK) {
                    billingServiceConnected = true;

                    request.execute();
                } else {
                    request.failed();
                }
            }

            @Override
            public void onBillingServiceDisconnected() {
                Log.d(TAG, "Billing service was disconnected!");

                billingServiceConnected = false;
            }
        });
    }

    private void executeServiceRequest(Request request) {
        if (billingServiceConnected) {
            request.execute();
        } else {
            startServiceConnection(request);
        }
    }

    final class BillingListener implements PurchasesUpdatedListener {
        @Override
        public void onPurchasesUpdated(int resultCode, List<Purchase> purchases) {
            final List<String> identifiers = getIdentifiers(purchases);

            for (String identifier : identifiers) {
                final Result result = pendingPurchaseRequests.remove(identifier);
                if (result == null) continue;

                if (resultCode == BillingResponse.OK) {
                    result.success(identifiers);
                } else {
                    result.error("ERROR", "Failed to purchase an item with error " + result, null);
                }
            }
        }
    }

    interface Request {
        void execute();
        void failed();
    }

    static class LifecycleCallback implements Application.ActivityLifecycleCallbacks {
        @Override
        public void onActivityCreated(Activity activity, Bundle savedInstanceState) {
        }

        @Override
        public void onActivityStarted(Activity activity) {
        }

        @Override
        public void onActivityResumed(Activity activity) {
        }

        @Override
        public void onActivityPaused(Activity activity) {
        }

        @Override
        public void onActivityStopped(Activity activity) {
        }

        @Override
        public void onActivitySaveInstanceState(Activity activity, Bundle outState) {
        }

        @Override
        public void onActivityDestroyed(Activity activity) {
        }
    }
}
