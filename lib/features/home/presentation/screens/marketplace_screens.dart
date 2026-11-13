import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../marketplace.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/domain/auth_state.dart';

const _green = Color(0xFF164D36);
const _mint = Color(0xFFEAF5ED);
final _money = NumberFormat.simpleCurrency(name: 'CAD');
final _date = DateFormat('EEE, MMM d • h:mm a');

class MarketPage extends StatelessWidget {
  const MarketPage({
    super.key,
    required this.title,
    required this.children,
    this.nav,
  });
  final String title;
  final List<Widget> children;
  final int? nav;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F8F5),
    appBar: AppBar(title: Text(title)),
    bottomNavigationBar: nav == null
        ? null
        : NavigationBar(
            selectedIndex: nav!,
            onDestinationSelected: (index) =>
                context.go(['/customer-home', '/bookings', '/profile'][index]),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                label: 'Bookings',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: 'Profile',
              ),
            ],
          ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 16), child: child),
          ],
        ),
      ),
    ),
  );
}

class MarketBanner extends StatelessWidget {
  const MarketBanner(this.title, this.subtitle, this.icon, {super.key});
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [_green, Color(0xFF317754)]),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Icon(icon, color: const Color(0xFFC1E9CE), size: 42),
      ],
    ),
  );
}

class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDDE7DE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final child in children)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: child,
          ),
      ],
    ),
  );
}

class PropertiesScreen extends ConsumerWidget {
  const PropertiesScreen({super.key, this.service});
  final Service? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);
    return MarketPage(
      title: 'Properties',
      children: [
        const MarketBanner(
          'Your places',
          'Choose where you need a service, or add another property.',
          Icons.home_work_outlined,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _PropertyEditor(),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add property'),
          ),
        ),
        if (properties.isEmpty)
          const MarketCard(
            children: [Text('Add a property to start a booking.')],
          ),
        for (final property in properties)
          MarketCard(
            children: [
              Text(
                property.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(property.address),
              Text('${property.size} property'),
              if (property.notes.isNotEmpty) Text(property.notes),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () =>
                        context.push('/booking/${property.id}', extra: service),
                    child: const Text('Book a service'),
                  ),
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _PropertyEditor(property: property),
                    ),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final remove = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text('Remove ${property.name}?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (context.mounted && remove == true) {
                        ref
                            .read(propertiesProvider.notifier)
                            .remove(property.id);
                      }
                    },
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class _PropertyEditor extends ConsumerStatefulWidget {
  const _PropertyEditor({this.property});
  final Property? property;

  @override
  ConsumerState<_PropertyEditor> createState() => _PropertyEditorState();
}

class _PropertyEditorState extends ConsumerState<_PropertyEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.property?.name);
  late final _address = TextEditingController(text: widget.property?.address);
  late final _notes = TextEditingController(text: widget.property?.notes);
  late String _size = widget.property?.size ?? 'Standard';

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.property == null ? 'Add property' : 'Edit property'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_name, 'Property name', required: true),
              _field(
                _address,
                'Street address, city and postal code',
                required: true,
              ),
              DropdownButtonFormField<String>(
                initialValue: _size,
                decoration: const InputDecoration(labelText: 'Property size'),
                items: [
                  for (final size in ['Small', 'Standard', 'Large'])
                    DropdownMenuItem(value: size, child: Text(size)),
                ],
                onChanged: (size) => setState(() => _size = size!),
              ),
              _field(_notes, 'Access instructions'),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          ref
              .read(propertiesProvider.notifier)
              .save(
                widget.property?.id,
                _name.text.trim(),
                _address.text.trim(),
                _size,
                _notes.text.trim(),
              );
          Navigator.pop(context);
        },
        child: const Text('Save property'),
      ),
    ],
  );
}

