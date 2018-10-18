package com.lykhonis.flutterbilling;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.util.Log;

import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClient.BillingResponse;
import com.android.billingclient.api.BillingClient.FeatureType;
import com.android.billingclient.api.BillingClient.SkuType;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.ConsumeResponseListener;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.SkuDetails;
import com.android.billingclient.api.SkuDetailsParams;
import com.android.billingclient.api.SkuDetailsResponseListener;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;

public final class BillingPlugin implements MethodCallHandler {
    private final String TAG = BillingPlugin.class.getSimpleName();

    private enum BillingServiceStatus {
        IDLE, STARTING, READY
    }

    private final Activity activity;
    private final BillingClient billingClient;
    private final List<PurchaseRequest> pendingPurchaseRequests;
    private final Deque<Request> pendingRequests;
    private BillingServiceStatus billingServiceStatus;

    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "flutter_billing");
        channel.setMethodCallHandler(new BillingPlugin(registrar.activity()));
    }

    private BillingPlugin(Activity activity) {
        this.activity = activity;

        pendingPurchaseRequests = new ArrayList<>();
        pendingRequests = new ArrayDeque<>();
        billingServiceStatus = BillingServiceStatus.IDLE;

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

        executeServiceRequest(new Request() {
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
            purchase(methodCall.<String>argument("identifier"), methodCall.<Boolean>argument("consume"), result);
        } else if ("fetchProducts".equals(methodCall.method)) {
            fetchProducts(methodCall.<List<String>>argument("identifiers"), result);
        } else if ("fetchSubscriptions".equals(methodCall.method)) {
            fetchSubscriptions(methodCall.<List<String>>argument("identifiers"), result);
        } else if ("subscribe".equals(methodCall.method)) {
            subscribe(methodCall.<String>argument("identifier"), result);
        } else if ("getReceipt".equals(methodCall.method)) {
            result.success("");
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
                                    List<Map<String, Object>> products = getProductsFromSkuDetails(skuDetailsList);
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

    private void fetchSubscriptions(final List<String> identifiers, final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                billingClient.querySkuDetailsAsync(
                        SkuDetailsParams.newBuilder()
                                        .setSkusList(identifiers)
                                        .setType(SkuType.SUBS)
                                        .build(),
                        new SkuDetailsResponseListener() {
                            @Override
                            public void onSkuDetailsResponse(int responseCode, List<SkuDetails> skuDetailsList) {
                                if (responseCode == BillingResponse.OK) {
                                    List<Map<String, Object>> products = getProductsFromSkuDetails(skuDetailsList);
                                    result.success(products);
                                } else {
                                    result.error("ERROR", "Failed to fetch Subscriptions!", null);
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

    private List<Map<String, Object>> getProductsFromSkuDetails(List<SkuDetails> skuDetailsList) {
        List<Map<String, Object>> products = new ArrayList<>();

        for (SkuDetails details : skuDetailsList) {
            String type = getProductType(details.getType());
            if (type == null) continue; // skip unsupported sku type

            Map<String, Object> product = new HashMap<>();
            product.put("identifier", details.getSku());
            product.put("price", details.getPrice());
            product.put("title", details.getTitle());
            product.put("description", details.getDescription());
            product.put("currency", details.getPriceCurrencyCode());
            product.put("amount", details.getPriceAmountMicros() / 10_000L);
            product.put("type", type);
            products.add(product);
        }

        return products;
    }

    private String getProductType(String skuType) {
        if (SkuType.INAPP.equals(skuType)) return "product";
        if (SkuType.SUBS.equals(skuType)) return "subscription";
        return null; // ?
    }

    private void purchase(final String identifier, final Boolean consume, final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                int responseCode = billingClient.launchBillingFlow(
                        activity,
                        BillingFlowParams.newBuilder()
                                         .setSku(identifier)
                                         .setType(SkuType.INAPP)
                                         .build());

                if (responseCode == BillingResponse.OK) {
                    PurchaseRequest request = new PurchaseRequest(identifier, consume, result);
                    pendingPurchaseRequests.add(request);
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

    private void subscribe(final String identifier, final Result result) {
        executeServiceRequest(new Request() {
            @Override
            public void execute() {
                int subscriptionSupportResponse = billingClient.isFeatureSupported(FeatureType.SUBSCRIPTIONS);
                if (BillingResponse.OK != subscriptionSupportResponse) {
                    result.error("NOT SUPPORTED", "Subscriptions are not supported.", null);
                    return;
                }

                int responseCode = billingClient.launchBillingFlow(
                        activity,
                        BillingFlowParams.newBuilder()
                                         .setSku(identifier)
                                         .setType(SkuType.SUBS)
                                         .build());

                if (responseCode == BillingResponse.OK) {
                    PurchaseRequest request = new PurchaseRequest(identifier, result);
                    pendingPurchaseRequests.add(request);
                } else {
                    result.error("ERROR", "Failed to subscribe with error " + responseCode, null);
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
                List<String> identifiers = new ArrayList<>();

                Purchase.PurchasesResult purchasesResult = billingClient.queryPurchases(SkuType.INAPP);
                if (purchasesResult.getResponseCode() == BillingResponse.OK) {
                    identifiers.addAll(getIdentifiers(purchasesResult.getPurchasesList()));
                } else {
                    Log.w(TAG, "Failed to query purchases for in app products " +
                            "with error " + purchasesResult.getResponseCode());
                }

                purchasesResult = billingClient.queryPurchases(SkuType.SUBS);
                if (purchasesResult.getResponseCode() == BillingResponse.OK) {
                    identifiers.addAll(getIdentifiers(purchasesResult.getPurchasesList()));
                } else {
                    Log.w(TAG, "Failed to query purchases for in app subscriptions " +
                            "with error " + purchasesResult.getResponseCode());
                }

                result.success(identifiers);
            }

            @Override
            public void failed() {
                result.error("UNAVAILABLE", "Billing service is unavailable!", null);
            }
        });
    }

    private Purchase findPurchase(List<Purchase> purchases, String identifier) {
        if (purchases == null) return null;
        for (Purchase purchase : purchases) {
            if (identifier.equals(purchase.getSku())) return purchase;
        }
        return null;
    }

    private List<String> getIdentifiers(List<Purchase> purchases) {
        if (purchases == null) return Collections.emptyList();
        List<String> identifiers = new ArrayList<>(purchases.size());
        for (Purchase purchase : purchases) {
            identifiers.add(purchase.getSku());
        }
        return identifiers;
    }

    private void stopServiceConnection() {
        if (billingClient.isReady()) {
            Log.d(TAG, "Stopping billing service.");

            billingClient.endConnection();
            billingServiceStatus = BillingServiceStatus.IDLE;
        }
    }

    private void startServiceConnection() {
        if (billingServiceStatus != BillingServiceStatus.IDLE) return;
        billingServiceStatus = BillingServiceStatus.STARTING;
        billingClient.startConnection(new BillingClientStateListener() {
            @Override
            public void onBillingSetupFinished(@BillingResponse int billingResponseCode) {
                Log.d(TAG, "Billing service was setup with code " + billingResponseCode);

                billingServiceStatus = billingResponseCode == BillingResponse.OK ? BillingServiceStatus.READY : BillingServiceStatus.IDLE;
                Request request;

                while ((request = pendingRequests.poll()) != null) {
                    if (billingServiceStatus == BillingServiceStatus.READY) {
                        request.execute();
                    } else {
                        request.failed();
                    }
                }
            }

            @Override
            public void onBillingServiceDisconnected() {
                Log.d(TAG, "Billing service was disconnected!");
                billingServiceStatus = BillingServiceStatus.IDLE;
            }
        });
    }

    private void executeServiceRequest(Request request) {
        if (billingServiceStatus == BillingServiceStatus.READY) {
            request.execute();
        } else {
            pendingRequests.add(request);
            startServiceConnection();
        }
    }

    final class BillingListener implements PurchasesUpdatedListener {
        @Override
        public void onPurchasesUpdated(int resultCode, List<Purchase> purchases) {
            if (resultCode == BillingResponse.OK && purchases != null) {
                Iterator<PurchaseRequest> iterator = pendingPurchaseRequests.iterator();
                while (iterator.hasNext()) {
                    PurchaseRequest request = iterator.next();
                    if (request.handlePurchases(purchases)) {
                        iterator.remove();
                    }
                }
            } else {
                for (PurchaseRequest request : pendingPurchaseRequests) {
                    request.handleError(resultCode);
                }
                pendingPurchaseRequests.clear();
            }
        }
    }

    final class PurchaseRequest {
        private final String identifier;
        private final Result result;
        private final boolean consume;

        PurchaseRequest(String identifier, boolean consume, Result result) {
            this.identifier = identifier;
            this.result = result;
            this.consume = consume;
        }

        PurchaseRequest(String identifier, Result result) {
            this(identifier, false, result);
        }

        boolean handlePurchases(final List<Purchase> purchases) {
            Purchase purchase = findPurchase(purchases, identifier);
            if (purchase == null) return false;
            if (consume) {
                billingClient.consumeAsync(purchase.getPurchaseToken(), new ConsumeResponseListener() {
                    @Override
                    public void onConsumeResponse(int responseCode, String purchaseToken) {
                        if (responseCode != BillingResponse.OK) {
                            Log.w(TAG, "Failed to consume product with code " + responseCode);
                        }
                        result.success(getIdentifiers(purchases));
                    }
                });
            } else {
                result.success(getIdentifiers(purchases));
            }
            return true;
        }

        void handleError(int resultCode) {
            result.error("ERROR", "Failed to purchase an item with error " + resultCode, null);
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
