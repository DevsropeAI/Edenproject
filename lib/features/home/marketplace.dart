import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/data/repositories/auth_repository.dart';
import '../auth/domain/auth_state.dart';
import '../auth/providers/auth_provider.dart';

enum Service {
  snow('Snow Removal', 45),
  lawn('Lawn Mowing', 30),
  cleaning('House Cleaning', 85),
  drivewaySnow('Driveway Snow Clearing', 40),
  walkwayClear('Walkway Clearing', 20),
  entranceClear('Front Entrance Clearing', 25),
  leaf('Leaf Removal', 40),
  tree('Tree Trimming', 75),
  landscaping('Landscaping', 80),
  yard('Yard Cleaning', 50),
  pressure('Pressure Washing', 90),
  gutter('Gutter Cleaning', 65),
  hardscaping('Hardscaping', 300),
  paver('Paver Installation', 400),
  drivewayBuild('Driveway Construction', 500),
  walkwayBuild('Walkway Construction', 250),
  retainingWall('Retaining Wall Installation', 450);

  const Service(this.label, this.price);
  final String label;
  final int price;
  bool get isSnow => [
    Service.snow,
    Service.drivewaySnow,
    Service.walkwayClear,
    Service.entranceClear,
  ].contains(this);
}

enum JobStatus {
  searching('Searching for contractor'),
  accepted('Contractor accepted'),
  enRoute('Contractor is on the way'),
  arrived('Contractor arrived'),
  working('Work in progress'),
  submitted('Awaiting customer approval'),
  completed('Completed'),
  cancelled('Cancelled');

  const JobStatus(this.label);
  final String label;
}

String serviceDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class Property {
  const Property(
    this.id,
    this.name,
    this.address,
    this.size,
    this.notes, {
    this.type = "House",
    this.photo,
    this.pin,
    this.isDefault = false,
    this.structuredAddress = const {},
    this.measurements = const {},
    this.cityId,
  });
  final int id;
  final String name;
  final String address;
  final String size;
  final String type;
  final Uint8List? photo;
  final ({double latitude, double longitude})? pin;
  final bool isDefault;
  final Map<String, dynamic> structuredAddress;
  final Map<String, dynamic> measurements;
  final int? cityId;
  String get fullAddress => structuredAddress.isEmpty
      ? address
      : ['street', 'city', 'state', 'postalCode', 'country']
            .map((key) => structuredAddress[key] as String? ?? '')
            .where((value) => value.isNotEmpty)
            .join(', ');

  Property withDefault(bool value) => Property(
    id,
    name,
    address,
    size,
    notes,
    type: type,
    photo: photo,
    pin: pin,
    isDefault: value,
    structuredAddress: structuredAddress,
    measurements: measurements,
    cityId: cityId,
  );
  final String notes;

  factory Property.fromJson(Map<String, dynamic> json) {
    final pin = json['pin'] as Map?;
    return Property(
      json['id'] as int,
      json['name'] as String,
      json['address'] as String,
      json['size'] as String,
      json['notes'] as String,
      type: json['type'] as String,
      photo: _decodeImage(json['photo']),
      isDefault: json['isDefault'] == true,
      structuredAddress: Map<String, dynamic>.from(
        json['structuredAddress'] as Map? ?? {},
      ),
      measurements: Map<String, dynamic>.from(
        json['measurements'] as Map? ?? {},
      ),
      cityId: (json['cityId'] as num?)?.toInt(),
      pin: pin == null
          ? null
          : (
              latitude: (pin['latitude'] as num).toDouble(),
              longitude: (pin['longitude'] as num).toDouble(),
            ),
    );
  }
}

typedef OrderNotice = ({JobStatus status, int version, DateTime at});

String orderNoticeText(JobStatus status) => switch (status) {
  JobStatus.accepted => 'A contractor accepted your booking',
  JobStatus.enRoute => 'Your contractor is on the way',
  JobStatus.submitted => 'Work is ready for your approval',
  _ => status.label,
};

