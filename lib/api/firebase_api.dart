import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

class FirebaseApi {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  Future<void> initNotifications() async {
    // Demander les permissions
    await _requestPermissions();
    
    // Initialiser les notifications locales
    await _initializeLocalNotifications();
    
    // Configurer les handlers de messages
    _setupMessageHandlers();
    
    // Obtenir et afficher le token
    final token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');
  }

  Future<void> _requestPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: true,
      criticalAlert: true,
      provisional: true,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');
  }

  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        print('Local notification tapped: ${response.payload}');
        await _handleNotificationTap(response.payload);
      },
    );

    // Créer le canal de notification pour Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'default_channel_id',
      'Default Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _setupMessageHandlers() {
    // Messages en premier plan
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received foreground message: ${message.data}');
      _showLocalNotification(message);
    });
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel_id',
      'Default Notifications',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? 'Notification',
      message.notification?.body ?? 'You have a new message',
      platformDetails,
      payload: message.data['url'], // Passer l'URL en payload
    );
  }

  Future<void> _handleNotificationTap(String? url) async {
    if (url != null && url.isNotEmpty) {
      print('Opening URL: $url');
      try {
        final uri = Uri.parse(url);
        // Essayer de lancer l'URL directement
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        print('URL launched successfully');
      } catch (e) {
        print('Error launching URL: $e');
        // Essayer avec le navigateur par défaut
        try {
          final uri = Uri.parse(url);
          await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
          print('URL launched with platformDefault mode');
        } catch (e2) {
          print('Failed to launch URL with platformDefault: $e2');
        }
      }
    }
  }
}