Widget _field(
  TextEditingController controller,
  String label, {
  bool required = false,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 6),
  child: TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    validator: required
        ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
        : null,
  ),
);

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.propertyId, this.service});
  final int? propertyId;
  final Service? service;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  late Service _service = widget.service ?? Service.snow;
  final _notes = TextEditingController();
  DateTime? _scheduled;
  bool _urgent = false;
  bool _recurring = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _scheduled ?? now,
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _scheduled ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (!mounted || time == null) return;
    final selected = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (selected.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a future time.')));
      return;
    }
    setState(() => _scheduled = selected);
  }

  @override
  Widget build(BuildContext context) {
    final property = ref
        .watch(propertiesProvider)
        .where((item) => item.id == widget.propertyId)
        .firstOrNull;
    if (property == null) {
      return const MarketPage(
        title: 'Book a service',
        children: [Text('Property unavailable.')],
      );
    }
    final base = _service.price + (property.size == 'Large' ? 15 : 0);
    final rushFee = _urgent ? 20 : 0;
    final tax = (base + rushFee) * .13;
    final total = base + rushFee + tax;
    return MarketPage(
      title: 'Book a service',
      children: [
        MarketBanner(
          property.name,
          property.address,
          Icons.event_available_outlined,
        ),
        MarketCard(
          children: [
            DropdownButtonFormField<Service>(
              initialValue: _service,
              decoration: const InputDecoration(labelText: 'Service'),
              items: [
                for (final service in Service.values)
                  DropdownMenuItem(value: service, child: Text(service.label)),
              ],
              onChanged: (service) => setState(() => _service = service!),
            ),
            OutlinedButton.icon(
              onPressed: _pickSchedule,
              icon: const Icon(Icons.schedule),
              label: Text(
                _scheduled == null
                    ? 'Choose date and time'
                    : _date.format(_scheduled!),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Urgent booking'),
              value: _urgent,
              onChanged: (value) => setState(() => _urgent = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Weekly service preference'),
              value: _recurring,
              onChanged: (value) => setState(() => _recurring = value),
            ),
            _field(_notes, 'Instructions for the contractor'),
          ],
        ),
        MarketCard(
          children: [
            Text(
              'Instant quote',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Service  ${_money.format(base)}'),
            if (_urgent) Text('Urgent fee  ${_money.format(rushFee)}'),
            Text('Estimated tax  ${_money.format(tax)}'),
            const Divider(),
            Text(
              'Total  ${_money.format(total)} CAD',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text('Demo booking. No payment is collected.'),
            FilledButton(
              onPressed: _scheduled == null
                  ? null
                  : () {
                      if (!_scheduled!.isAfter(DateTime.now())) {
                        setState(() => _scheduled = null);
                        return;
                      }
                      ref
                          .read(bookingsProvider.notifier)
                          .place(
                            property,
                            _service,
                            _scheduled!,
                            total,
                            _notes.text.trim(),
                            _recurring,
                          );
                      context.go('/bookings');
                    },
              child: const Text('Confirm booking'),
            ),
          ],
        ),
      ],
    );
  }
}

class BookingListScreen extends ConsumerWidget {
  const BookingListScreen({super.key, this.contractor = false});
  final bool contractor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsProvider);
    final visible = bookings.where(
      (booking) => !contractor || !booking.declined,
    );
    return MarketPage(
      title: contractor ? 'Eden Contractor' : 'My bookings',
      nav: contractor ? null : 1,
      children: [
        MarketBanner(
          contractor ? 'Job dashboard' : 'Your bookings',
          contractor
              ? 'Find new work and manage your accepted jobs.'
              : 'Follow service progress and review finished work.',
          contractor ? Icons.handyman_outlined : Icons.receipt_long_outlined,
        ),
        if (contractor)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/profile', extra: true),
              icon: const Icon(Icons.person_outline),
              label: const Text('Profile & settings'),
            ),
          ),
        if (visible.isEmpty)
          const MarketCard(children: [Text('Nothing to show yet.')]),
        for (final (title, statuses)
            in (contractor
                ? [
                    ('Available jobs', [JobStatus.searching]),
                    (
                      'Active jobs',
                      [
                        JobStatus.accepted,
                        JobStatus.arrived,
                        JobStatus.working,
                        JobStatus.submitted,
                      ],
                    ),
                    ('Completed jobs', [JobStatus.completed]),
                  ]
                : [
                    (
                      'Active',
                      JobStatus.values.where(
                        (status) => status != JobStatus.completed,
                      ),
                    ),
                    ('Past bookings', [JobStatus.completed]),
                  ]))
          if (visible.any((booking) => statuses.contains(booking.status))) ...[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            for (final booking in visible.where(
              (booking) => statuses.contains(booking.status),
            ))
              MarketCard(
                children: [
                  Text(
                    booking.service.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(booking.property.address),
                  Text(
                    '${_date.format(booking.date)} · ${_money.format(booking.total)} CAD',
                  ),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(booking.status.label),
                        backgroundColor: _mint,
                      ),
                      TextButton(
                        onPressed: () => context.push(
                          '/${contractor ? 'job-details' : 'bookings'}/${booking.id}',
                        ),
                        child: const Text('View details'),
                      ),
                    ],
                  ),
                ],
              ),
          ],
      ],
    );
  }
}

