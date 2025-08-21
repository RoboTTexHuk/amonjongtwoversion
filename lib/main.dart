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
import 'package:url_launcher/url_launcher.dart';

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

  // --- External platform allowlists ---
  // Схемы, которые считаются внешними платформами
  final Set<String> _externalPlatformSchemes = {
    'tg',
    'telegram',
    'whatsapp',
    'mailto',
    'bnl',
  };

  // Хосты, которые считаем внешними (если ссылка http/https)
  final Set<String> _externalPlatformHosts = {
    't.me',
    'telegram.me',
    'telegram.org',
    'wa.me',
    'api.whatsapp.com',
    'mail.google.com',
    'gmail.com',
    'bnl.com',
  };

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

    // Таймер на 10 секунд: если savedata не пришёл -- переход
    Future.delayed(const Duration(seconds: 12), () {
      if (_savedataHandled == false) {
        print("load save");
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
    MethodChannel('com.example.fcm/notification').setMethodCallHandler((call) async {
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



  Future<void> _sendDataToWeb() async {
    if (_nebulaDev == null) return;

    final data = {
      "content": {
        "af_data": _sith,
        "af_id": _falcon,
        "fb_app_name": "amonjong",
        "app_name": "amonjong",
        "deep": null,
        "bundle_identifier": "com.amonjongtwostones.famojing.stonesamong.amonjongtwostones",
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
        source: '''
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
  ];

  // --- EMAIL helpers ---
  bool _isBareEmailUri(Uri uri) {
    final s = uri.scheme;
    if (s.isNotEmpty) return false;
    final raw = uri.toString();
    return raw.contains('@') && !raw.contains(' ');
  }

  Uri _convertBareEmailToMailto(Uri uri) {
    final full = uri.toString();
    final parts = full.split('?');
    final email = parts.first;
    final qp = parts.length > 1 ? Uri.splitQueryString(parts[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: qp.isEmpty ? null : qp,
    );
  }

  // --- External platform links ---
  bool _isExternalPlatformLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (_externalPlatformSchemes.contains(scheme)) return true;

    if (scheme == 'http' || scheme == 'https') {
      final host = uri.host.toLowerCase();
      if (_externalPlatformHosts.contains(host)) return true;
    }
    return false;
  }

  Uri _normalizeToWebUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();

    // Telegram
    if (scheme == 'tg' || scheme == 'telegram') {
      final qp = uri.queryParameters;
      final domain = qp['domain'];
      if (domain != null && domain.isNotEmpty) {
        return Uri.https('t.me', '/$domain', {
          if (qp['start'] != null) 'start': qp['start']!,
        });
      }
      final path = uri.path.isNotEmpty ? uri.path : '';
      return Uri.https('t.me', '/$path', uri.queryParameters.isEmpty ? null : uri.queryParameters);
    }

    // WhatsApp
    if (scheme == 'whatsapp') {
      final qp = uri.queryParameters;
      final phone = qp['phone'];
      final text = qp['text'];
      if (phone != null && phone.isNotEmpty) {
        return Uri.https('wa.me', '/${_digitsAndPlus(phone)}', {if (text != null && text.isNotEmpty) 'text': text});
      }
      return Uri.https('wa.me', '/', {if (text != null && text.isNotEmpty) 'text': text});
    }

    // BNL
    if (scheme == 'bnl') {
      final newPath = uri.path.isNotEmpty ? uri.path : '';
      return Uri.https('bnl.com', '/$newPath', uri.queryParameters.isEmpty ? null : uri.queryParameters);
    }

    return uri;
  }

  // --- Mail via in-app browser (Gmail Web) ---
  Future<bool> _openMailViaInAppBrowser(Uri mailtoUri) async {
    final gmailUri = _gmailComposeFromMailto(mailtoUri);
    return await _openInAppHttpBrowser(gmailUri);
  }

  Uri _gmailComposeFromMailto(Uri mailto) {
    final qp = mailto.queryParameters;
    final params = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailto.path.isNotEmpty) 'to': mailto.path,
      if ((qp['subject'] ?? '').isNotEmpty) 'su': qp['subject']!,
      if ((qp['body'] ?? '').isNotEmpty) 'body': qp['body']!,
      if ((qp['cc'] ?? '').isNotEmpty) 'cc': qp['cc']!,
      if ((qp['bcc'] ?? '').isNotEmpty) 'bcc': qp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', params);
  }

  // --- Open http/https in in-app browser ---
  Future<bool> _openInAppHttpBrowser(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return true;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openInAppBrowser error: $e; url=$uri');
      try {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        return false;
      }
    }
  }

  String _digitsAndPlus(String input) => input.replaceAll(RegExp(r'[^0-9+]'), '');

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
                    final savedata = args.isNotEmpty ? args[0]['savedata'] : null;
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
                    } else {
                      setState(() {
                        _savedataHandled = true; // Не переходить
                      });
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
                final webUri = navigationAction.request.url;
                final uri = webUri == null ? null : Uri.tryParse(webUri.toString());

                if (uri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                // 1) "Голый" email -> mailto
                if (_isBareEmailUri(uri)) {
                  final mailto = _convertBareEmailToMailto(uri);
                  await _openMailViaInAppBrowser(mailto);
                  return NavigationActionPolicy.CANCEL;
                }

                // 2) mailto:
                if (uri.scheme.toLowerCase() == 'mailto') {
                  await _openMailViaInAppBrowser(uri);
                  return NavigationActionPolicy.CANCEL;
                }

                // 3) внешние платформы: нормализуем к web и открываем во встроенном/внешнем браузере
                if (_isExternalPlatformLink(uri)) {
                  final normalized = _normalizeToWebUri(uri);
                  await _openInAppHttpBrowser(normalized);
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
            ),
        ],
      ),
    );
  }
}