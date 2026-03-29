import 'package:flutter/material.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'emotion_detector.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  CameraController? cameraController;
  bool grantedPermission = false;
  bool initializing = true;
  int frameCount = 0;
  
  // Detection results
  double bluffPercentage = 0.0;
  double tensionScore = 0.0;
  double calmScore = 0.0;
  double confidencePercent = 0.0;
  String label = "Analyzing...";
  
  // Vine boom overlay
  bool showOverlay = false;
  AnimationController? _overlayController;
  Animation<double>? _overlayOpacity;
  bool isBluffing = false; // true = bluffing (red), false = confident (green)

  @override
  void initState() {
    super.initState();
    
    // Initialize overlay animation
    _overlayController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _overlayOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _overlayController!, curve: Curves.easeOut),
    );
    
    _overlayController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          showOverlay = false;
        });
        _overlayController!.reset();
      }
    });
    
    // Set up result listener
    EmotionDetector.instance.onResultUpdate = _handleNewResult;
    
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    
    if (status.isGranted) {
      setState(() {
        grantedPermission = true;
      });
      await _initializeCamera();
    } 
    else {
      setState(() {
        grantedPermission = false;
        initializing = false;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          initializing = false;
        });
        return;
      }

      // Use the front camera for poker face detection
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras[0],
      );
      
      cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium, // Medium should be sufficient for emotion detection
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await cameraController!.initialize();
      
      setState(() {
        initializing = false;
      });

      // Start streaming frames
      _startImageStream();
      
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        initializing = false;
      });
    }
  }

  void _startImageStream() {
    if (cameraController == null) return;
    
    cameraController!.startImageStream((CameraImage image) {
      frameCount++;
      
      // Process every 3rd frame (roughly 300ms at 10fps)
      if (frameCount % 3 != 0) return;
      
      // EmotionDetector handles its own processing state check
      EmotionDetector.instance.processFrame(image);
    });
  }

  /// Handle new aggregated result from EmotionDetector
  void _handleNewResult(EmotionAnalysisResult result) {
    setState(() {
      bluffPercentage = result.bluffPercent;
      tensionScore = result.tensionScore;
      calmScore = result.calmScore;
      confidencePercent = result.confidencePercent;
      label = result.label;
    });

    // Trigger vine boom overlay for confident extreme readings
    if (confidencePercent > 75) { // TODO: Adjust threshold based on testing
      if (bluffPercentage > 85) {
        _triggerOverlay(isBluffing: true);
      } else if (bluffPercentage < 15) {
        _triggerOverlay(isBluffing: false);
      }
    }
  }

  /// Trigger the vine boom overlay animation
  void _triggerOverlay({required bool isBluffing}) {
    setState(() {
      this.isBluffing = isBluffing;
      showOverlay = true;
    });
    
    // TODO: Play vine boom sound effect
    // AudioPlayer.play('assets/sounds/vine_boom.mp3');
    
    _overlayController!.forward();
  }

  @override
  void dispose() {
    _overlayController?.dispose();
    cameraController?.stopImageStream();
    cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFDFDFC)),
        ),
      );
    }

    if (!grantedPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_outlined, size: 64, color: Colors.white70),
                SizedBox(height: 24),
                Text(
                  'Camera Permission Required',
                  style: GoogleFonts.orbitron(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFDFDFC),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  'This app needs camera access to detect poker faces.',
                  style: GoogleFonts.orbitron(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => _requestCameraPermission(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFFDFDFC),
                    foregroundColor: Colors.black,
                  ),
                  child: Text('Grant Permission'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Camera not available',
            style: GoogleFonts.orbitron(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview - 4:3 aspect ratio like iPhone camera
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraController!.value.previewSize!.height,
                    height: cameraController!.value.previewSize!.width,
                    child: CameraPreview(cameraController!),
                  ),
                ),
              ),
            ),
          ),
          
          // Results overlay at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.95),
                  ],
                ),
              ),
              padding: EdgeInsets.fromLTRB(24, 40, 24, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bluff percentage - big and prominent
                  Text(
                    '${bluffPercentage.toStringAsFixed(0)}%',
                    style: GoogleFonts.orbitron(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: _getColorForBluffPercentage(bluffPercentage),
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'BLUFF PROBABILITY',
                    style: GoogleFonts.orbitron(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFFFDFDFC),
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Divider
                  Container(
                    height: 1,
                    width: 120,
                    color: Colors.white30,
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Analysis details
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildScoreColumn('TENSION', tensionScore),
                      _buildScoreColumn('CALM', calmScore),
                      _buildScoreColumn('CONFIDENCE', confidencePercent),
                    ],
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Label
                  Text(
                    label.toUpperCase(),
                    style: GoogleFonts.orbitron(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFFDFDFC),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Vine boom overlay
          if (showOverlay)
            AnimatedBuilder(
              animation: _overlayOpacity!,
              builder: (context, child) {
                return Opacity(
                  opacity: _overlayOpacity!.value,
                  child: Container(
                    color: (isBluffing ? Colors.red : Colors.green).withOpacity(0.7),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // TODO: Replace with actual image assets
                          Icon(
                            isBluffing ? Icons.warning_rounded : Icons.check_circle_rounded,
                            size: 120,
                            color: Colors.white,
                          ),
                          SizedBox(height: 24),
                          Text(
                            isBluffing ? 'BLUFFING!' : 'CONFIDENT!',
                            style: GoogleFonts.orbitron(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildScoreColumn(String label, double value) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(1),
          style: GoogleFonts.orbitron(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFDFDFC),
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.orbitron(
            fontSize: 9,
            fontWeight: FontWeight.w300,
            color: Colors.white60,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Color _getColorForBluffPercentage(double percentage) {
    if (percentage < 30) {
      return Colors.greenAccent;
    } else if (percentage < 60) {
      return Colors.yellowAccent;
    } else {
      return Colors.redAccent;
    }
  }
}