class BookingDetailsScreen extends ConsumerWidget {
  const BookingDetailsScreen({
    super.key,
    required this.id,
    this.contractor = false,
  });
  final int? id;
  final bool contractor;

  Future<void> _pickPhoto(
    BuildContext context,
    WidgetRef ref,
    Booking booking, {
    required bool before,
  }) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      if (bytes.length > 10 * 1024 * 1024) {
        throw StateError('Photo exceeds 10 MB');
      }
      ref.read(bookingsProvider.notifier).change(booking.id, (current) {
        if (current.status != booking.status) return current;
        return before
            ? current.update(before: bytes)
            : current.update(after: bytes);
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open photo. Try an image under 10 MB.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref
        .watch(bookingsProvider)
        .where((item) => item.id == id)
        .firstOrNull;
    if (booking == null) {
      return const MarketPage(
        title: 'Booking details',
        children: [Text('Booking unavailable.')],
      );
    }
    final notifier = ref.read(bookingsProvider.notifier);
    void advance(JobStatus next) => notifier.change(
      booking.id,
      (current) => current.status == booking.status
          ? current.update(status: next)
          : current,
    );
    return MarketPage(
      title: contractor ? 'Job details' : 'Booking details',
      children: [
        MarketBanner(
          booking.service.label,
          booking.property.address,
          Icons.assignment_outlined,
        ),
        MarketCard(
          children: [
            Chip(label: Text(booking.status.label), backgroundColor: _mint),
            Text(_date.format(booking.date)),
            Text('${_money.format(booking.total)} CAD'),
            if (booking.recurring) const Text('Weekly service requested'),
            if (booking.property.notes.isNotEmpty) Text(booking.property.notes),
            if (booking.notes.isNotEmpty) Text(booking.notes),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push('/chat/${booking.id}', extra: contractor),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Messages'),
            ),
          ],
        ),
        if (booking.before != null ||
            booking.after != null ||
            (contractor &&
                [
                  JobStatus.arrived,
                  JobStatus.working,
                ].contains(booking.status)))
          MarketCard(
            children: [
              Text(
                'Work photos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final (label, bytes) in [
                ('Before', booking.before),
                ('After', booking.after),
              ])
                if (bytes != null) ...[
                  Text(label),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      bytes,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stackTrace) =>
                          const Text('Photo preview unavailable'),
                    ),
                  ),
                ],
              if (contractor && booking.status == JobStatus.arrived)
                OutlinedButton.icon(
                  onPressed: () =>
                      _pickPhoto(context, ref, booking, before: true),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Choose before photo'),
                ),
              if (contractor && booking.status == JobStatus.working)
                OutlinedButton.icon(
                  onPressed: () =>
                      _pickPhoto(context, ref, booking, before: false),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Choose after photo'),
                ),
            ],
          ),
        if (contractor && !booking.declined) ...[
          if (booking.status == JobStatus.searching)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => advance(JobStatus.accepted),
                  child: const Text('Accept job'),
                ),
                OutlinedButton(
                  onPressed: () {
                    notifier.change(
                      booking.id,
                      (current) => current.update(declined: true),
                    );
                    context.go('/contractor-home');
                  },
                  child: const Text('Decline'),
                ),
              ],
            ),
          if (booking.status == JobStatus.accepted)
            FilledButton(
              onPressed: () => advance(JobStatus.arrived),
              child: const Text('Mark arrived'),
            ),
          if (booking.status == JobStatus.arrived)
            FilledButton(
              onPressed: booking.before == null
                  ? null
                  : () => advance(JobStatus.working),
              child: const Text('Start work'),
            ),
          if (booking.status == JobStatus.working)
            FilledButton(
              onPressed: booking.after == null
                  ? null
                  : () => advance(JobStatus.submitted),
              child: const Text('Submit completed work'),
            ),
        ],
        if (!contractor && booking.status == JobStatus.submitted)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => advance(JobStatus.completed),
                child: const Text('Approve work'),
              ),
              OutlinedButton(
                onPressed: () {
                  notifier.change(
                    booking.id,
                    (current) => current.update(
                      status: JobStatus.working,
                      clearAfter: true,
                      messages: [
                        ...current.messages,
                        (
                          contractor: false,
                          text: 'I requested rework. Please check in before resubmitting.',
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Request rework'),
              ),
            ],
          ),
        if (!contractor &&
            booking.status == JobStatus.completed &&
            booking.rating == null)
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ReviewDialog(id: booking.id),
            ),
            child: const Text('Rate the service'),
          ),
        if (booking.rating != null)
          MarketCard(
            children: [
              Text('Customer rating · ${booking.rating}/5'),
              if (booking.review.isNotEmpty) Text(booking.review),
            ],
          ),
      ],
    );
  }
}

