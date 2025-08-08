import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    
    // SOLUTION PROBLÈME 1: Ajouter l'URL d'accueil à l'historique si on démarre avec une notification
    if (widget.initialUrl != null) {
      _navigationHistory.add(homeUrl);
    }
    _navigationHistory.add(startUrl);
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            // SOLUTION PROBLÈME 1: Ajouter à l'historique seulement si ce n'est pas un retour
            if (_navigationHistory.isEmpty || _navigationHistory.last != url) {
              _navigationHistory.add(url);
            }
          },
          onPageFinished: (String url) {
            setState(() {
              _isWebViewReady = true;
            });
          },
          onNavigationRequest: (request) =>
              request.url.startsWith('https://equiphorse.tn')
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent,
        ),
      )
      ..loadRequest(Uri.parse(startUrl));
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
      print('Redirection vers: $url');
      // SOLUTION PROBLÈME 1: Ajouter l'URL d'accueil avant si ce n'est pas déjà fait
      if (_navigationHistory.isEmpty || !_navigationHistory.contains(homeUrl)) {
        _navigationHistory.add(homeUrl);
      }
      _controller.loadRequest(Uri.parse(url));
    } else {
      print('Aucune URL trouvée dans les données de notification');
      _controller.loadRequest(Uri.parse(homeUrl));
    }
  }

  // Nouvelle méthode pour gérer les URLs de notification depuis les notifications locales
  void _handleNotificationUrl(String url) {
    print('Redirection depuis notification locale vers: $url');
    // Ajouter l'URL d'accueil avant si ce n'est pas déjà fait
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
      onWillPop: _onWillPop, // SOLUTION PROBLÈME 1: Utiliser la nouvelle logique
      child: Scaffold(
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),

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