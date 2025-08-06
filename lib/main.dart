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
import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;

import 'amoMenu.dart' show GameSelectionScreen;
import 'amoPush.dart' show ObfuscatedWidget;

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

// --- NebulaDev ---
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

class _PortalScreenState extends State<PortalScreen>
    with WidgetsBindingObserver {
  late InAppWebViewController _webController;

  // --- Реальные данные NebulaDev ---
  NebulaDev? _nebulaDev;

  bool _fetching = false;
  bool _showPortal = true;
  bool _isLoading = false;
  AppsflyerSdk? _wookie;
  String _falcon = "";
  String _sith = "";
  DateTime? _suspendedAt;
  String _currentUrl = "https://mahjong-master.click";
  String? fcmToken;
  bool _savedataHandled = false; // флаг, что обработали savedata
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(const Duration(seconds: 8), () async {
      await _sendDataToWeb();

      await _sendDeviceDataToWeb();
    });
    tzdata.initializeTimeZones();

    _initNebulaDev();

    // --- слушаем токен всегда через TokenChannel ---
    TokenChannel.listen((token) {
      setState(() {
        fcmToken = token;
      });
    });

    FirebaseMessaging.onBackgroundMessage(_msgBgHandler);
    _initAppsFlyer();
    _setupChannels();
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
    // Таймер на 10 секунд: если savedata не пришёл — переход
    Future.delayed(const Duration(seconds: 12), () {
      if (_savedataHandled == false) {
        print("load save");
        //   _savedataHandled = true; // чтобы не перейти дважды
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => GameSelectionScreen()),
          (route) => false,
        );
      }
    });
  }

  Future<void> _initNebulaDev() async {
    final deviceInfo = DeviceInfoPlugin();
    String? meteorUID;
    String? vesselType;
    String? vesselBuild;

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      meteorUID = info.id;
      vesselType = "android";
      vesselBuild = info.version.release;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      meteorUID = info.identifierForVendor;
      vesselType = "ios";
      vesselBuild = info.systemVersion;
    }

    final packageInfo = await PackageInfo.fromPlatform();

    final userGalacticLocale = Platform.localeName.split('_')[0];
    final starlaneZone = tz.local.name;

    setState(() {
      _nebulaDev = NebulaDev(
        meteorUID: meteorUID,
        quantumSession: "session-${DateTime.now().millisecondsSinceEpoch}",
        vesselType: vesselType,
        vesselBuild: vesselBuild,
        starAppBuild: packageInfo.version,
        userGalacticLocale: userGalacticLocale,
        starlaneZone: starlaneZone,
        cometPush: true,
      );
    });
  }

  static Future<void> _msgBgHandler(RemoteMessage message) async {
    print('BG MSG: ${message.data}');
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
    _webController.loadUrl(
      urlRequest: URLRequest(url: WebUri("https://mahjong-master.click")),
    );
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
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((
      call,
    ) async {
      if (call.method == "onNotificationTap") {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(
          call.arguments,
        );

        print('Payload: $payload');
        print('Payload["uri"]: ${payload["uri"]}');

        final uri = payload["uri"];
        if (uri != null && !uri.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => ObfuscatedWidget(uri)),
            (route) => false,
          );
        }
      }
    });
  }

  void _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.getToken();
    // Token всегда прилетает через TokenChannel.listen
  }

  Future<void> _sendDataToWeb() async {
    if (_nebulaDev == null) return;

    final data = {
      "content": {
        "af_data": _sith,
        "af_id": _falcon,
        "fb_app_name": "amonjong",
        "app_name": "amonjong",
        "deep": null,
        "bundle_identifier":
            "com.amonjongtwostones.famojing.stonesamong.amonjongtwostones",
        "app_version": _nebulaDev?.starAppBuild,
        "apple_id": "6748683192",
        ..._nebulaDev!.asPacket(token: fcmToken),
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
      if (_nebulaDev == null) return;
      final deviceMap = _nebulaDev!.asPacket(token: fcmToken);
      await _webController.evaluateJavascript(
        source:
            '''
      localStorage.setItem('app_data', JSON.stringify(${jsonEncode(deviceMap)}));
      ''',
      );
    } finally {
      setState(() => _isLoading = false);
    }
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
    _setupChannels();
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
                    final savedata = args.isNotEmpty
                        ? args[0]['savedata']
                        : null;
                    print('datasave ' + savedata.toString());
                    // Если savedata пришёл и не пустой, и не false:

                    if (args[0]['savedata'].toString() == "false") {
                      setState(() {
                        _savedataHandled = true; // Не переходить
                      });
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
                //    await _sendDataToWeb();
                await _sendDeviceDataToWeb();
                setState(() {
                  _fetching = false;
                });
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                return NavigationActionPolicy.ALLOW;
              },
            ),
          if (!_showPortal || _fetching || _isLoading) const AmonjongLoader(),
        ],
      ),
    );
  }
}