class _ReviewDialog extends ConsumerStatefulWidget {
  const _ReviewDialog({required this.id});
  final int id;
  @override
  ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
  int _rating = 0;
  final _review = TextEditingController();

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rate the service'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          children: [
            for (var value = 1; value <= 5; value++)
              IconButton(
                tooltip: '$value stars',
                onPressed: () => setState(() => _rating = value),
                icon: Icon(
                  value <= _rating ? Icons.star : Icons.star_border,
                  color: _green,
                ),
              ),
          ],
        ),
        _field(_review, 'Write a review (optional)'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _rating == 0
            ? null
            : () {
                ref
                    .read(bookingsProvider.notifier)
                    .change(
                      widget.id,
                      (booking) => booking.update(
                        rating: _rating,
                        review: _review.text.trim(),
                      ),
                    );
                Navigator.pop(context);
              },
        child: const Text('Submit review'),
      ),
    ],
  );
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.id, required this.contractor});
  final int? id;
  final bool contractor;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref
        .watch(bookingsProvider)
        .where((item) => item.id == widget.id)
        .firstOrNull;
    if (booking == null) {
      return const MarketPage(
        title: 'Messages',
        children: [Text('Booking unavailable.')],
      );
    }
    void send() {
      final message = _message.text.trim();
      if (message.isEmpty) return;
      ref
          .read(bookingsProvider.notifier)
          .change(
            booking.id,
            (current) => current.update(
              messages: [
                ...current.messages,
                (contractor: widget.contractor, text: message),
              ],
            ),
          );
      _message.clear();
    }

    return MarketPage(
      title: 'Messages',
      children: [
        MarketBanner(
          booking.service.label,
          'Conversation for this booking',
          Icons.chat_bubble_outline,
        ),
        MarketCard(
          children: [
            if (booking.messages.isEmpty) const Text('No messages yet.'),
            for (final message in booking.messages)
              Align(
                alignment: message.contractor == widget.contractor
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _mint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${message.contractor ? 'Contractor' : 'Customer'}\n${message.text}',
                  ),
                ),
              ),
            TextField(
              controller: _message,
              onSubmitted: (_) => send(),
              decoration: InputDecoration(
                labelText: 'Message',
                suffixIcon: IconButton(
                  onPressed: send,
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.contractor = false});
  final bool contractor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.maybeWhen(
      authenticated: (user) => user,
      orElse: () => null,
    );
    return MarketPage(
      title: 'Profile & settings',
      nav: contractor ? null : 2,
      children: [
        MarketBanner(
          user?.name ?? 'Eden profile',
          contractor ? 'Contractor view' : 'Customer view',
          Icons.person_outline,
        ),
        MarketCard(
          children: [
            if (user != null) Text(user.email),
            if (!contractor)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_work_outlined),
                title: const Text('Manage properties'),
                onTap: () => context.push('/properties'),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                contractor ? 'Switch to customer' : 'Switch to contractor',
              ),
              onTap: () => context.go(
                contractor ? '/customer-home' : '/contractor-home',
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () async {
                try {
                  await ref.read(authProvider.notifier).logout();
                  if (!context.mounted) return;
                  ref.invalidate(bookingsProvider);
                  ref.invalidate(propertiesProvider);
                  context.go('/login');
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not log out. Please retry.'),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
