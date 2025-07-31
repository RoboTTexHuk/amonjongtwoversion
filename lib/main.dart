import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:appsflyer_sdk/appsflyer_sdk.dart' show AppsFlyerOptions, AppsflyerSdk;


import 'amoMenu.dart' show GameSelectionScreen;
import 'amoPush.dart' show ObfuscatedWidget;

Future<void> _msgBgHandler(RemoteMessage message) async {
  print('BG MSG: ${message.data}');
}

// --- DeviceManager ---
class DeviceManager {
  String? deviceId;
  String? instanceId = "instance-unique-id";
  String? platformType;
  String? platformVersion;
  String? appVersion;
  String? language;
  String? timezone;
  bool notificationsEnabled = true;

  Future<void> initDevice() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id;
      platformType = "android";
      platformVersion = info.version.release;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor;
      platformType = "ios";
      platformVersion = info.systemVersion;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    appVersion = packageInfo.version;
    language = Platform.localeName.split('_')[0];
    timezone = tz.local.name;
  }

  Map<String, dynamic> toMap({String? fcmToken}) {
    return {
      "fcm_token": fcmToken ?? 'no_token',
      "device_id": deviceId ?? 'no_device',
      "app_name": "onepursuit",
      "instance_id": instanceId ?? 'no_instance',
      "platform": platformType ?? 'no_type',
      "os_version": platformVersion ?? 'no_os',
      "app_version": appVersion ?? 'no_app',
      "language": language ?? 'en',
      "timezone": timezone ?? 'UTC',
      "push_enabled": notificationsEnabled,
    };
  }
}

// --- TokenChannel ---
class TokenChannel {
  static const MethodChannel _c = MethodChannel('com.example.fcm/token');
  static void listen(Function(String token) onToken) {
    _c.setMethodCallHandler((call) async {
      if (call.method == 'setToken') {
        final String token = call.arguments as String;
        onToken(token);
      }
    });
  }
}

// --- CosmosData и NebulaDev ---
class CosmosData {
  final String? nebulaMetrics;
  final String? galaxyID;
  CosmosData({this.nebulaMetrics, this.galaxyID});
}
class NebulaDev {
  final String? meteorUID;
  final String? quantumSession;
  final String? vesselType;
  final String? vesselBuild;
  final String? starAppBuild;
  final String? userGalacticLocale;
  final String? starlaneZone;
  final bool cometPush;
  NebulaDev({
    this.meteorUID,
    this.quantumSession,
    this.vesselType,
    this.vesselBuild,
    this.starAppBuild,
    this.userGalacticLocale,
    this.starlaneZone,
    this.cometPush = true,
  });
  Map<String, dynamic> asPacket({String? token}) => {
    "fcm_token": token ?? 'missing_token',
    "device_id": meteorUID ?? 'missing_id',
    "app_name": "amonjong",
    "instance_id": quantumSession ?? 'missing_session',
    "platform": vesselType ?? 'missing_system',
    "os_version": vesselBuild ?? 'missing_build',
    "app_version": starAppBuild ?? 'missing_app',
    "language": userGalacticLocale ?? 'en',
    "timezone": starlaneZone ?? 'UTC',
    "push_enabled": cometPush,
  };
}



class AmonjongLoader extends StatelessWidget {
  const AmonjongLoader({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await Firebase.initializeApp();
  runApp(MaterialApp(home: PortalScreen(null)));
}

class PortalScreen extends StatefulWidget {
  final String? signalBeacon;
  const PortalScreen(this.signalBeacon, {super.key});
  @override
  State<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends State<PortalScreen> with WidgetsBindingObserver {
  late InAppWebViewController _webController;

  final _cosmos = CosmosData(nebulaMetrics: "metrics_42", galaxyID: "galaxy_123");
  final _nebulaDev = NebulaDev(
    meteorUID: "meteor_abc",
    quantumSession: "quantum_456",
    vesselType: "spaceship",
    vesselBuild: "os_2.1.1",
    starAppBuild: "app_1.0.0",
    userGalacticLocale: "en",
    starlaneZone: "Andromeda",
    cometPush: true,
  );
  final DeviceManager _deviceManager = DeviceManager();

  bool _fetching = false;
  bool _showPortal = true;
  bool _isLoading = false;
  AppsflyerSdk? _wookie;
  String _falcon = "";
  String _sith = "";
  DateTime? _suspendedAt;
  String _currentUrl = "https://mahjong-master.click";
  String? fcmToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    tzdata.initializeTimeZones();

    _initDeviceManager();

    TokenChannel.listen((token) {
      setState(() {
        fcmToken = token;
      });
    });

    FirebaseMessaging.onBackgroundMessage(_msgBgHandler);
    _initAppsFlyer();
    _setupChannels();
    _initData();
    _initFCM();

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _loadUrl(msg.data['uri'].toString());
      } else {
        _resetUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
      if (msg.data['uri'] != null) {
        _loadUrl(msg.data['uri'].toString());
      } else {
        _resetUrl();
      }
    });

    Future.delayed(const Duration(seconds: 6), () {
      _sendDataToWeb();
      sendDataRaw();
      _sendDeviceDataToWeb();
    });
  }

