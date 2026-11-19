import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Product ID placeholder kept for API compatibility in FOSS builds.
const String kProLifetimeProductId = 'com.vynody.pro_lifetime';

/// Minimal product details stub for FOSS / F-Droid builds without IAP plugins.
class FdroidProductDetails {
  const FdroidProductDetails({this.price = ''});

  final String price;
}

/// State of In-App Purchase (disabled in FOSS / F-Droid builds).
class IapState {
  const IapState({
    this.isAvailable = false,
    this.isLoadingProduct = false,
    this.isPurchasing = false,
    this.isRestoring = false,
    this.proProduct,
    this.errorMessage,
  });

  final bool isAvailable;
  final bool isLoadingProduct;
  final bool isPurchasing;
  final bool isRestoring;
  final FdroidProductDetails? proProduct;
  final String? errorMessage;

  IapState copyWith({
    bool? isAvailable,
    bool? isLoadingProduct,
    bool? isPurchasing,
    bool? isRestoring,
    FdroidProductDetails? proProduct,
    String? errorMessage,
    bool clearError = false,
  }) {
    return IapState(
      isAvailable: isAvailable ?? this.isAvailable,
      isLoadingProduct: isLoadingProduct ?? this.isLoadingProduct,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      isRestoring: isRestoring ?? this.isRestoring,
      proProduct: proProduct ?? this.proProduct,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// FOSS / F-Droid stub for [IapService] with zero proprietary billing dependencies.
class IapService extends ChangeNotifier {
  IapService(this._ref);

  // ignore: unused_field
  final Ref _ref;

  final IapState _state = const IapState();
  IapState get state => _state;

  Future<void> loadProducts() async {}

  Future<bool> buyPro() async => false;

  Future<void> restorePurchases({bool silent = false}) async {}

  Future<void> syncPurchasesSilently() async {}

  Future<void> redeemCode() async {}
}

/// Riverpod provider for [IapService].
final iapServiceProvider = ChangeNotifierProvider<IapService>((ref) {
  return IapService(ref);
});

/// Riverpod provider for [IapState].
final iapStateProvider = Provider<IapState>((ref) {
  final service = ref.watch(iapServiceProvider);
  return service.state;
});