class Booking {
  const Booking({
    required this.id,
    required this.property,
    required this.service,
    required this.date,
    required this.total,
    required this.notes,
    this.recurring = false,
    this.paused = false,
    this.referencePhoto,
    this.status = JobStatus.searching,
    this.before,
    this.after,
    this.messages = const [],
    this.rating,
    this.review = '',
    this.declined = false,
    this.customerNotices = const [],
    this.customerRead = 0,
    this.contractorRead = 0,
    this.scheduledDate,
  });

  final int id;
  final Property property;
  final Service service;
  final DateTime date;
  final String? scheduledDate;
  DateTime get serviceDay =>
      scheduledDate == null ? date : DateTime.parse(scheduledDate!);
  final double total;
  final String notes;
  final bool recurring;
  final bool paused;
  final Uint8List? referencePhoto;
  final JobStatus status;
  final Uint8List? before;
  final Uint8List? after;
  final List<({bool contractor, String text, Uint8List? image})> messages;
  final int? rating;
  final String review;
  final bool declined;
  final List<OrderNotice> customerNotices;
  final int customerRead;
  final int contractorRead;

  bool hasUnreadMessages(bool contractor) => messages
      .skip(contractor ? contractorRead : customerRead)
      .any((message) => message.contractor != contractor);

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    id: json['id'] as int,
    property: Property.fromJson(json['property'] as Map<String, dynamic>),
    service: Service.values.byName(json['service'] as String),
    date: DateTime.parse(json['date'] as String).toLocal(),
    scheduledDate: json['scheduledDate'] as String?,
    total: (json['total'] as num).toDouble(),
    notes: json['notes'] as String,
    status: JobStatus.values.byName(json['status'] as String),
    recurring: json['recurring'] == true,
    paused: json['paused'] == true,
    referencePhoto: _decodeImage(json['referencePhoto']),
    before: _decodeImage(json['before']),
    after: _decodeImage(json['after']),
    rating: json['rating'] as int?,
    review: json['review'] as String? ?? '',
    customerRead: (json['chatRead'] as Map?)?['customer'] as int? ?? 0,
    contractorRead: (json['chatRead'] as Map?)?['contractor'] as int? ?? 0,
    customerNotices: [
      for (final notice in json['customerNotices'] as List? ?? const [])
        (
          status: JobStatus.values.byName(notice['status'] as String),
          version: notice['version'] as int,
          at: DateTime.parse(notice['at'] as String).toLocal(),
        ),
    ],
    messages: [
      for (final message in json['messages'] as List)
        (
          contractor: message['contractor'] == true,
          text: message['text'] as String,
          image: _decodeImage(message['image']),
        ),
    ],
  );

  Booking update({
    JobStatus? status,
    Uint8List? before,
    Uint8List? after,
    List<({bool contractor, String text, Uint8List? image})>? messages,
    int? rating,
    String? review,
    bool? declined,
    bool clearAfter = false,
  }) => Booking(
    id: id,
    property: property,
    service: service,
    date: date,
    scheduledDate: scheduledDate,
    total: total,
    notes: notes,
    recurring: recurring,
    paused: paused,
    referencePhoto: referencePhoto,
    status: status ?? this.status,
    before: before ?? this.before,
    after: clearAfter ? null : after ?? this.after,
    messages: messages ?? this.messages,
    rating: rating ?? this.rating,
    review: review ?? this.review,
    declined: declined ?? this.declined,
    customerNotices: customerNotices,
    customerRead: customerRead,
    contractorRead: contractorRead,
  );
}

Uint8List? _decodeImage(Object? value) =>
    value is String ? base64Decode(value) : null;
String? _encodeImage(Uint8List? value) =>
    value == null ? null : base64Encode(value);

final marketplaceFeedbackProvider =
    NotifierProvider<MarketplaceFeedback, String?>(MarketplaceFeedback.new);

class MarketplaceFeedback extends Notifier<String?> {
  @override
  String? build() => null;

  void report(Object error) {
    state = null;
    state = apiError(error);
  }
}

final _marketplaceModeProvider = Provider(
  (ref) => ref
      .watch(authProvider)
      .maybeWhen(
        authenticated: (user) => (id: user.id, role: user.role),
        orElse: () => null,
      ),
);

