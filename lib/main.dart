import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroWay',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('NeuroWay — Упражнения')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              child: Text('Выбор + движение'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChoiceMovementExercise()),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              child: Text('Следуй и запоминай'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FollowRememberExercise()),
              ),
            ),
            SizedBox(height: 16),
            Text('Доступные упражнения: 1) Выбор + движение  2) Следуй и запоминай'),
          ],
        ),
      ),
    );
  }
}

enum StimulusType { red, blue, star }

class LevelConfig {
  final int levelNumber;
  final String name;
  final double inversionProbability;
  final bool showHint;
  final String hintText;
  final int minSessionStimuli;
  final bool rareInversionMode;

  LevelConfig({
    required this.levelNumber,
    required this.name,
    this.inversionProbability = 0.0,
    this.showHint = false,
    this.hintText = '',
    this.minSessionStimuli = 20,
    this.rareInversionMode = false,
  });
}

class StimulusResult {
  final StimulusType type;
  final bool correct;
  final double reactionTime;
  final bool wasInversion;

  StimulusResult({
    required this.type,
    required this.correct,
    required this.reactionTime,
    required this.wasInversion,
  });
}

// Follow and Remember exercise
class FollowRememberExercise extends StatefulWidget {
  @override
  _FollowRememberExerciseState createState() => _FollowRememberExerciseState();
}

// Вспомогательные типы
class _Sample {
  final Offset pos;
  final List<Offset> centerLine;
  _Sample(this.pos, this.centerLine);
}

class _MotorMetrics {
  final double meanDeviation;
  final double outOfPathRatio;
  final double maxDeviation;
  _MotorMetrics(this.meanDeviation, this.outOfPathRatio, this.maxDeviation);
}

class _SessionSummary {
  final _MotorMetrics metrics;
  final double durationSec;
  _SessionSummary(this.metrics, this.durationSec);
}

class _ImageSelection {
  final String value;
  final double rt;
  _ImageSelection(this.value, this.rt);
}

class _ImageMetrics {
  final double accuracy;
  final double meanRt;
  _ImageMetrics(this.accuracy, this.meanRt);
}

