import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

// Instance pour les notifications locales
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

// Handler des notifications en arrière-plan
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message received: ${message.messageId}');
}

// Variable globale pour stocker l'URL de notification
String? _notificationUrl;

// Variable globale pour stocker la référence de l'instance de MyHomePageState
_MyHomePageState? _currentAppInstance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialiser les notifications locales
  await _initializeLocalNotifications();
  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Vérifier s'il y a une notification au démarrage
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _notificationUrl = initialMessage.data['url'];
  }
  
  runApp(MyApp(initialUrl: _notificationUrl));
}

// SOLUTION PROBLÈME 2: Initialisation des notifications locales
Future<void> _initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
      // Gérer le clic sur notification locale
      final String? payload = notificationResponse.payload;
      if (payload != null && _currentAppInstance != null) {
        print('Notification locale cliquée avec payload: $payload');
        // Rediriger vers l'URL dans l'app
        _currentAppInstance!._handleNotificationUrl(payload);
      }
    },
  );
}

class MyApp extends StatelessWidget {
  final String? initialUrl;
  
  const MyApp({super.key, this.initialUrl});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equiphorse App',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: MyHomePage(initialUrl: initialUrl),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final String? initialUrl;
  
  const MyHomePage({super.key, this.initialUrl});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  late WebViewController _controller;
  bool _isDialogVisible = false;
  bool _notificationsAllowed = false;
  bool _isWebViewReady = false;
  int _loadingCount = 0;
  
  // SOLUTION PROBLÈME 1: Stack pour gérer l'historique de navigation
  final List<String> _navigationHistory = [];
  static const String homeUrl = 'https://equiphorse.tn/equiphorse/fr/';

  @override
  void initState() {
    super.initState();
    // Enregistrer cette instance comme instance courante
    _currentAppInstance = this;
    
    WidgetsBinding.instance.addObserver(this);
    _initWebView();
    _checkNotificationStatus();
    _showNotificationDialogAfterDelay();
    _setupNotificationListeners();
  }