final serviceCatalogProvider = FutureProvider.autoDispose<Map<Service, int>>((
  ref,
) async {
  final response = await ref.watch(apiClientProvider).get('/services');
  return {
    for (final service in response.data as List)
      Service.values.byName(service['id'] as String):
          service['priceCents'] as int,
  };
});

final serviceDetailsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final response = await ref.watch(apiClientProvider).get('/services');
      return (response.data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    });
final addOnsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  final response = await ref.watch(apiClientProvider).get('/add-ons');
  return (response.data as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
});
final quoteProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, key) async {
      final api = ref.watch(apiClientProvider);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!ref.mounted) return {};
      final response = await api.post('/quotes', data: jsonDecode(key));
      return Map<String, dynamic>.from(response.data as Map);
    });

final propertiesProvider = NotifierProvider<Properties, List<Property>>(
  Properties.new,
);
final bookingsProvider = NotifierProvider<Bookings, List<Booking>>(
  Bookings.new,
);

abstract class MarketplaceRecords<T> extends Notifier<List<T>> {
  int _generation = 0;
  int _refreshCount = 0;
  bool _saving = false;

  String get path;
  T decode(Map<String, dynamic> json);

  @override
  List<T> build() {
    final account = ref.watch(_marketplaceModeProvider);
    final generation = ++_generation;
    _saving = false;
    if (account != null &&
        (path != '/properties' || account.role == 'customer')) {
      unawaited(Future<void>.microtask(() => refresh()));
      if (path == '/bookings') {
        final timer = Timer.periodic(const Duration(seconds: 12), (_) {
          if (generation == _generation && !_saving)
            unawaited(refresh(silent: true));
        });
        ref.onDispose(timer.cancel);
      }
    }
    return [];
  }

  Future<void> refresh({bool silent = false}) async {
    if (!ref.mounted) return;
    final generation = _generation;
    final sequence = ++_refreshCount;
    try {
      final response = await ref.read(apiClientProvider).get(path);
      if (ref.mounted &&
          generation == _generation &&
          sequence == _refreshCount) {
        state = (response.data as List)
            .map((json) => decode(json as Map<String, dynamic>))
            .toList();
      }
    } catch (error) {
      if (!silent && ref.mounted && generation == _generation) {
        ref.read(marketplaceFeedbackProvider.notifier).report(error);
      }
    }
  }

  Future<bool> saveChange(
    Future<void> Function(ApiClient api) operation,
  ) async {
    if (_saving) return false;
    _saving = true;
    final generation = _generation;
    try {
      await operation(ref.read(apiClientProvider));
      if (!ref.mounted || generation != _generation) return false;
      await refresh();
      return ref.mounted && generation == _generation;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        ref.read(marketplaceFeedbackProvider.notifier).report(error);
        await refresh(silent: true);
      }
      return false;
    } finally {
      if (generation == _generation) _saving = false;
    }
  }
}

class Properties extends MarketplaceRecords<Property> {
  @override
  String get path => '/properties';

  @override
  Property decode(Map<String, dynamic> json) => Property.fromJson(json);

  Future<bool> save(
    int? id,
    String name,
    String address,
    String size,
    String notes, {
    required String type,
    Uint8List? photo,
    ({double latitude, double longitude})? pin,
    Map<String, dynamic>? structuredAddress,
    Map<String, dynamic>? measurements,
    Map<String, dynamic>? addressSelection,
  }) => saveChange((api) async {
    await api.post(
      path,
      data: {
        'id': id,
        'name': name,
        'address': address,
        'size': size,
        'notes': notes,
        'type': type,
        'photo': _encodeImage(photo),
        'pin': pin == null
            ? null
            : {'latitude': pin.latitude, 'longitude': pin.longitude},
        if (structuredAddress != null) 'structuredAddress': structuredAddress,
        if (measurements != null) 'measurements': measurements,
        if (addressSelection != null) 'addressSelection': addressSelection,
      },
    );
  });

  Future<bool> setDefault(int id) => saveChange((api) async {
    await api.post('$path/$id/default');
  });

  Future<bool> remove(int id) => saveChange((api) async {
    await api.delete('$path/$id');
  });
}

