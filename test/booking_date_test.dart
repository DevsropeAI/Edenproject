import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/marketplace_screens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Booking booking({String? day}) => Booking(
    id: 1,
    property: const Property(1, 'Home', 'Address', 'Standard', ''),
    service: Service.snow,
    date: DateTime.utc(2026, 11, 23, 12),
    scheduledDate: day,
    total: 45,
    notes: '',
  );
  test('date-only bookings display their calendar day without a made-up appointment time', () {
    final value = booking(day: '2026-11-23');
    expect(bookingDateLabel(value), 'Mon, Nov 23, 2026');
    expect(
      value.update(status: JobStatus.accepted).scheduledDate,
      '2026-11-23',
    );
    expect(serviceDateKey(value.serviceDay), '2026-11-23');
  });
  test('legacy bookings keep their timestamp and existing time display', () {
    final value = booking();
    expect(value.date, DateTime.utc(2026, 11, 23, 12));
    expect(value.scheduledDate, isNull);
    expect(bookingDateLabel(value), contains('12:00 PM'));
  });
}