  Future<void> _initDeviceManager() async {
    await _deviceManager.initDevice();
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _suspendedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && _suspendedAt != null) {
        final now = DateTime.now();
        final backgroundDuration = now.difference(_suspendedAt!);
        if (backgroundDuration > const Duration(minutes: 25)) {
          _forcePortalRebuild();
        }
      }
      _suspendedAt = null;
    }
  }

  void _forcePortalRebuild() {
    setState(() {
      _showPortal = false;
    });
    Future.delayed(const Duration(milliseconds: 50), () {
      setState(() {
        _showPortal = true;
      });
    });
  }

  void _loadUrl(String url) {
    _webController.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    setState(() {
      _currentUrl = url;
    });
  }

  void _resetUrl() {
    _webController.loadUrl(urlRequest: URLRequest(url: WebUri("https://mahjong-master.click")));
    setState(() {
      _currentUrl = "https://mahjong-master.click";
    });
  }

  void _initAppsFlyer() {
    final AppsFlyerOptions opts = AppsFlyerOptions(
      afDevKey: "qsBLmy7dAXDQhowM8V3ca4",
      appId: "6748683192",
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );
    _wookie = AppsflyerSdk(opts);
    _wookie?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );
    _wookie?.startSDK();
    _wookie?.onInstallConversionData((res) {
      setState(() {
        _sith = res.toString();
      });
    });
    _wookie!.getAppsFlyerUID().then((value) {
      setState(() {
        _falcon = value.toString();
      });
    });
  }

  void _setupChannels() {
    // FCM notification tap
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(call.arguments);

        print('Payload: $payload');
        print('Payload["uri"]: ${payload["uri"]}');

        final uri = payload["uri"];
        if (uri != null && uri.toString().isNotEmpty) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => ObfuscatedWidget(uri)),
                (route) => false,
          );
        }
      }
    });
  }

  void _initData() {
    // Place for additional data inits if needed
  }

  void _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.getToken();
    // Token is handled via TokenChannel
  }

  Future<void> _sendDataToWeb() async {
    final data = {
      "content": {
        "af_data": _sith,
        "af_id": _falcon,
        "fb_app_name": "amonjong",
        "app_name": "amonjong",
        "deep": null,
        "bundle_identifier": "com.amonjongtwostones.famojing.stonesamong.amonjongtwostones",
        "app_version": "1.0.0",
        "apple_id": "6748683192",
        "fcm_token": fcmToken ?? "no_token",
        "device_id": _nebulaDev.meteorUID ?? "no_device",
        "instance_id": _nebulaDev.quantumSession ?? "no_instance",
        "platform": _nebulaDev.vesselType ?? "no_type",
        "os_version": _nebulaDev.vesselBuild ?? "no_os",
        "app_version": _nebulaDev.starAppBuild ?? "no_app",
        "language": _nebulaDev.userGalacticLocale ?? "en",
        "timezone": _nebulaDev.starlaneZone ?? "UTC",
        "push_enabled": _nebulaDev.cometPush,
        "useruid": _falcon,
      },
    };

    final jsonString = jsonEncode(data);
    print("Cosmos JSON: $jsonString");
    if (_webController != null) {
      await _webController.evaluateJavascript(
        source: "sendRawData(${jsonEncode(jsonString)});",
      );
    }
  }

  Future<void> _sendDeviceDataToWeb() async {
    setState(() => _isLoading = true);
    try {
      final deviceMap = _deviceManager.toMap(fcmToken: fcmToken);
      await _webController.evaluateJavascript(source: '''
      localStorage.setItem('app_data', JSON.stringify(${jsonEncode(deviceMap)}));
      ''');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void sendDataRaw() {
    print('sendDataRaw called');
  }

  final List<ContentBlocker> _lll = [
    ContentBlocker(
      trigger: ContentBlockerTrigger(urlFilter: ".*.doubleclick.net/.*"),
      action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
    ),
    // ... можно добавить остальные фильтры ...
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_showPortal)
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                // contentBlockers: _lll,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
              ),
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              onWebViewCreated: (controller) {
                _webController = controller;

                _webController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (args) {
                    print("JS args: $args");
                    print("From the JavaScript side:");
                    print("ResRes" + args[0]['savedata'].toString());
                    if (args[0]['savedata'].toString() == "false") {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameSelectionScreen(),
                        ),
                            (route) => false,
                      );
                    }
                    return args.reduce((curr, next) => curr + next);
                  },
                );
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _fetching = true;
                });
              },
              onLoadStop: (controller, url) async {
                await controller.evaluateJavascript(
                  source: "console.log('Portal loaded!');",
                );
                await _sendDataToWeb();
                await _sendDeviceDataToWeb();
                setState(() {
                  _fetching = false;
                });
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                return NavigationActionPolicy.ALLOW;
              },
            ),
          if (!_showPortal || _fetching || _isLoading)
            const AmonjongLoader(),
        ],
      ),
    );
  }
}