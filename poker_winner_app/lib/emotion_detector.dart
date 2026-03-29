import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class EmotionAnalysisResult {
  final double tensionPercent;  // Total confidence % in negative emotions
  final double calmPercent;     // Total confidence % in calm/neutral emotions
  final double bluffPercent;    // Normalized difference (0=too calm, 100=bluffing)
  final String label;           // Descriptive label for bluff percentage

  EmotionAnalysisResult({
    required this.tensionPercent,
    required this.calmPercent,
    required this.bluffPercent,
    required this.label,
  });
}

// Individual frame analysis result
// ['angry', 'contempt', 'disgust', 'fear', 'happy', 'natural', 'sad', 'sleepy', 'surprised']
// weighted average of top 3 detections per emotion
class FrameResult {
  final List<double> emotions;

  FrameResult({
    required this.emotions,
  });
}

// TFLite model wrapper for emotion detection
// Processes frames, aggregates results every second, and provides bluff analysis
class EmotionDetector {
  static EmotionDetector? _instance;
  static EmotionDetector get instance => _instance ??= EmotionDetector._();
  
  EmotionDetector._();

  // Emotion index mapping from model output
  // ['angry', 'contempt', 'disgust', 'fear', 'happy', 'natural', 'sad', 'sleepy', 'surprised']
  static const int ANGRY = 0;
  static const int CONTEMPT = 1;
  static const int DISGUST = 2;
  static const int FEAR = 3;
  static const int HAPPY = 4;
  static const int NEUTRAL = 5;
  static const int SAD = 6;
  static const int SLEEPY = 7;
  static const int SURPRISED = 8;
  
  static const List<String> CLASS_NAMES = [
    'angry', 'contempt', 'disgust', 'fear', 'happy', 'natural', 'sad', 'sleepy', 'surprised'
  ];

  // State tracking
  bool _isProcessing = false;
  bool _isInitialized = false;
  Interpreter? _interpreter;
  
  // Frame results buffer (cleared every second)
  final List<FrameResult> _frameBuffer = [];
  Timer? _aggregationTimer;
  
  // Latest aggregated result
  EmotionAnalysisResult? _latestResult;
  
  // Callback for when new aggregated result is available
  Function(EmotionAnalysisResult)? onResultUpdate;

  bool get isProcessing => _isProcessing;
  bool get isInitialized => _isInitialized;
  EmotionAnalysisResult? get latestResult => _latestResult;

  /// Initialize the TFLite model
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset('best_float32.tflite');
      
      _isInitialized = true;
      
