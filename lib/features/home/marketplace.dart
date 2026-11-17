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
  cleaning('House Cleaning', 85);

  const Service(this.label, this.price);
  final String label;
  final int price;
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
  });
  final int id;
  final String name;
  final String address;
  final String size;
  final String type;
  final Uint8List? photo;
  final ({double latitude, double longitude})? pin;
  final bool isDefault;

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
  });

  final int id;
  final Property property;
  final Service service;
  final DateTime date;
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

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
    id: json['id'] as int,
    property: Property.fromJson(json['property'] as Map<String, dynamic>),
    service: Service.values.byName(json['service'] as String),
    date: DateTime.parse(json['date'] as String).toLocal(),
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
  }) => saveChange((api) async {
    await api.post(
      path,
      data: {
        'propertyId': property.id,
        'service': service.name,
        'date': date.toUtc().toIso8601String(),
        'notes': notes,
        'recurring': recurring,
        'referencePhoto': _encodeImage(referencePhoto),
        'urgent': urgent,
        'walkway': walkway,
        'discount': discount,
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
}
