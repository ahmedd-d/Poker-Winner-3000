import 'dart:async';
import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'emotion_detector.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:google_fonts/google_fonts.dart';

class DisclaimerScreen extends StatefulWidget{
  const DisclaimerScreen({super.key});
  
  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();

}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  @override
  void initState() {
    super.initState();
    _initializeModelAndNavigate();
  }

  Future<void> _initializeModelAndNavigate() async {
    try {
      // Initialize TFLite emotion detection model
      await EmotionDetector.instance.initialize();
    } catch (e) {
      print('Error initializing model: $e');
    }
    
    if (mounted) {
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => CameraScreen()),
      );
    }
  }

  @override 
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Title and disclaimer section
            Expanded(
              flex: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Spacer(flex: 2),
                    
                    // Title
                    Text(
                      "Poker Winner 3000",
                      style: TextStyle(
                        fontFamily: "Sterion",
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: Colors.white70,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 24), 
                    
                    // Disclaimer
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        "For entertainment purposes only.\n"
                        "Please don't gamble. Or do. It's your money.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: Colors.white54,
                          height: 1.5,
                        ),
                      ),
                    ),
                    
                    Spacer(flex: 1),
                  ],
                ),
              ),
            ),
            
            // Loading animation section
            Expanded(
              flex: 62,
              child: Center(child: LoadingAnimationWidget.stretchedDots(
                  color: Colors.white,
                  size: 50,
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
    super.dispose();
  }
}