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
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;


import 'main.dart' show MainClass, WebViewPage, QuantumPortalView, PortalScreen;

// FCM Background Handler
@pragma('vm:entry-point')
Future<void> backgroundHandler(RemoteMessage message) async {
  print("Message ID: ${message.messageId}");
  print("Message Data: ${message.data}");
}

class ObfuscatedWidget extends StatefulWidget with WidgetsBindingObserver {
  String initialUrl;
  ObfuscatedWidget(this.initialUrl, {super.key});
  @override
  State<ObfuscatedWidget> createState() => _ObfuscatedWidgetState(initialUrl);
}

class _ObfuscatedWidgetState extends State<ObfuscatedWidget> with WidgetsBindingObserver {
  _ObfuscatedWidgetState(this.url);

  late InAppWebViewController webViewController;
  String? token;
  String? platform;
  String? osVersion;
  String? appVersion;
  String? language;
  String? timezoneName;
  bool notificationsEnabled = true;
  bool isLoading = false;
  var showContent = true;
  final List<ContentBlocker> contentBlockers = [];
  String url;
  DateTime? pausedTime;
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
      pausedTime = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && pausedTime != null) {
        final now = DateTime.now();
        final durationInBackground = now.difference(pausedTime!);
        if (durationInBackground > const Duration(minutes: 25)) {
          _rebuildApp();
        }
      }
      pausedTime = null;
    }
  }

  void _rebuildApp() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => PortalScreen(""),
        ),
            (route) => false,
      );
    });
  }

  @override
  void initState() {
    super.initState();


    WidgetsBinding.instance.addObserver(this);
    for (final adFilter in adBlockList) {
      contentBlockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: adFilter),
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

    FirebaseMessaging.onBackgroundMessage(backgroundHandler);
    // _initializeTracking();
    _initializeAppFlyer();
    _initializeFirebase();
    _loadDeviceInfo();
    _setupFCMListeners();
    _x3();

    Future.delayed(const Duration(seconds: 2), () {
      //    _initializeTracking();
    });
    Future.delayed(const Duration(seconds: 6), () {
      _sendDataToWebView();
    });
  }

  void _setupFCMListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['uri'] != null) {
        _loadUrl(message.data['uri'].toString());
      } else {
        _reloadWebView();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['uri'] != null) {
        _loadUrl(message.data['uri'].toString());
      } else {
        _reloadWebView();
      }
    });
  }

  void _loadUrl(String uri) async {
    if (webViewController != null) {
      await webViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri)),
      );
    }
  }

  void _reloadWebView() async {
    Future.delayed(const Duration(seconds: 3), () {
      if (webViewController != null) {
        webViewController.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)),
        );
      }
    });
  }

  Future<void> _initializeFirebase() async {
    FirebaseMessaging firebaseMessaging = FirebaseMessaging.instance;
    NotificationSettings settings = await firebaseMessaging.requestPermission(alert: true, badge: true, sound: true);
    token = await firebaseMessaging.getToken();
  }



  AppsflyerSdk? appsFlyerSdk;
  String appsFlyerData = "";
  String appsFlyerId = "";

  void _initializeAppFlyer() {
    final AppsFlyerOptions options = AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6745261464",
      showDebug: true,
    );
    appsFlyerSdk = AppsflyerSdk(options);
    appsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    appsFlyerSdk?.startSDK(
      onSuccess: () => print("AppsFlyer OK"),
      onError: (int code, String message) => print("AppsFlyer Error: $code $message"),
    );
    appsFlyerSdk?.onInstallConversionData((data) {
      setState(() {
        appsFlyerData = data.toString();
        appsFlyerId = data['payload']['af_status'].toString();
      });
    });
    appsFlyerSdk?.getAppsFlyerUID().then((id) {
      setState(() {
        appsFlyerId = id.toString();
      });
    });
  }

  Future<void> _sendDataToWebView() async {
    print("Conversion Data: $appsFlyerData");
    final Map<String, dynamic> requestData = {
      "content": {
        "af_data": "$appsFlyerData",
        "af_id": "$appsFlyerId",
        "fb_app_name": "amonjong",
        "app_name": "amonjong",
        "deep": null,
        "bundle_identifier": "com.amonjongtwostones.famojing.stonesamong.amonjongtwostones",
        "app_version": "1.0.0",
        "apple_id": "6748683192",
        "device_id": platform ?? "default_device_id",
        "instance_id": osVersion ?? "default_instance_id",
        "platform": appVersion ?? "unknown_platform",
        "os_version": language ?? "default_os_version",
        "app_version": timezoneName ?? "default_app_version",
        "language": language ?? "en",
        "timezone": timezoneName ?? "UTC",
        "push_enabled": notificationsEnabled,
        "useruid": "$appsFlyerId",
      },
    };

    final jsonData = jsonEncode(requestData);
    print("My JSON Data: $jsonData");
    await webViewController.evaluateJavascript(
      source: "sendRawData(${jsonEncode(jsonData)});",
    );
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        platform = androidInfo.id;
        appVersion = "android";
        osVersion = androidInfo.version.release;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        platform = iosInfo.identifierForVendor;
        appVersion = "ios";
        osVersion = iosInfo.systemVersion;
      }
      final packageInfo = await PackageInfo.fromPlatform();
      language = Platform.localeName.split('_')[0];
      timezoneName = timezone.local.name;
    } catch (e) {
      debugPrint("Device Info Error: $e");
    }
  }
  void _x3() {
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          call.arguments,
        );
        print("URI data"+data['uri'].toString());
        if (data["uri"] != null && !data["uri"].contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) =>ObfuscatedWidget(data["uri"])),
                (route) => false,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _x3();
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              disableDefaultErrorPage: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              allowsPictureInPictureMediaPlayback: true,
              useOnDownloadStart: true,
              //  contentBlockers: contentBlockers,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            initialUrlRequest: URLRequest(url: WebUri(url)),
            onWebViewCreated: (controller) {
              webViewController = controller;
              webViewController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    print("JS Args: $args");
                    return args.reduce((value, element) => value + element);
                  });
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(
                source: "console.log('Hello from JS!');",
              );
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
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