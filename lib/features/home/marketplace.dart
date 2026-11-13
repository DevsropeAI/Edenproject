import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  arrived('Contractor arrived'),
  working('Work in progress'),
  submitted('Awaiting customer approval'),
  completed('Completed');

  const JobStatus(this.label);
  final String label;
}

class Property {
  const Property(this.id, this.name, this.address, this.size, this.notes);
  final int id;
  final String name;
  final String address;
  final String size;
  final String notes;
}

class Booking {
  const Booking({
    required this.id,
    required this.property,
    required this.service,
    required this.date,
    required this.total,
    required this.notes,
    this.recurring = false,
    this.status = JobStatus.searching,
    this.before,
    this.after,
    this.messages = const [],
    this.rating,
    this.review = '',
    this.declined = false,
  });

  final int id;
  final Property property;
  final Service service;
  final DateTime date;
  final double total;
  final String notes;
  final bool recurring;
  final JobStatus status;
  final Uint8List? before;
  final Uint8List? after;
  final List<({bool contractor, String text})> messages;
  final int? rating;
  final String review;
  final bool declined;

  Booking update({
    JobStatus? status,
    Uint8List? before,
    Uint8List? after,
    List<({bool contractor, String text})>? messages,
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
    status: status ?? this.status,
    before: before ?? this.before,
    after: clearAfter ? null : after ?? this.after,
    messages: messages ?? this.messages,
    rating: rating ?? this.rating,
    review: review ?? this.review,
    declined: declined ?? this.declined,
  );
}

final propertiesProvider = NotifierProvider<Properties, List<Property>>(
  Properties.new,
);
final bookingsProvider = NotifierProvider<Bookings, List<Booking>>(
  Bookings.new,
);

class Properties extends Notifier<List<Property>> {
  int _nextId = 2;

  @override
  List<Property> build() => const [
    Property(
      1,
      'Maple House',
      '123 Maple St, Toronto',
      'Standard',
      'Use the side gate.',
    ),
  ];

  void save(int? id, String name, String address, String size, String notes) {
    final property = Property(id ?? _nextId++, name, address, size, notes);
    state = id == null
        ? [...state, property]
        : [
            for (final existing in state)
              existing.id == id ? property : existing,
          ];
  }

  void remove(int id) =>
      state = state.where((property) => property.id != id).toList();
}

class Bookings extends Notifier<List<Booking>> {
  int _nextId = 2;

  @override
  List<Booking> build() => [
    Booking(
      id: 1,
      property: const Property(
        1,
        'Maple House',
        '123 Maple St, Toronto',
        'Standard',
        'Use the side gate.',
      ),
      service: Service.snow,
      date: DateTime.now().add(const Duration(days: 1)),
      total: 50.85,
      notes: 'Please clear the driveway and front entrance.',
    ),
  ];

  void place(
    Property property,
    Service service,
    DateTime date,
    double total,
    String notes,
    bool recurring,
  ) {
    state = [
      Booking(
        id: _nextId++,
        property: property,
        service: service,
        date: date,
        total: total,
        notes: notes,
        recurring: recurring,
      ),
      ...state,
    ];
  }

  void change(int id, Booking Function(Booking) update) {
    state = [
      for (final booking in state) booking.id == id ? update(booking) : booking,
    ];
  }
}
