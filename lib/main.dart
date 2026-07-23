import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:v3care/view/login_screen/login_page.dart';
import 'package:v3care/view/login_screen/otp_page.dart';
import 'package:v3care/view/splash/splash_page.dart';

import '../../Utils/api.dart';
import '../../Utils/const_helper.dart';
import '../../Utils/shared_pref_helper.dart';
import 'Constants/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await SharedPrefHelper.sharedPrefHelper.initSharedPref();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyDBlhVIAkwzNSLgWAQ-g8pqh4fWNmCbaC0',
      appId: '1:1076547612792:android:a35bc3600e0920d20efd8d',
      messagingSenderId: '1076547612792',
      projectId: 'v3care-426110',
      storageBucket: 'v3care-426110.firebasestorage.app',
    ),
  );
  configLoading();
  API.onSessionExpired = handleSessionExpired;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: AppColors.primaryColor,
    // Background color of status bar
    statusBarIconBrightness: Brightness.light,
    // Color of icons (light = white icons)
    statusBarBrightness: Brightness.dark,
    // For iOS
    systemNavigationBarColor: AppColors.primaryColor,
    // Navigation bar background
    systemNavigationBarIconBrightness: Brightness.light,
    // Icons color in navigation bar
    systemNavigationBarDividerColor: AppColors.white,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'V3 Care',
      debugShowCheckedModeBanner: false,
      navigatorKey: ConstHelper.navigatorKey,
      builder: EasyLoading.init(),
      initialRoute: '/',
      home: const SplashPage(),
      routes: {
        'login': (context) => const LoginPage(),
        'otp': (context) => const OTPPage(),
      },
    );
  }
}

bool _handlingSessionExpiry = false;

/// The stored token is dead. Clear it and send the user back to login instead
/// of letting every screen keep firing requests that can only fail.
void handleSessionExpired() {
  if (_handlingSessionExpiry) return;
  _handlingSessionExpiry = true;

  SharedPrefHelper.sharedPreferences.setBool('login', false);
  SharedPrefHelper.sharedPreferences.remove('userData');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    EasyLoading.dismiss();

    if (ConstHelper.navigatorKey.currentContext != null) {
      Get.offAll(
        () => const LoginPage(),
        transition: Transition.fadeIn,
      );
      Get.snackbar(
        'Session expired',
        'Please log in again to continue.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }

    // Let a later expiry be handled again once this one has been dealt with.
    Future.delayed(
      const Duration(seconds: 3),
      () => _handlingSessionExpiry = false,
    );
  });
}

void configLoading() {
  EasyLoading.instance
    ..displayDuration = const Duration(milliseconds: 2000)
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle
    ..loadingStyle = EasyLoadingStyle.dark
    ..indicatorSize = 45.0
    ..radius = 10.0
    ..progressColor = Colors.yellow
    ..backgroundColor = Colors.green
    ..indicatorColor = Colors.yellow
    ..textColor = Colors.yellow
    ..maskColor = Colors.blue.withAlpha(128)
    ..userInteractions = false
    ..maskType = EasyLoadingMaskType.black
    ..dismissOnTap = false;
}