class _FollowPainter extends CustomPainter {
  final List<Offset> centerLine;
  final double pathWidth;
  final List<_Sample> samples;
  _FollowPainter({required this.centerLine, required this.pathWidth, required this.samples});
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()..color = Colors.black..strokeWidth = 2;
    for (int i = 0; i < centerLine.length - 1; i++) {
      canvas.drawLine(centerLine[i], centerLine[i + 1], paintLine);
    }
    final area = Paint()..color = Colors.blue.withOpacity(0.15);
    for (int i = 0; i < centerLine.length - 1; i++) {
      final a = centerLine[i];
      final b = centerLine[i + 1];
      for (int s = 0; s <= 20; s++) {
        final t = s / 20;
        final p = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
        canvas.drawCircle(p, pathWidth / 2, area);
      }
    }
    final samplePaint = Paint()..color = Colors.red;
    for (var sp in samples) canvas.drawCircle(sp.pos, 3, samplePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _FollowRememberExerciseState extends State<FollowRememberExercise> {
  int motorLevel = 1; // 1..3
  double pathWidth = 80.0;

  bool tracking = false;
  Stopwatch? sessionStopwatch;
  List<_Sample> allSamples = [];
  List<_SessionSummary> sessionSummaries = [];
  final GlobalKey _paintKey = GlobalKey();

  // images
  int imageLevel = 1; // 1..4
  final List<String> items = ['A', 'B', 'C', 'D', 'E'];
  List<String> sequence = [];
  int revealIndex = 0;
  bool playingImages = false;
  Timer? _imageTimer;
  DateTime? _sequenceEndTime;
  List<_ImageSelection> selections = [];
  List<_ImageMetrics> imageHistory = [];

  final Random _rng = Random();
  bool _motorStartedByImages = false;

  double _imageIntervalForLevel() {
    if (imageLevel == 1) return 2.5;
    if (imageLevel == 2) return 2.0;
    if (imageLevel == 3) return 1.5;
    return 1.0;
  }

  int _expectedSelectionsForLevel() {
    if (imageLevel == 1) return 1;
    if (imageLevel == 2) return 2;
    if (imageLevel == 3) return 3;
    return 2;
  }

  void playImageSequence() {
    final pool = List<String>.from(items);
    pool.shuffle(_rng);
    sequence = pool.take(5).toList();
    revealIndex = 0;
    playingImages = true;
    selections.clear();
    _sequenceEndTime = null;
    final interval = _imageIntervalForLevel();
    _imageTimer?.cancel();
    
    if (!tracking) {
      startTracking();
      _motorStartedByImages = true;
    } else {
      _motorStartedByImages = false;
    }
    _imageTimer = Timer.periodic(Duration(milliseconds: (interval * 1000).toInt()), (t) {
      setState(() {
        revealIndex++;
        if (revealIndex >= sequence.length) {
          
          playingImages = false;
          t.cancel();
          
          Timer(Duration(milliseconds: (interval * 1000).toInt()), () {
            
            if (_motorStartedByImages && tracking) {
              stopTracking();
            }
            _sequenceEndTime = DateTime.now();
            setState(() {});
          });
        }
      });
    });
    setState(() {});
  }

  void onSelectImage(String v) {
    if (playingImages || _sequenceEndTime == null) return;
    final rt = DateTime.now().difference(_sequenceEndTime!).inMilliseconds / 1000.0;
    selections.add(_ImageSelection(v, rt));
    if (selections.length >= _expectedSelectionsForLevel()) _evaluateImageSelections();
    setState(() {});
  }

  void _evaluateImageSelections() {
    final k = _expectedSelectionsForLevel();
    final lastK = sequence.sublist(sequence.length - k);
    List<String> target = List.from(lastK);
    if (imageLevel == 4) target = List.from(lastK.reversed);
    int correct = 0;
    double sumRt = 0;
    for (int i = 0; i < target.length; i++) {
      final sel = i < selections.length ? selections[i].value : null;
      if (sel != null && sel == target[i]) correct++;
      if (i < selections.length) sumRt += selections[i].rt;
    }
    final acc = correct / target.length;
    final meanRt = selections.isEmpty ? 0.0 : sumRt / selections.length;
    imageHistory.add(_ImageMetrics(acc, meanRt));
    if (imageHistory.length > 6) imageHistory.removeAt(0);

    final lastTwoOk = imageHistory.length >= 2 && imageHistory.sublist(imageHistory.length - 2).every((m) => m.accuracy >= 0.8 && m.meanRt <= 2.5);
    if (lastTwoOk && imageLevel < 4) imageLevel++;
    if (acc < 0.7 || meanRt > 2.5) {
      if (imageLevel > 1) imageLevel--;
    }

    final parts = <String>[];
    for (int i = 0; i < target.length; i++) {
      final sel = i < selections.length ? selections[i].value : '-';
      parts.add('${target[i]} <- $sel ${sel == target[i] ? '✔' : '✖'}');
    }
    final fb = 'Результат: ${parts.join(', ')} • Точность: ${(acc * 100).toStringAsFixed(0)}% • RT: ${meanRt.toStringAsFixed(2)}s';
    showDialog(context: context, builder: (_) => AlertDialog(title: Text('Результат'), content: Text(fb), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))]));
  }

  void startTracking() {
    allSamples.clear();
    sessionStopwatch = Stopwatch()..start();
    tracking = true;
    setState(() {});
  }

  void stopTracking() {
    tracking = false;
    final elapsed = sessionStopwatch?.elapsedMilliseconds ?? 0;
    sessionStopwatch?.stop();
    if (allSamples.isNotEmpty) {
      final metrics = _computeMetrics();
      sessionSummaries.add(_SessionSummary(metrics, elapsed / 1000.0));
      if (sessionSummaries.length > 10) sessionSummaries.removeAt(0);
      _decideMotorLevel();
    }
    setState(() {});
  }

  void onPointerMove(PointerEvent event) {
    if (!tracking) return;
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(event.position);
    final centerLine = _centerLineForSize(box.size);
    allSamples.add(_Sample(local, centerLine));
  }

  List<Offset> _centerLineForSize(Size s) {
    final w = s.width;
    final h = s.height;
    if (motorLevel == 1) return [Offset(20, h / 2), Offset(w - 20, h / 2)];
    if (motorLevel == 2) return [Offset(20, h * 0.8), Offset(w * 0.33, h * 0.3), Offset(w * 0.66, h * 0.7), Offset(w - 20, h * 0.3)];
    return [Offset(20, h * 0.6), Offset(w * 0.18, h * 0.3), Offset(w * 0.36, h * 0.7), Offset(w * 0.54, h * 0.3), Offset(w * 0.72, h * 0.7), Offset(w - 20, h * 0.4)];
  }

  _MotorMetrics _computeMetrics() {
    if (allSamples.isEmpty) return _MotorMetrics(0, 0, 0);
    double sum = 0;
    int outCount = 0;
    double maxDev = 0;
    for (var s in allSamples) {
      final d = _distToPolyline(s.pos, s.centerLine);
      sum += d;
      if (d > pathWidth / 2) outCount++;
      if (d > maxDev) maxDev = d;
    }
    final mean = sum / allSamples.length;
    final outRatio = outCount / allSamples.length;
    return _MotorMetrics(mean, outRatio, maxDev);
  }

  double _distToPolyline(Offset p, List<Offset> poly) {
    double best = double.infinity;
    for (int i = 0; i < poly.length - 1; i++) {
      final a = poly[i];
      final b = poly[i + 1];
      final d = _pointToSeg(p, a, b);
      if (d < best) best = d;
    }
    return best;
  }

  double _pointToSeg(Offset p, Offset v, Offset w) {
    final l2 = (v - w).distanceSquared;
    if (l2 == 0.0) return (p - v).distance;
    var t = ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    t = t.clamp(0.0, 1.0);
    final proj = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - proj).distance;
  }

  void _decideMotorLevel() {
    double totalSec = 0;
    for (var s in sessionSummaries) totalSec += s.durationSec;
    if (totalSec < 15.0) return;

    double sumMean = 0;
    double sumOut = 0;
    double maxDev = 0;
    for (var s in sessionSummaries) {
      sumMean += s.metrics.meanDeviation * s.durationSec;
      sumOut += s.metrics.outOfPathRatio * s.durationSec;
      if (s.metrics.maxDeviation > maxDev) maxDev = s.metrics.maxDeviation;
    }
    final meanDev = sumMean / totalSec;
    final outRatio = sumOut / totalSec;

    final outPct = outRatio * 100;
    final meanPct = meanDev / pathWidth;
    final maxPct = maxDev / pathWidth;

    final lastTwo = sessionSummaries.length >= 2 ? sessionSummaries.sublist(sessionSummaries.length - 2) : [];
    final lastTwoOk = lastTwo.length == 2 && lastTwo.every((s) => (s.metrics.outOfPathRatio * 100) <= 5 && (s.metrics.meanDeviation / pathWidth) <= 0.2 && (s.metrics.maxDeviation / pathWidth) <= 1.0);
    if (lastTwoOk && motorLevel < 3) motorLevel++;

    if (outPct >= 5 && outPct <= 15 && meanPct >= 0.2 && meanPct <= 0.35 && maxPct >= 1.0 && maxPct <= 1.5) return;

    if (outPct > 20 || meanPct > 0.35 || maxPct > 1.5) {
      if (motorLevel > 1) motorLevel--;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Следуй и запоминай')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              // ElevatedButton(onPressed: startTracking, child: Text('Старт дорожки')),
              // SizedBox(width: 8),
              // ElevatedButton(onPressed: stopTracking, child: Text('Стоп дорожки')),
              // SizedBox(width: 8),
              Text('Уровень дорожки: $motorLevel'),
            ]),
          ),
          Expanded(
            child: LayoutBuilder(builder: (ctx, cons) {
              final centerLine = _centerLineForSize(cons.biggest);
              return Listener(
                onPointerMove: (e) => onPointerMove(e),
                child: Container(
                  key: _paintKey,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _FollowPainter(centerLine: centerLine, pathWidth: pathWidth, samples: allSamples),
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: 8),
          Divider(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              ElevatedButton(onPressed: playingImages ? null : playImageSequence, child: Text('Показать 5 картинок')),
              SizedBox(width: 12),
              Text('Уровень картинок: $imageLevel'),
            ]),
          ),
          Container(
            height: 120,
            child: Center(
              child: playingImages
                  ? Text(revealIndex == 0 ? '' : sequence[revealIndex - 1], style: TextStyle(fontSize: 48))
                  : (_sequenceEndTime == null && revealIndex > 0)
                      ? Text(sequence[revealIndex - 1], style: TextStyle(fontSize: 48))
                      : Wrap(spacing: 8, children: items.map((it) => ElevatedButton(onPressed: () => onSelectImage(it), child: Text(it))).toList()),
            ),
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TransitionResult {
  final bool shouldAdvance;
  final String reason;
  _TransitionResult(this.shouldAdvance, this.reason);
}

// Choice + Movement exercise
class ChoiceMovementExercise extends StatefulWidget {
  @override
  _ChoiceMovementExerciseState createState() => _ChoiceMovementExerciseState();
}

class _ChoiceMovementExerciseState extends State<ChoiceMovementExercise> {
  final List<LevelConfig> levels = [
    LevelConfig(levelNumber: 1, name: 'Уровень 1 — без инверсии', inversionProbability: 0.0, showHint: false, minSessionStimuli: 20),
    LevelConfig(levelNumber: 2, name: 'Уровень 2 — редкая инверсия', inversionProbability: 0.0, showHint: true, hintText: '★ — наоборот', minSessionStimuli: 20, rareInversionMode: true),
    LevelConfig(levelNumber: 3, name: 'Уровень 3 — частая инверсия', inversionProbability: 0.35, showHint: false, minSessionStimuli: 20),
    LevelConfig(levelNumber: 4, name: 'Уровень 4 — дуальный формат', inversionProbability: 0.35, showHint: false, minSessionStimuli: 20),
  ];

  int currentLevelIndex = 0;
  StimulusType? currentStimulus;
  bool currentIsInversion = false;
  bool running = false;
  Stopwatch? _stopwatch;
  Timer? _itiTimer;
  Random _rng = Random();

  List<StimulusResult> results = [];
  int stimuliShown = 0;
  int countSinceLastRare = 0;

  int auditoryCount = 0;
  
  StimulusType? currentUnderlyingStimulus;

  @override
  void dispose() {
    _itiTimer?.cancel();
    _stopwatch?.stop();
    super.dispose();
  }

  void startSession() {
    setState(() {
      results.clear();
      stimuliShown = 0;
      countSinceLastRare = 0;
      auditoryCount = 0;
      running = true;
    });
    scheduleNextStimulus(delayMs: 500);
  }

  void stopSession() {
    _stopwatch?.stop();
    _itiTimer?.cancel();
    setState(() => running = false);
  }

  void scheduleNextStimulus({int delayMs = 1000}) {
    _itiTimer?.cancel();
    _itiTimer = Timer(Duration(milliseconds: delayMs), () {
      _presentStimulus();
    });
  }

  void _presentStimulus() {
    if (!running) return;
    final cfg = levels[currentLevelIndex];


    bool isInversion = false;
    if (cfg.rareInversionMode) {
      
      countSinceLastRare++;
      if (countSinceLastRare >= 5) {
        if (_rng.nextBool()) {
          isInversion = true;
          countSinceLastRare = 0;
        } else if (countSinceLastRare >= 6) {
          isInversion = true;
          countSinceLastRare = 0;
        }
      }
    } else {
      isInversion = _rng.nextDouble() < cfg.inversionProbability;
    }


    StimulusType stim;
    if (isInversion) {
      
      currentUnderlyingStimulus = _rng.nextBool() ? StimulusType.red : StimulusType.blue;
      stim = StimulusType.star;
    } else {
      currentUnderlyingStimulus = null;
      stim = _rng.nextBool() ? StimulusType.red : StimulusType.blue;
    }

    setState(() {
      currentStimulus = stim;
      currentIsInversion = isInversion;
      stimuliShown++;
    });

    _stopwatch = Stopwatch()..start();


    if (cfg.levelNumber == 4) {
      auditoryCount++;
    }
  }

  void _registerResponse(bool pressedLeft) {
    if (!running || currentStimulus == null || _stopwatch == null) return;
    _stopwatch!.stop();
    final rt = _stopwatch!.elapsedMilliseconds / 1000.0;

    bool correct = false;
    bool wasInversion = currentIsInversion;


    StimulusType stim = currentStimulus!;
    if (stim == StimulusType.star) {
      if (currentUnderlyingStimulus == StimulusType.red) {
        
        correct = (pressedLeft == false);
      } else if (currentUnderlyingStimulus == StimulusType.blue) {
        
        correct = (pressedLeft == true);
      } else {
        
        correct = false;
      }

    } else {
      if (stim == StimulusType.red) correct = pressedLeft == true;
      if (stim == StimulusType.blue) correct = pressedLeft == false;
    }

    results.add(StimulusResult(type: stim, correct: correct, reactionTime: rt, wasInversion: wasInversion));

    setState(() {
      currentStimulus = null;
      currentIsInversion = false;
      currentUnderlyingStimulus = null;
    });


    final cfg = levels[currentLevelIndex];

    if (stimuliShown >= cfg.minSessionStimuli) {
      // evaluate criteria on the last cfg.minSessionStimuli responses and maybe advance
      final transition = _evaluateTransition(cfg);
      if (transition.shouldAdvance) {
        if (currentLevelIndex < levels.length - 1) {
          currentLevelIndex++;
          // reset for next level
          startSession();
          return;
        }
      }
      // do not stop session automatically; continue showing stimuli
    }


    scheduleNextStimulus(delayMs: 700);
  }

  _TransitionResult _evaluateTransition(LevelConfig cfg) {
    if (results.isEmpty) return _TransitionResult(false, 'Нет данных');

    // use only last N results for transition decision
    final n = cfg.minSessionStimuli;
    final window = results.length <= n ? List<StimulusResult>.from(results) : results.sublist(results.length - n);

    final total = window.length;
    final correctCount = window.where((r) => r.correct).length;
    final overallAcc = correctCount / total;

    final inversionResults = window.where((r) => r.wasInversion || r.type == StimulusType.star).toList();
    final inversionCount = inversionResults.length;
    final inversionAcc = inversionCount == 0 ? 1.0 : (inversionResults.where((r) => r.correct).length / inversionCount);

    final maxRT = window.map((r) => r.reactionTime).fold<double>(0.0, (p, e) => max(p, e));

    final starRTs = window.where((r) => r.type == StimulusType.star).map((r) => r.reactionTime).toList();
    final meanStarRT = starRTs.isEmpty ? 0.0 : (starRTs.reduce((a, b) => a + b) / starRTs.length);

    // mean time first 5 vs second 5 (if have at least 10 in window)
    double meanFirst5 = 0.0, meanSecond5 = 0.0;
    if (window.length >= 10) {
      final first5 = window.take(5).map((r) => r.reactionTime).toList();
      final second5 = window.skip(5).take(5).map((r) => r.reactionTime).toList();
      meanFirst5 = first5.reduce((a, b) => a + b) / first5.length;
      meanSecond5 = second5.reduce((a, b) => a + b) / second5.length;
    }

    // series errors on inversion within window
    int maxConsecutiveInvErrors = 0;
    int currentStreak = 0;
    for (var r in window.where((r) => r.type == StimulusType.star || r.wasInversion)) {
      if (!r.correct) {
        currentStreak++;
        if (currentStreak > maxConsecutiveInvErrors) maxConsecutiveInvErrors = currentStreak;
      } else {
        currentStreak = 0;
      }
    }


    if (cfg.levelNumber == 1) {
      bool a1 = overallAcc >= 0.9;
      bool a2 = maxRT <= 1.5;
      bool a3 = true;
      if (results.length >= 10 && meanFirst5 > 0 && meanSecond5 > 0) {
        final diff = (meanFirst5 - meanSecond5).abs();
        final ratio = diff / max(meanFirst5, meanSecond5);
        a3 = ratio <= 0.2;
      }
      final ok = a1 && a2 && a3;
      String reason = 'overall=${(overallAcc * 100).toStringAsFixed(1)}%, maxRT=${maxRT.toStringAsFixed(2)}s';
      return _TransitionResult(ok, reason);
    }


    if (cfg.levelNumber == 2) {
      bool a1 = overallAcc >= 0.85;
      bool a2 = inversionAcc >= 0.7;
      bool a3 = meanStarRT <= 2.5;
      bool a4 = maxConsecutiveInvErrors < 3;
      final ok = a1 && a2 && a3 && a4;
      String reason = 'overall=${(overallAcc * 100).toStringAsFixed(1)}%, inv=${(inversionAcc * 100).toStringAsFixed(1)}%, meanStarRT=${meanStarRT.toStringAsFixed(2)}s';
      return _TransitionResult(ok, reason);
    }


    if (cfg.levelNumber == 3) {
      bool a1 = overallAcc >= 0.85;
      bool a2 = inversionAcc >= 0.75;
      bool a3 = meanStarRT <= 2.5;
      bool a4 = maxConsecutiveInvErrors < 2;
      final ok = a1 && a2 && a3 && a4;
      String reason = 'overall=${(overallAcc * 100).toStringAsFixed(1)}%, inv=${(inversionAcc * 100).toStringAsFixed(1)}%';
      return _TransitionResult(ok, reason);
    }


    if (cfg.levelNumber == 4) {
      bool a1 = overallAcc >= 0.85;
      String reason = 'overall=${(overallAcc * 100).toStringAsFixed(1)}%';
      return _TransitionResult(a1, reason);
    }

    return _TransitionResult(false, 'Нет критериев');
  }

  String _formatStats() {
    if (results.isEmpty) return 'Нет данных';
    final total = results.length;
    final correctCount = results.where((r) => r.correct).length;
    final overallAcc = correctCount / total;
    final inv = results.where((r) => r.type == StimulusType.star).toList();
    final invAcc = inv.isEmpty ? 1.0 : (inv.where((r) => r.correct).length / inv.length);
    final meanRT = results.map((r) => r.reactionTime).reduce((a, b) => a + b) / results.length;
    return 'Уровень ${levels[currentLevelIndex].levelNumber} • Стимулов: $total • Точность: ${(overallAcc * 100).toStringAsFixed(0)}% • RT: ${meanRT.toStringAsFixed(2)}s • Инверсия: ${(invAcc * 100).toStringAsFixed(0)}%';
  }

  Widget _buildStimulusWidget() {
    if (currentStimulus == null) return SizedBox(height: 150);
    if (currentStimulus == StimulusType.red) {
      return Container(width: 150, height: 150, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle));
    }
    if (currentStimulus == StimulusType.blue) {
      return Container(width: 150, height: 150, decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle));
    }
    
    return Container(
      height: 150,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: currentUnderlyingStimulus == StimulusType.red ? Colors.red : Colors.blue,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12),
          Icon(Icons.star, size: 56, color: Colors.yellow[700]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = levels[currentLevelIndex];
    return Scaffold(
      appBar: AppBar(
        title: Text(cfg.name),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Center(child: Text('Уровень ${cfg.levelNumber}')),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_formatStats()),
            if (cfg.rareInversionMode) Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(cfg.hintText, style: TextStyle(fontWeight: FontWeight.bold))),
            if (cfg.levelNumber == 4) Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Считайте вслух: ${auditoryCount + 1}')),
            SizedBox(height: 12),
            Center(child: _buildStimulusWidget()),
            SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
                    onPressed: running ? () => _registerResponse(true) : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.arrow_left, size: 36, color: Colors.black), Text('Левая')],
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
                    onPressed: running ? () => _registerResponse(false) : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.arrow_right, size: 36, color: Colors.black), Text('Правая')],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Wrap(spacing: 8, children: [
              ElevatedButton(
                onPressed: running ? null : startSession,
                child: Text('Старт'),
              ),
              ElevatedButton(
                onPressed: running ? stopSession : null,
                child: Text('Стоп'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    results.clear();
                    stimuliShown = 0;
                    currentStimulus = null;
                    currentIsInversion = false;
                  });
                },
                child: Text('Сброс результатов'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    currentLevelIndex = (currentLevelIndex + 1) % levels.length;
                    results.clear();
                    stimuliShown = 0;
                    currentStimulus = null;
                  });
                },
                child: Text('Переключить уровень'),
              ),
            ]),
            SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Последние стимулы:'),
                    ...results.reversed.take(50).map((r) => ListTile(
                          dense: true,
                          leading: r.type == StimulusType.star ? Icon(Icons.star) : (r.type == StimulusType.red ? CircleAvatar(backgroundColor: Colors.red) : CircleAvatar(backgroundColor: Colors.blue)),
                          title: Text('${r.correct ? '✔' : '✖'} • ${r.reactionTime.toStringAsFixed(2)}s'),
                          subtitle: Text(r.wasInversion ? 'инверсия' : ''),
                        ))
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
