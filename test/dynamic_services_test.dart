import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual address corrections are displayed without deleting structured metadata', () {
    const property = Property(1, 'Home', 'Corrected entrance, Lahore', 'Large', '', structuredAddress: {'street':'Old entrance','city':'Lahore','country':'Pakistan'});
    expect(property.fullAddress, 'Corrected entrance, Lahore');
    expect(property.structuredAddress['street'], 'Old entrance');
  });
  test('retired custom service history and long-term metadata survive decoding and updates', () {
    final booking = Booking.fromJson({'id':1,'property':{'id':1,'name':'Home','address':'Street','size':'Large','type':'House','notes':''},'service':'inactive-custom','serviceTitle':'Window Cleaning','date':'2026-11-25T00:00:00Z','total':84.75,'notes':'Instructions','status':'searching','messages':[],'bookingType':'long_term','customerName':'Customer'});
    expect(booking.service.label, 'Window Cleaning');
    expect(booking.total, 84.75);
    expect(booking.update(status: JobStatus.accepted).bookingType, 'long_term');
    expect(booking.update(status: JobStatus.accepted).customerName, 'Customer');
  });
  test('custom catalog services have stable IDs and readable names', () {
    final service = Service.fromId('svc123', title: 'Window Cleaning');
    expect(service.name, 'svc123');
    expect(service.label, 'Window Cleaning');
    expect(Service.fromId('svc123'), service);
    expect({service: 7500}[Service.fromId('svc123')], 7500);
    expect(service.isSnow, isFalse);
  });
  test('legacy IDs retain their identity and snow controls', () {
    expect(Service.fromId('snow'), Service.snow);
    expect(Service.snow.isSnow, isTrue);
    expect(Service.lawn.isSnow, isFalse);
    expect(Service.fromId('retired-service').label, 'retired-service');
  });
}