  void _initWebView() {
    String startUrl = widget.initialUrl ?? homeUrl;

    if (widget.initialUrl != null) {
      _navigationHistory.add(homeUrl);
    }
    _navigationHistory.add(startUrl);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // AJOUT: Intercepter les clics pour afficher le spinner immédiatement
      ..addJavaScriptChannel(
        'FlutterClickHandler',
        onMessageReceived: (JavaScriptMessage message) {
          // Dès qu'un clic est détecté, afficher le spinner immédiatement
          if (mounted) {
            setState(() {
              _isWebViewReady = false;
            });
            print('Clic détecté, spinner affiché immédiatement');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _loadingCount++;
              // Ne pas modifier _isWebViewReady ici, il peut déjà être à false depuis le clic
            });
            if (_navigationHistory.isEmpty || _navigationHistory.last != url) {
              _navigationHistory.add(url);
            }
          },
          onPageFinished: (String url) {
            setState(() {
              _loadingCount = (_loadingCount > 0) ? _loadingCount - 1 : 0;
              _isWebViewReady = _loadingCount == 0;
            });
            // Réinjecter le script après chaque navigation
            _injectClickInterceptor();
          },
          // AJOUT: Gestion des erreurs pour éviter spinner infini
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _loadingCount = (_loadingCount > 0) ? _loadingCount - 1 : 0;
              _isWebViewReady = _loadingCount == 0;
            });
            print('Erreur de chargement: ${error.description}');
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith('https://equiphorse.tn')) {
              // MODIFICATION: Afficher le spinner dès la décision de navigation
              setState(() {
                _isWebViewReady = false;
              });
              return NavigationDecision.navigate;
            }
            _openExternalLink(request.url);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(startUrl));

    // Injecter le script JavaScript après un délai
    Future.delayed(const Duration(seconds: 1), () {
      _injectClickInterceptor();
    });
  }

  // NOUVELLE MÉTHODE: Injecter le JavaScript pour intercepter les clics
  Future<void> _injectClickInterceptor() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          // Supprimer les anciens listeners pour éviter les doublons
          if (window.flutterClickListenerAdded) {
            return;
          }
          window.flutterClickListenerAdded = true;
          
          // Intercepter tous les clics sur les liens
          document.addEventListener('click', function(event) {
            var target = event.target;
            
            // Remonter jusqu'à trouver un lien ou un élément cliquable
            while (target && target !== document) {
              if (target.tagName === 'A' || 
                  target.onclick || 
                  target.getAttribute('href') ||
                  target.classList.contains('btn') ||
                  target.classList.contains('button')) {
                
                // Vérifier si c'est une navigation interne
                var href = target.href || target.getAttribute('href') || '';
                if (href && (href.includes('equiphorse.tn') || href.startsWith('/') || href.startsWith('#') === false)) {
                  FlutterClickHandler.postMessage('link_clicked');
                  break;
                }
              }
              target = target.parentElement;
            }
          });
          
          // Intercepter aussi les soumissions de formulaires
          document.addEventListener('submit', function(event) {
            FlutterClickHandler.postMessage('form_submitted');
          });
          
          console.log('Flutter click interceptor injected successfully');
        })();
      ''');
    } catch (e) {
      print('Erreur lors de l\'injection du script: $e');
    }
  }

  Future<void> _openExternalLink(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      print("Impossible d'ouvrir le lien : $url");
    }
  }

  void _setupNotificationListeners() {
    // SOLUTION PROBLÈME 2: Gestion des notifications en premier plan avec notifications natives
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Notification reçue au premier plan: ${message.messageId}');
      _showNativeNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification cliquée (app en arrière-plan): ${message.messageId}');
      _handleNotificationClick(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('App lancée par notification: ${message.messageId}');
        if (widget.initialUrl == null) {
          _waitForWebViewAndNavigate(message);
        }
      }
    });
  }

  // SOLUTION PROBLÈME 2: Afficher une notification native système
  Future<void> _showNativeNotification(RemoteMessage message) async {
    String title = message.notification?.title ?? 'Notification';
    String body = message.notification?.body ?? 'Nouveau message';
    String? url = message.data['url'];

    const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
      'equiphorse_channel',
      'Equiphorse Notifications',
      channelDescription: 'Notifications de l\'application Equiphorse',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iosNotificationDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      message.hashCode,
      title,
      body,
      notificationDetails,
      payload: url,
    );
  }

  void _waitForWebViewAndNavigate(RemoteMessage message) {
    if (_isWebViewReady) {
      _handleNotificationClick(message);
    } else {
      Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_isWebViewReady) {
          timer.cancel();
          _handleNotificationClick(message);
        }
      });
    }
  }

  void _handleNotificationClick(RemoteMessage message) {
    final String? url = message.data['url'];
    if (url != null && url.isNotEmpty) {
      setState(() {
        _isWebViewReady = false; // Spinner dès la navigation forcée
      });
      if (_navigationHistory.isEmpty || !_navigationHistory.contains(homeUrl)) {
        _navigationHistory.add(homeUrl);
      }
      _controller.loadRequest(Uri.parse(url));
    } else {
      _controller.loadRequest(Uri.parse(homeUrl));
    }
  }

  // Nouvelle méthode pour gérer les URLs de notification depuis les notifications locales
  void _handleNotificationUrl(String url) {
    setState(() {
      _isWebViewReady = false; // Spinner dès la navigation forcée
    });
    if (_navigationHistory.isEmpty || !_navigationHistory.contains(homeUrl)) {
      _navigationHistory.add(homeUrl);
    }
    _controller.loadRequest(Uri.parse(url));
  }

  Future<void> _checkNotificationStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    setState(() {
      _notificationsAllowed =
          settings.authorizationStatus == AuthorizationStatus.authorized;
    });
  }

  void _showNotificationDialogAfterDelay() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_notificationsAllowed && mounted) {
        setState(() {
          _isDialogVisible = true;
        });
      }
    });
  }

  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (Platform.isIOS) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      setState(() {
        _notificationsAllowed = true;
        _isDialogVisible = false;
      });
    } else {
      setState(() {
        _isDialogVisible = false;
      });
    }
  }

  // SOLUTION PROBLÈME 1: Gestion personnalisée du retour
  Future<bool> _onWillPop() async {
    print('Navigation history: $_navigationHistory');
    
    if (_navigationHistory.length > 1) {
      // Supprimer l'URL actuelle
      _navigationHistory.removeLast();
      // Naviguer vers l'URL précédente
      String previousUrl = _navigationHistory.last;
      print('Retour vers: $previousUrl');
      await _controller.loadRequest(Uri.parse(previousUrl));
      return false; // Ne pas fermer l'app
    }
    
    // Si on est sur la page d'accueil ou plus d'historique, permettre la fermeture
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    
    return true; // Fermer l'app
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // MODIFICATION: Envelopper WebView dans GestureDetector comme solution de secours
              GestureDetector(
                onTap: () {
                  // Solution de secours si JavaScript ne fonctionne pas
                  setState(() {
                    _isWebViewReady = false;
                  });
                  print('Tap détecté sur WebView (solution de secours)');
                },
                child: WebViewWidget(controller: _controller),
              ),

              // Indicateur de chargement
              if (!_isWebViewReady)
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ton icône PNG au centre
                      Image.asset(
                        'assets/icone_de_chargement.png',
                        width: 64,
                        height: 64,
                      ),
                      // Spinner autour de l'icône
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),

              // Dialog de demande de permission
              if (_isDialogVisible && !_notificationsAllowed)
                GestureDetector(
                  onTap: () => setState(() => _isDialogVisible = false),
                  child: Container(
                    color: Colors.black.withOpacity(0.4),
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.notifications_active, size: 40, color: Colors.blue),
                            const SizedBox(height: 12),
                            const Text(
                              'Notifications',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Autorisez les notifications pour recevoir les alertes importantes et rester informé.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, color: Colors.black54),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _requestPermission,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text(
                                  'Autoriser',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Nettoyer la référence globale
    if (_currentAppInstance == this) {
      _currentAppInstance = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}