      // Start aggregation timer
      _startAggregationTimer();
      
    } catch (e) {
      print('Error initializing emotion detector: $e');
      rethrow;
    }
  }

  /// Start timer that aggregates results every second
  void _startAggregationTimer() {
    _aggregationTimer?.cancel();
    _aggregationTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _aggregateResults();
    });
  }

  /// Process a single camera frame
  Future<void> processFrame(CameraImage image) async {
    if (!_isInitialized || _isProcessing) return;
    
    _isProcessing = true;
    
    try {
      final frameResult = await _runModelInference(image);
      _frameBuffer.add(frameResult);
    } catch (e) {
      print('Error processing frame: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Run model inference on a frame
  Future<FrameResult> _runModelInference(CameraImage image) async {
    if (_interpreter == null) {
      throw StateError('Model not initialized');
    }

    // 1. Convert CameraImage to RGB
    final rgbImage = _convertCameraImageToRGB(image);
    
    // 2. Resize to 640x640 and normalize to 0-1
    final processedImage = _preprocessImage(rgbImage, 640, 640);
    
    // 3. Run inference
    final input = [processedImage];
    final output = List.filled(1 * 13 * 8400, 0.0).reshape([1, 13, 8400]);
    
    _interpreter!.run(input, output);
    
    // 4. Parse predictions: transpose from (1, 13, N) to (N, 13)
    final List<List<double>> predictions = [];
    for (int i = 0; i < 8400; i++) {
      final row = <double>[];
      for (int j = 0; j < 13; j++) {
        row.add(output[0][j][i]);
      }
      predictions.add(row);
    }
    
    // 5. Extract boxes and class scores
    final boxes = <List<double>>[];
    final classScores = <List<double>>[];
    final topClassScores = <double>[];
    
    for (var pred in predictions) {
      boxes.add(pred.sublist(0, 4)); // First 4 are box coords (xywh)
      final scores = pred.sublist(4);  // Next 9 are class scores
      classScores.add(scores);
      topClassScores.add(scores.reduce(max));
    }
    
    // 6. Group detections by face
    final groups = _groupRawCandidates(boxes, classScores, topClassScores);
    
    // 7. Calculate weighted emotion scores from all groups
    final emotionScores = _calculateGroupedEmotions(groups);
    
    return FrameResult(emotions: emotionScores);
  }
  
  /// Convert CameraImage (YUV420) to RGB
  img.Image _convertCameraImageToRGB(CameraImage image) {
    // YUV420 format has 3 planes: Y (luminance), U, V (chrominance)
    final int width = image.width;
    final int height = image.height;
    
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
    
    final imgRgb = img.Image(width: width, height: height);
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
        final int index = y * width + x;
        
        final yp = image.planes[0].bytes[index];
        final up = image.planes[1].bytes[uvIndex];
        final vp = image.planes[2].bytes[uvIndex];
        
        // YUV to RGB conversion
        int r = (yp + vp * 1.402 - 179.456).round().clamp(0, 255);
        int g = (yp - up * 0.34414 - vp * 0.71414 + 135.45984).round().clamp(0, 255);
        int b = (yp + up * 1.772 - 226.816).round().clamp(0, 255);
        
        imgRgb.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    
    return imgRgb;
  }
  
  /// Preprocess image: resize to target size and normalize to [0, 1]
  List<List<List<List<double>>>> _preprocessImage(img.Image image, int width, int height) {
    final resized = img.copyResize(image, width: width, height: height);
    
    final input = List.generate(
      1,
      (_) => List.generate(
        height,
        (y) => List.generate(
          width,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );
    
    return input;
  }

  /// Aggregate all frames from the past second
  void _aggregateResults() {
    if (_frameBuffer.isEmpty) {
      // No frames processed in the last second
      return;
    }

    // Average emotions across all frames
    final aggregatedEmotions = List<double>.filled(9, 0.0);

    for (var frame in _frameBuffer) {
      for (int i = 0; i < 9; i++) {
        aggregatedEmotions[i] += frame.emotions[i];
      }
    }

    final frameCount = _frameBuffer.length;
    for (int i = 0; i < 9; i++) {
      aggregatedEmotions[i] /= frameCount;
    }

    // Calculate tension and calm percentages
    final tensionPercent = _calculateTensionPercent(aggregatedEmotions);
    final calmPercent = _calculateCalmPercent(aggregatedEmotions);
    
    // Calculate bluff percentage
    final bluffPercent = _calculateBluffPercentage(tensionPercent, calmPercent);
    
    // Determine label
    final label = _getBluffLabel(bluffPercent);

    // Create result
    _latestResult = EmotionAnalysisResult(
      tensionPercent: tensionPercent * 100,  // Convert to percentage
      calmPercent: calmPercent * 100,        // Convert to percentage
      bluffPercent: bluffPercent,
      label: label,
    );

    // Notify listener
    onResultUpdate?.call(_latestResult!);

    // Clear buffer for next second
    _frameBuffer.clear();
  }

  /// Calculate tension percentage from negative emotions
  /// Tension = sum of confidence % for: angry + contempt + disgust + fear + sad
  double _calculateTensionPercent(List<double> emotions) {
    return emotions[ANGRY] + 
           emotions[CONTEMPT] + 
           emotions[DISGUST] + 
           emotions[FEAR] + 
           emotions[SAD];
  }

  /// Calculate calm percentage from positive/neutral emotions
  /// Calm = sum of confidence % for: happy + neutral + surprised
  double _calculateCalmPercent(List<double> emotions) {
    return emotions[HAPPY] + 
           emotions[NEUTRAL] + 
           emotions[SURPRISED];
  }

  /// Calculate bluff percentage
  /// tension - calm, normalized so 0 = most calm, 100 = most tense/bluffing
  /// More positive difference = more likely bluffing
  double _calculateBluffPercentage(double tension, double calm) {
    // Raw difference (can be negative if calm > tension)
    final rawScore = tension - calm;
    
    // TODO: Adjust normalization range based on testing
    // Assuming typical range: -3 to +3 (each score can be 0-5 theoretically)
    // Map [-3, +3] to [0, 100]
    // When calm > tension (negative): maps to 0-50%
    // When tension > calm (positive): maps to 50-100%
    final normalizedScore = ((rawScore + 3.0) / 6.0) * 100;
    
    return normalizedScore.clamp(0.0, 100.0);
  }

  /// Get descriptive label for bluff percentage
  /// Note: 50% is the midpoint where tension = calm
  String _getBluffLabel(double bluffPercent) {
    // TODO: Adjust thresholds based on testing
    if (bluffPercent <= 50) {
      return 'Unsure';
    } else if (bluffPercent < 65) {
      return 'Maybe Bluff';
    } else if (bluffPercent < 85) {
      return 'Likely Bluff';
    } else {
      return 'Bluffing';
    }
  }

  /// Clean up resources
  void dispose() {
    _aggregationTimer?.cancel();
    _frameBuffer.clear();
    _interpreter?.close();
  }
  
  // ========== Detection Grouping & Scoring ==========
  
  /// Group raw detections by face using IoU and center distance
  List<Map<String, dynamic>> _groupRawCandidates(
    List<List<double>> boxes,
    List<List<double>> classScores,
    List<double> topClassScores,
    {double keepThresh = 0.01}
  ) {
    final groups = <Map<String, dynamic>>[];
    
    for (int i = 0; i < boxes.length; i++) {
      if (topClassScores[i] < keepThresh) continue;
      
      final boxXywh = boxes[i];
      final scoreVector = classScores[i];
      
      bool matched = false;
      for (var group in groups) {
        if (_isSameFace(boxXywh, group['box_xywh'])) {
          (group['detections'] as List).add({
            'box_xywh': boxXywh,
            'scores': scoreVector,
          });
          matched = true;
          break;
        }
      }
      
      if (!matched) {
        groups.add({
          'box_xywh': boxXywh,
          'detections': [
            {'box_xywh': boxXywh, 'scores': scoreVector}
          ],
        });
      }
    }
    
    return groups;
  }
  
  /// Check if two boxes represent the same face
  bool _isSameFace(
    List<double> box1Xywh,
    List<double> box2Xywh,
    {double iouThresh = 0.5, double centerThresh = 0.03}
  ) {
    final box1Xyxy = _xywh2xyxy(box1Xywh);
    final box2Xyxy = _xywh2xyxy(box2Xywh);
    
    final overlap = _calculateIoU(box1Xyxy, box2Xyxy);
    final dist = _centerDistance(box1Xywh, box2Xywh);
    
    return overlap >= iouThresh || dist <= centerThresh;
  }
  
  /// Convert center format (cx, cy, w, h) to corner format (x1, y1, x2, y2)
  List<double> _xywh2xyxy(List<double> box) {
    final cx = box[0], cy = box[1], w = box[2], h = box[3];
    return [
      cx - w / 2,  // x1
      cy - h / 2,  // y1
      cx + w / 2,  // x2
      cy + h / 2,  // y2
    ];
  }
  
  /// Calculate Intersection over Union
  double _calculateIoU(List<double> box1, List<double> box2) {
    final x1 = max(box1[0], box2[0]);
    final y1 = max(box1[1], box2[1]);
    final x2 = min(box1[2], box2[2]);
    final y2 = min(box1[3], box2[3]);
    
    final interW = max(0.0, x2 - x1);
    final interH = max(0.0, y2 - y1);
    final interArea = interW * interH;
    
    final area1 = max(0.0, box1[2] - box1[0]) * max(0.0, box1[3] - box1[1]);
    final area2 = max(0.0, box2[2] - box2[0]) * max(0.0, box2[3] - box2[1]);
    final union = area1 + area2 - interArea;
    
    if (union == 0) return 0.0;
    return interArea / union;
  }
  
  /// Calculate Euclidean distance between box centers
  double _centerDistance(List<double> box1Xywh, List<double> box2Xywh) {
    final cx1 = box1Xywh[0], cy1 = box1Xywh[1];
    final cx2 = box2Xywh[0], cy2 = box2Xywh[1];
    return sqrt(pow(cx1 - cx2, 2) + pow(cy1 - cy2, 2));
  }
  
  /// Calculate weighted emotion scores from all face groups
  List<double> _calculateGroupedEmotions(List<Map<String, dynamic>> groups) {
    if (groups.isEmpty) {
      // No detections, return neutral
      return List.filled(9, 0.0);
    }
    
    // Average emotion scores across all face groups
    final totalEmotions = List<double>.filled(9, 0.0);
    
    for (var group in groups) {
      final groupScores = _weightedEmotionScores(group);
      for (int i = 0; i < 9; i++) {
        totalEmotions[i] += groupScores[i];
      }
    }
    
    // Average across groups
    for (int i = 0; i < 9; i++) {
      totalEmotions[i] /= groups.length;
    }
    
    return totalEmotions;
  }
  
  /// Calculate weighted emotion scores for a single face group
  /// Takes top 3 detections per emotion and weights them: 1.0, 0.5, 0.25
  List<double> _weightedEmotionScores(Map<String, dynamic> group) {
    const weights = [1.0, 0.5, 0.25];
    final finalScores = <double>[];
    
    for (int emotionIdx = 0; emotionIdx < CLASS_NAMES.length; emotionIdx++) {
      final vals = <double>[];
      
      // Collect all scores for this emotion across detections
      for (var det in group['detections']) {
        final scores = det['scores'] as List<double>;
        vals.add(scores[emotionIdx]);
      }
      
      // Sort descending and take top 3
      vals.sort((a, b) => b.compareTo(a));
      final top3 = vals.take(3).toList();
      
      // Weighted average: (1*1st + 0.5*2nd + 0.25*3rd) / 1.75
      double total = 0.0;
      for (int i = 0; i < top3.length; i++) {
        total += weights[i] * top3[i];
      }
      
      final score = total / 1.75; // Fixed denominator
      finalScores.add(score);
    }
    
    return finalScores;
  }
}
