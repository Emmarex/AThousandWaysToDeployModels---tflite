import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tf_lite/pages/HomePage.dart';

Future<void> main() async {
  try {
    runApp(MainApp());
  } catch (e) {
    runApp(MainApp());
  }
}

class MainApp extends StatelessWidget {
  
  @override
  Widget build(BuildContext context) {

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    return MaterialApp(
      title: 'TensorFlow Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage()
    );
  }
}