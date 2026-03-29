import 'package:flutter/material.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'emotion_detector.dart';
import 'package:audioplayers/audioplayers.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _grantedPermission = false;
  bool _initializing = true;
  int _frameCount = 0;
  
  // Detection results
  double bluffPercentage = 0.0;
  double tensionPercent = 0.0;
  double calmPercent = 0.0;
  String label = "Analyzing...";
  
  // Vine boom overlay
  bool _showOverlay = false;
  AnimationController? _overlayController;
  Animation<double>? _overlayOpacity;
  AudioPlayer? _audioPlayer;

  @override
  void initState() {
    super.initState();
    _initializeAudio();
    
    // Image overlays
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
          _showOverlay = false;
        });
        _overlayController!.reset();
      }
    });
    
    // result listener
    EmotionDetector.instance.onResultUpdate = _handleNewResult;
    
    _requestCameraPermission();
  }

  Future<void> _initializeAudio() async {
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setSource(AssetSource("sounds/vine-boom.mp3"));
    await _audioPlayer!.setVolume(1);
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    
    if (!status.isGranted) {
      _initializing = false;
    }
    setState(() { _grantedPermission = true; });
    await _initializeCamera(); 
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
        });
        return;
      }

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras[0],
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // Native format, efficient RGB conversion
      );

      await _cameraController!.initialize();
      
      setState(() {
        _initializing = false;
      });

      // Start streaming frames
      _startImageStream();
      
    } catch (e) {
      // ignore: avoid_print
      print('Error initializing camera: $e');
      setState(() {
        _initializing = false;
      });
    }
  }

  void _startImageStream() {
    if (_cameraController == null) return;
    
    _cameraController!.startImageStream((CameraImage image) {
      _frameCount++;
      if (_frameCount % 3 != 0) return; // try every third frame
      EmotionDetector.instance.processFrame(image);
    });
  }

  // Display aggregated result from EmotionDetector
  void _handleNewResult(EmotionAnalysisResult result) {
    setState(() {
      bluffPercentage = result.bluffPercent;
      tensionPercent = result.tensionPercent;
      calmPercent = result.calmPercent;
      label = result.label;
    });

    // Overlay and vine boom for high bluff
    if (bluffPercentage > 85) {
      _triggerOverlay();
    }
  }

  void _triggerOverlay() {
    setState(() { _showOverlay = true; });
    _audioPlayer?.seek(Duration.zero);
    _audioPlayer?.resume();
    _overlayController!.forward();
  }

  @override
  void dispose() {
    _overlayController?.dispose();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFDFDFC)),
        ),
      );
    }

    if (!_grantedPermission) {
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

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
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
          // Camera viewport
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize!.height,
                    height: _cameraController!.value.previewSize!.width,
                    child: CameraPreview(_cameraController!),
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
                  // Bluff percentage and label
                  Text(
                    '${bluffPercentage.toStringAsFixed(0)}% - ${label.toUpperCase()}',
                    style: GoogleFonts.orbitron(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: _getColorForBluffPercentage(bluffPercentage),
                      height: 1.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Analysis details: Calm and Tense percentages
                  Text(
                    '${calmPercent.toStringAsFixed(0)}% CALM    ${tensionPercent.toStringAsFixed(0)}% TENSE',
                    style: GoogleFonts.orbitron(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white70,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Vine boom overlay - just the meme image
          if (_showOverlay)
            AnimatedBuilder(
              animation: _overlayOpacity!,
              builder: (context, child) {
                return Opacity(
                  opacity: _overlayOpacity!.value,
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                    child: Center(
                      child: Image.asset(
                        'assets/images/jackpot.jpg', 
                        width: MediaQuery.of(context).size.width * 0.8,
                        fit: BoxFit.contain,
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