class Bookings extends MarketplaceRecords<Booking> {
  Future<void> markMessagesRead(int id, int count) async {
    await ref
        .read(apiClientProvider)
        .post('$path/$id', data: {'action': 'read', 'count': count});
    await refresh(silent: true);
  }

  @override
  String get path => '/bookings';

  @override
  Booking decode(Map<String, dynamic> json) => Booking.fromJson(json);

  Future<bool> place(
    Property property,
    Service service,
    DateTime date,
    String notes,
    bool recurring, {
    Uint8List? referencePhoto,
    bool urgent = false,
    bool walkway = false,
    bool discount = false,
    String? couponCode,
    String? snowDepth,
    List<String> addOnIds = const [],
    int? expectedTotalCents,
  }) => saveChange((api) async {
    await api.post(
      path,
      data: {
        'propertyId': property.id,
        'service': service.name,
        'scheduledDate': serviceDateKey(date),
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        'notes': notes,
        'recurring': recurring,
        'referencePhoto': _encodeImage(referencePhoto),
        'urgent': urgent,
        'walkway': walkway,
        'discount': discount,
        if (couponCode != null) 'couponCode': couponCode,
        if (snowDepth != null) 'snowDepth': snowDepth,
        'addOnIds': addOnIds,
        if (expectedTotalCents != null)
          'expectedTotalCents': expectedTotalCents,
      },
    );
  });

  Future<bool> setWeeklyPaused(int id, bool paused) => saveChange((api) async {
    await api.post('$path/$id', data: {'action': 'weekly', 'paused': paused});
  });

  Future<bool> change(int id, Booking Function(Booking) update) async {
    final current = state.where((booking) => booking.id == id).firstOrNull;
    if (current == null) return false;
    final next = update(current);
    Map<String, dynamic> command;
    if (identical(current, next)) return false;
    if (next.declined) {
      command = {'action': 'decline'};
    } else if (next.status != current.status) {
      command = switch (next.status) {
        JobStatus.accepted => {'action': 'accept'},
        JobStatus.working when current.status == JobStatus.submitted => {
          'action': 'rework',
        },
        _ => {'action': 'advance', 'status': next.status.name},
      };
    } else if (next.before != current.before || next.after != current.after) {
      final before = next.before != current.before;
      command = {
        'action': before ? 'before' : 'after',
        'image': _encodeImage(before ? next.before : next.after),
      };
    } else if (next.rating != current.rating) {
      command = {
        'action': 'review',
        'rating': next.rating,
        'review': next.review,
      };
    } else if (next.messages.length > current.messages.length) {
      final message = next.messages.last;
      command = {
        'action': 'message',
        'text': message.text,
        'image': _encodeImage(message.image),
      };
    } else {
      return false;
    }
    return saveChange((api) async {
      await api.post('$path/$id', data: command);
    });
  }

  Future<bool> release(int id) => saveChange((api) async {
    await api.post('$path/$id', data: {'action': 'release'});
  });

  Future<bool> bookingAction(int id, String action) => saveChange((api) async {
    await api.post('$path/$id', data: {'action': action});
  });

  Future<Map<String, dynamic>> previewBookingEdit(
    int id,
    DateTime date,
    String notes,
    Map<String, dynamic> measurements,
    String propertyNotes,
  ) async {
    final r = await ref
        .read(apiClientProvider)
        .post(
          '$path/$id',
          data: {
            'action': 'previewEdit',
            'scheduledDate': serviceDateKey(date),
            'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
            'notes': notes,
            'measurements': measurements,
            'propertyNotes': propertyNotes,
          },
        );
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<bool> editSchedule(
    int id,
    DateTime date,
    String notes, {
    Map<String, dynamic>? measurements,
    String? propertyNotes,
    int? expectedTotalCents,
  }) => saveChange((api) async {
    await api.post(
      '$path/$id',
      data: {
        'action': 'edit',
        'scheduledDate': serviceDateKey(date),
        'utcOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        'notes': notes,
        if (measurements != null) 'measurements': measurements,
        if (propertyNotes != null) 'propertyNotes': propertyNotes,
        if (expectedTotalCents != null)
          'expectedTotalCents': expectedTotalCents,
      },
    );
  });
}
