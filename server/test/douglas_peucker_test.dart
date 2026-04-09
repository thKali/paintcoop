import 'dart:math';
import 'package:test/test.dart';
import 'package:server/services/douglas_peucker.dart';

// Simple point for testing
typedef P = ({double x, double y});

List<P> compress(List<P> pts, double epsilon) =>
    douglasPeucker(pts, epsilon, (p) => p.x, (p) => p.y);

void main() {
  group('Douglas-Peucker', () {
    test('straight line collapses to 2 points', () {
      // 100 points perfectly on the line y = x
      final line = [for (var i = 0.0; i < 100; i++) (x: i, y: i)];
      final result = compress(line, 1.0);
      expect(result.length, 2);
      expect(result.first, line.first);
      expect(result.last, line.last);
    });

    test('single sharp peak is preserved', () {
      // Flat line with one spike in the middle
      final points = [
        (x: 0.0, y: 0.0),
        (x: 50.0, y: 100.0), // spike — far from the A→C line
        (x: 100.0, y: 0.0),
      ];
      final result = compress(points, 1.0);
      expect(result.length, 3); // all three kept
      expect(result[1].y, 100.0);
    });

    test('points within epsilon are discarded', () {
      // Almost-straight line with tiny deviations (< 1px)
      final points = [
        (x: 0.0, y: 0.0),
        (x: 50.0, y: 0.3), // 0.3px off — below epsilon
        (x: 100.0, y: 0.0),
      ];
      final result = compress(points, 1.0);
      expect(result.length, 2);
    });

    test('passes through with fewer than 3 points unchanged', () {
      final two = [(x: 0.0, y: 0.0), (x: 10.0, y: 10.0)];
      expect(compress(two, 1.0), two);

      final one = [(x: 5.0, y: 5.0)];
      expect(compress(one, 1.0), one);
    });

    test('higher epsilon discards more points', () {
      // Gentle curve
      final curve = [
        for (var i = 0; i <= 100; i++)
          (x: i.toDouble(), y: sin(i * pi / 100) * 10),
      ];

      final tight = compress(curve, 0.5);
      final loose = compress(curve, 5.0);

      expect(loose.length, lessThan(tight.length));
    });

    test('first and last points are always preserved', () {
      final points = [
        for (var i = 0.0; i < 50; i++) (x: i, y: i * 0.5),
      ];
      final result = compress(points, 10.0);
      expect(result.first, points.first);
      expect(result.last, points.last);
    });

    test('empty list returns empty', () {
      expect(compress([], 1.0), isEmpty);
    });
  });
}
