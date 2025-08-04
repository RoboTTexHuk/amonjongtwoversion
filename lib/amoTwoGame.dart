import 'dart:convert';
import 'dart:io';


import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tzA;
import 'package:timezone/timezone.dart' as tzB;
import 'package:http/http.dart' as httpA;



import 'main.dart' show AAAQ, BBBWebPage;

// FCM Background Handler
@pragma('vm:entry-point')
Future<void> msgBackgroundHandler(RemoteMessage msg) async {
  print("BG Message: ${msg.messageId}");
  print("BG Data: ${msg.data}");
}

class ExampleWebWidgetTWO extends StatefulWidget with WidgetsBindingObserver  {
  String paramA;
  ExampleWebWidgetTWO(this.paramA, {super.key});
  @override
  State<ExampleWebWidgetTWO> createState() => _ExampleWebWidgetTWOState(paramA);
}

class _ExampleWebWidgetTWOState extends State<ExampleWebWidgetTWO> with WidgetsBindingObserver {
  _ExampleWebWidgetTWOState(this.initUrl);

  late InAppWebViewController webCtrl;
  String? deviceId;
  String? instId;
  String? platform;
  String? osVersion;
  String? appVer;
  String? lang;
  String? timezone;
  bool pushEnabled = true;
  bool isLoading = false;
  var allowContent = true;
  final List<ContentBlocker> contentBlockers = [];
  String initUrl;
  DateTime? backgroundTime;
  final List<String> adBlockList = [
    ".*.doubleclick.net/.*",
    ".*.ads.pubmatic.com/.*",
    ".*.googlesyndication.com/.*",
    ".*.google-analytics.com/.*",
    ".*.adservice.google.*/.*",
    ".*.adbrite.com/.*",
    ".*.exponential.com/.*",
    ".*.quantserve.com/.*",
    ".*.scorecardresearch.com/.*",
    ".*.zedo.com/.*",
    ".*.adsafeprotected.com/.*",
    ".*.teads.tv/.*",
    ".*.outbrain.com/.*",
  ];


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      backgroundTime = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && backgroundTime != null) {
        final now = DateTime.now();
        final duration = now.difference(backgroundTime!);
        // Если приложение было в фоне больше 25 минут (1500 секунд)
        if (duration > const Duration(minutes: 25)) {
          //  reloadPage();
        }
      }
      backgroundTime = null;
    }
  }



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    for (final f in adBlockList) {
      contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: f),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ));
    }
    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
        ContentBlockerTriggerResourceType.RAW
      ]),
      action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK, selector: ".notification"),
    ));

    contentBlockers.add(ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
        ContentBlockerTriggerResourceType.RAW
      ]),
      action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".privacy-info"),
    ));

    contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: ".*",
        ),
        action: ContentBlockerAction(
            type: ContentBlockerActionType.CSS_DISPLAY_NONE,
            selector: ".banner, .banners, .ads, .ad, .advert")));

    FirebaseMessaging.onBackgroundMessage(msgBackgroundHandler);
    // setupTracking();
    setupAppsFlyer();
    setupNotificationChannel();
    setupDeviceInfo();
    requestPushPermissions();

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        loadUri(msg.data['uri'].toString());
      } else {
        loadHome();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        loadUri(msg.data['uri'].toString());
      } else {
        loadHome();
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      // setupTracking();
    });
    Future.delayed(const Duration(seconds: 6), () {
      sendUserData();
    });
  }

  void setupNotificationChannel() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
        if (args["uri"] != null && !args["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => ExampleWebWidgetTWO(args["uri"])),
                (route) => false,
          );
        }
      }
    });
  }

  void loadUri(String url) async {
    if (webCtrl != null) {
      await webCtrl.loadUrl(
        urlRequest: URLRequest(url: WebUri(url)),
      );
    }
  }

  void loadHome() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (webCtrl != null) {
        webCtrl.loadUrl(
          urlRequest: URLRequest(url: WebUri(initUrl)),
        );
      }
    });
  }

  Future<void> requestPushPermissions() async {
    FirebaseMessaging fcm = FirebaseMessaging.instance;
    NotificationSettings ns = await fcm.requestPermission(alert: true, badge: true, sound: true);
    instId = await fcm.getToken();
  }



  AppsflyerSdk? appsFlyerInstance;
  String appsFlyerUID = "";
  String appsFlyerData = "";

  void setupAppsFlyer() {
    final AppsFlyerOptions opts = AppsFlyerOptions(
        afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
        appId: "6745261464",
        showDebug: true,
        timeToWaitForATTUserAuthorization: 0
    );
    appsFlyerInstance = AppsflyerSdk(opts);
    appsFlyerInstance?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    appsFlyerInstance?.startSDK(
      onSuccess: () => print("AppsFlyer OK"),
      onError: (int code, String err) => print("AppsFlyer ERR $code $err"),
    );
    appsFlyerInstance?.onInstallConversionData((data) {
      setState(() {
        appsFlyerData = data.toString();
        appsFlyerUID = data['payload']['af_status'].toString();
      });
    });
    appsFlyerInstance?.getAppsFlyerUID().then((uid) {
      setState(() {
        appsFlyerUID = uid.toString();
      });
    });
  }

  Future<void> sendUserData() async {
    print("CONV DATA: $appsFlyerData");
    final Map<String, dynamic> userJson = {
      "content": {
        "af_data": "$appsFlyerData",
        "af_id": "$appsFlyerUID",
        "fb_app_name": "amon2g",
        "app_name": "amon2g",
        "deep": null,
        "bundle_identifier": "com.amontwog.amontwog.amontwog",
        "app_version": "1.0.0",
        "apple_id": "6747983307",
        "device_id": deviceId ?? "default_device_id",
        "instance_id": instId ?? "default_instance_id",
        "platform": platform ?? "unknown_platform",
        "os_version": osVersion ?? "default_os_version",
        "app_version": appVer ?? "default_app_version",
        "language": lang ?? "en",
        "timezone": lang ?? "UTC",
        "push_enabled": pushEnabled,
        "useruid": "$appsFlyerUID",
      },
    };

    final encoded = jsonEncode(userJson);
    print("My json $encoded");
    await webCtrl.evaluateJavascript(
      source: "sendRawData(${jsonEncode(encoded)});",
    );
  }

  Future<void> setupDeviceInfo() async {
    try {
      final devicePlugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await devicePlugin.androidInfo;
        deviceId = androidInfo.id;
        platform = "android";
        osVersion = androidInfo.version.release;
      } else if (Platform.isIOS) {
        final iosInfo = await devicePlugin.iosInfo;
        deviceId = iosInfo.identifierForVendor;
        platform = "ios";
        osVersion = iosInfo.systemVersion;
      }
      final pkgInfo = await PackageInfo.fromPlatform();
      appVer = pkgInfo.version;
      lang = Platform.localeName.split('_')[0];
      lang = tzB.local.name;
      instId = "d67f89a0-1234-5678-9abc-def012345678";
      if (webCtrl != null) {
      }
    } catch (e) {
      debugPrint("Init error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
           //   userAgent:"Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              allowsPictureInPictureMediaPlayback: true,
              useOnDownloadStart: true,
              contentBlockers: contentBlockers,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(initUrl)),
            onWebViewCreated: (ctrl) {
              webCtrl = ctrl;
              webCtrl.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    print("JS args: $args");
                    return args.reduce((a, b) => a + b);
                  });
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(
                source: "console.log('Hello from JS!');",
              );
            },
            shouldOverrideUrlLoading: (controller, navAction) async {
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (isLoading)
            Visibility(
              visible: !isLoading,
              child: SizedBox.expand(
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      backgroundColor: Colors.grey.shade800,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.yellow),
                      strokeWidth: 8,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}