import 'package:flutter_test/flutter_test.dart';
import 'package:soulsync/features/safety/domain/models/safety_models.dart';

void main() {
  test('Haversine distance calculation in km matches known geodesic distance', () {
    // New Delhi (28.6139, 77.2090) to Noida (28.5355, 77.3910) ~ 19.8 km
    final km = HaversineCalculator.distanceKm(28.6139, 77.2090, 28.5355, 77.3910);
    expect(km, greaterThan(19.0));
    expect(km, lessThan(20.6));
  });

  test('TravelMode enum maps car, bike, walking, and unknown cleanly', () {
    expect(TravelMode.fromId('car'), TravelMode.car);
    expect(TravelMode.fromId('bike'), TravelMode.bike);
    expect(TravelMode.fromId('walking'), TravelMode.walking);
    expect(TravelMode.fromId('unknown_mode'), TravelMode.stationary);
  });

  test('SafetyStateModel parses strict privacy and consent defaults', () {
    final model = SafetyStateModel.fromJson({
      'couple_id': 'c_u5_u4',
      'config': {'enabled': true, 'speed_alerts_enabled': true},
      'my_session': {
        'status': 'stopped',
        'consents': {'location': false, 'history': false},
      },
      'distance': {'straight_line_km': null, 'is_live': false},
    });
    expect(model.myConsents.location, isFalse);
    expect(model.myConsents.history, isFalse);
    expect(model.straightLineKm, isNull);
  });
}
