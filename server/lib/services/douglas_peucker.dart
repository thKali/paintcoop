import 'dart:math';

// Reduces a list of points by removing redundant intermediate points.
// epsilon: maximum allowed distance (in pixels) from the simplified line.
// Smaller epsilon = more points kept = more precise.
// Larger epsilon = fewer points kept = more compressed.
List<T> douglasPeucker<T>(
  List<T> points,
  double epsilon,
  double Function(T) getX,
  double Function(T) getY,
) {
  if (points.length < 3) return points;

  // Find the point farthest from the line between first and last
  final first = points.first;
  final last = points.last;
  var maxDistance = 0.0;
  var maxIndex = 0;

  for (var i = 1; i < points.length - 1; i++) {
    final d = _perpendicularDistance(
      getX(points[i]), getY(points[i]),
      getX(first), getY(first),
      getX(last), getY(last),
    );
    if (d > maxDistance) {
      maxDistance = d;
      maxIndex = i;
    }
  }

  // If the farthest point is within epsilon, discard all intermediates
  if (maxDistance <= epsilon) {
    return [first, last];
  }

  // Otherwise, the farthest point is important — recurse on both halves
  final left = douglasPeucker(
    points.sublist(0, maxIndex + 1), epsilon, getX, getY,
  );
  final right = douglasPeucker(
    points.sublist(maxIndex), epsilon, getX, getY,
  );

  // Merge — drop the duplicate point at the junction
  return [...left, ...right.skip(1)];
}

// Perpendicular distance from point (px, py) to the line defined by (ax, ay)→(bx, by)
double _perpendicularDistance(
  double px, double py,
  double ax, double ay,
  double bx, double by,
) {
  final dx = bx - ax;
  final dy = by - ay;

  // Degenerate case: line is actually a point
  if (dx == 0 && dy == 0) {
    return sqrt(pow(px - ax, 2) + pow(py - ay, 2));
  }

  // Area of the triangle formed by the three points, divided by base length
  final numerator = ((dy * px) - (dx * py) + (bx * ay) - (by * ax)).abs();
  final denominator = sqrt(dx * dx + dy * dy);
  return numerator / denominator;
}
