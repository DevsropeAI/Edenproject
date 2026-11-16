import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dark_theme.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/glass_controls.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../auth/providers/auth_provider.dart';
import '../../../auth/domain/auth_state.dart';
import '../../marketplace.dart';
import 'demo_settings_screen.dart';
import 'mode_switch_tile.dart';
import 'profile_tools.dart';
import 'account_extras_screen.dart';
import 'property_map.dart';
import 'booking_location.dart';

import 'package:latlong2/latlong.dart';

Future<void> signOut(BuildContext context, WidgetRef ref) async {
  try {
    await ref.read(authProvider.notifier).logout();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please retry.')),
      );
    }
  }
}

const _green = Color(0xFF164D36);
const _mint = Color(0xFFEAF5ED);
final _money = NumberFormat.simpleCurrency(name: 'CAD');
final _date = DateFormat('EEE, MMM d • h:mm a');

class CustomerNavigation extends StatelessWidget {
  const CustomerNavigation({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: EdenSpacing.content),
      child: GlassBottomNav(
        selectedIndex: index,
        onSelected: (selected) {
          if (selected == index) return;
          if (selected == 2) {
            context.push('/settings/support');
          } else {
            context.go(
              [
                '/customer-home',
                '/bookings',
                '/settings/support',
                '/profile',
              ][selected],
            );
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent),
            label: 'Support',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
}

class ContractorNavigation extends StatelessWidget {
  const ContractorNavigation({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: EdenSpacing.content),
      child: GlassBottomNav(
        selectedIndex: index,
        onSelected: (selected) {
          if (selected == index) return;
          context.go(['/contractor-home', '/settings/wallet', '/profile'][selected]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), label: 'Jobs'),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Earnings',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
}

Future<T?> showCustomerDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool? dark = true,
}) => showDialog<T>(
  context: context,
  builder: (context) => Consumer(
    builder: (context, ref, _) {
      final useDark = dark ?? _customerTheme(ref);
      return useDark
          ? Theme(
              data: EdenDarkTheme.data,
              child: Builder(builder: builder),
            )
          : builder(context);
    },
  ),
);

bool _customerTheme(WidgetRef ref) => ref
    .watch(authProvider)
    .maybeWhen(
      authenticated: (_) => true,
      orElse: () => false,
    );
EdenStatus _bookingStatus(JobStatus status) => switch (status) {
  JobStatus.searching => EdenStatus.pending,
  JobStatus.completed => EdenStatus.complete,
  JobStatus.enRoute || JobStatus.working => EdenStatus.live,
  _ => EdenStatus.neutral,
};

class MarketPage extends StatelessWidget {
  const MarketPage({
    super.key,
    required this.title,
    required this.children,
    this.nav,
    this.actions,
    this.dark = false,
    this.customerTheme = false,
    this.customerTab,
    this.showRibbon = false,
    this.darkNavigation,
  });
  final String title;
  final List<Widget> children;
  final int? nav;
  final List<Widget>? actions;
  final bool dark;
  final bool customerTheme;
  final int? customerTab;
  final bool showRibbon;
  final Widget? darkNavigation;

  Widget _darkPage(BuildContext context) => Theme(
    data: EdenDarkTheme.data,
    child: Scaffold(
      extendBody: true,
      appBar: AppBar(title: Text(title), actions: actions),
      bottomNavigationBar:
          darkNavigation ??
          (customerTab == null
              ? null
              : CustomerNavigation(index: customerTab!)),
      body: AppBackground(
        showRibbon: showRibbon,
        mainBackdrop: switch (customerTab ??
            (darkNavigation is CustomerNavigation
                ? (darkNavigation as CustomerNavigation).index
                : darkNavigation is ContractorNavigation
                ? const [0, 1, 3][(darkNavigation as ContractorNavigation).index]
                : null)) {
          0 => MainBackdrop.home,
          1 => MainBackdrop.orders,
          2 => MainBackdrop.support,
          3 => MainBackdrop.profile,
          _ => null,
        },
        child: SafeArea(
          bottom: darkNavigation == null && customerTab == null,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: EdenSpacing.content),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  EdenSpacing.screen,
                  EdenSpacing.screen,
                  EdenSpacing.screen,
                  darkNavigation == null && customerTab == null
                      ? EdenSpacing.screen
                      : MediaQuery.viewPaddingOf(context).bottom +
                            EdenSpacing.control * 2,
                ),
                children: [
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EdenSpacing.gap),
                      child: child,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => customerTheme
      ? Consumer(
          builder: (context, ref, _) =>
              _buildPage(context, _customerTheme(ref)),
        )
      : _buildPage(context, dark);

  Widget _buildPage(BuildContext context, bool useDark) => useDark
      ? _darkPage(context)
      : Scaffold(
          backgroundColor: const Color(0xFFF6F8F5),
          appBar: AppBar(title: Text(title), actions: actions),
          bottomNavigationBar: nav == null
              ? null
              : NavigationBar(
                  selectedIndex: nav!,
                  onDestinationSelected: (index) => context.go(
                    ['/customer-home', '/bookings', '/profile'][index],
                  ),
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
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 420 ? 16 : 24,
                ),
                children: [
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: child,
                    ),
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
  Widget build(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? GlassCard(
          blur: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: EdenSpacing.screen),
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: EdenSpacing.sm),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        )
      : Container(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 420 ? 18 : 26,
          ),
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
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
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

class MarketHeading extends StatelessWidget {
  const MarketHeading(this.label, {super.key, this.compact = false});
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Text(label, style: compact ? text.titleMedium : text.titleLarge);
  }
}

class MarketCard extends StatelessWidget {
  const MarketCard({super.key, required this.children, this.solid = false});
  final bool solid;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? GlassCard(
          solid: solid,
          child: SizedBox(width: double.infinity, child: _contents()),
        )
      : Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFDDE7DE)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            child: _contents(),
          ),
        );

  Widget _contents() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final child in children)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: EdenSpacing.xs),
          child: child,
        ),
    ],
  );
}

class PropertiesScreen extends ConsumerWidget {
  const PropertiesScreen({super.key, this.service});
  final Service? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);
    return MarketPage(
      dark: true,
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
            onPressed: () => showCustomerDialog<void>(
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
              MarketHeading(property.name),
              Text(property.address),
              Text(
                '${property.type} · ${property.size}${property.isDefault ? ' · Default' : ''}',
              ),
              if (property.photo case final photo?) DemoImage(photo),
              if (property.pin case final pin?)
                Text('Pin: ${pin.latitude}, ${pin.longitude}'),
              if (!property.isDefault)
                TextButton(
                  onPressed: () => ref
                      .read(propertiesProvider.notifier)
                      .setDefault(property.id),
                  child: const Text('Set as default'),
                ),
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
                    onPressed: () => showCustomerDialog<void>(
                      context: context,
                      builder: (_) => _PropertyEditor(property: property),
                    ),
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final remove = await showCustomerDialog<bool>(
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
  late String _type = widget.property?.type ?? 'House';
  late Uint8List? _photo = widget.property?.photo;
  late final _latitude = TextEditingController(
    text: widget.property?.pin?.latitude.toString(),
  );
  late final _longitude = TextEditingController(
    text: widget.property?.pin?.longitude.toString(),
  );

  String? _coordinate(
    String? value,
    double limit,
    TextEditingController other,
  ) {
    final text = value?.trim() ?? '';
    if (text.isEmpty && other.text.trim().isEmpty) return null;
    final number = double.tryParse(text);
    if (number == null || !number.isFinite || number.abs() > limit) {
      return 'Enter a valid coordinate';
    }
    return null;
  }

  late String _size = widget.property?.size ?? 'Standard';

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
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
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Property type'),
                items: [
                  for (final type in ['House', 'Apartment', 'Commercial'])
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              _field(_notes, 'Access instructions'),
              TextFormField(
                controller: _latitude,
                decoration: const InputDecoration(
                  labelText: 'Latitude (optional)',
                ),
                validator: (value) => _coordinate(value, 90, _longitude),
              ),
              TextFormField(
                controller: _longitude,
                decoration: const InputDecoration(
                  labelText: 'Longitude (optional)',
                ),
                validator: (value) => _coordinate(value, 180, _latitude),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: const Text('Choose pin on map'),
                onPressed: () async {
                  final lat = double.tryParse(_latitude.text);
                  final lng = double.tryParse(_longitude.text);
                  final valid =
                      lat != null &&
                      lng != null &&
                      lat.abs() <= 90 &&
                      lng.abs() <= 180;
                  final pin = await showCustomerDialog<LatLng>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Property location'),
                      content: SizedBox(
                        width: 560,
                        child: PropertyMap(
                          initial: valid
                              ? LatLng(lat, lng)
                              : const LatLng(43.6532, -79.3832),
                          editable: true,
                        ),
                      ),
                    ),
                  );
                  if (!mounted || pin == null) return;
                  _latitude.text = pin.latitude.toStringAsFixed(6);
                  _longitude.text = pin.longitude.toStringAsFixed(6);
                },
              ),
              if (_photo case final photo?) DemoImage(photo),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Choose property photo'),
                onPressed: () async {
                  final bytes = await selectDemoImage(context);
                  if (mounted && bytes != null) setState(() => _photo = bytes);
                },
              ),
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
        onPressed: () async {
          if (!_form.currentState!.validate()) return;
          final saved = await ref
              .read(propertiesProvider.notifier)
              .save(
                widget.property?.id,
                _name.text.trim(),
                _address.text.trim(),
                _size,
                _notes.text.trim(),
                type: _type,
                photo: _photo,
                pin: _latitude.text.trim().isEmpty
                    ? null
                    : (
                        latitude: double.parse(_latitude.text.trim()),
                        longitude: double.parse(_longitude.text.trim()),
                      ),
              );
          if (saved && context.mounted) Navigator.pop(context);
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
  bool _walkway = false;
  Uint8List? _referencePhoto;
  final _coupon = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      builder: (_, child) => Theme(data: EdenDarkTheme.data, child: child!),
      context: context,
      initialDate: _scheduled ?? now,
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      builder: (_, child) => Theme(data: EdenDarkTheme.data, child: child!),
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
        dark: true,
        title: 'Book a service',
        children: [Text('Property unavailable.')],
      );
    }
    final catalog = ref.watch(serviceCatalogProvider);
    final options = catalog.value ?? const <Service, int>{};
    if (options.isEmpty) {
      return MarketPage(
        dark: true,
        title: 'Book a service',
        children: [
          if (catalog.isLoading)
            const LinearProgressIndicator()
          else
            TextButton(
              onPressed: () => ref.invalidate(serviceCatalogProvider),
              child: const Text('Reload available services'),
            ),
        ],
      );
    }
    final service = options.containsKey(_service)
        ? _service
        : options.keys.first;
    final base = options[service]! / 100 + (property.size == 'Large' ? 15 : 0);
    final rushFee = _urgent ? 20 : 0;
    final walkwayFee = service == Service.snow && _walkway ? 12 : 0;
    final subtotal = base + rushFee + walkwayFee;
    final discount = _coupon.text.trim().toUpperCase() == 'EDEN10'
        ? (subtotal * 10).round() / 100
        : 0;
    final tax = ((subtotal - discount) * 13).round() / 100;
    final total = subtotal - discount + tax;
    return MarketPage(
      dark: true,
      title: 'Book a service',
      children: [
        MarketBanner(
          property.name,
          property.address,
          Icons.event_available_outlined,
        ),
        MarketCard(
          solid: true,
          children: [
            DropdownButtonFormField<Service>(
              initialValue: service,
              decoration: const InputDecoration(labelText: 'Service'),
              items: [
                for (final service in options.keys)
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
            if (service == Service.snow)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add walkway clearing · CAD 12'),
                value: _walkway,
                onChanged: (value) => setState(() => _walkway = value ?? false),
              ),
            TextField(
              controller: _coupon,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Promo code',
                helperText: 'Demo code: EDEN10',
                errorText: _coupon.text.trim().isNotEmpty && discount == 0
                    ? 'Code is not recognized'
                    : null,
              ),
            ),
            _field(_notes, 'Instructions for the contractor'),
            if (_referencePhoto case final photo?) DemoImage(photo),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Choose reference photo'),
              onPressed: () async {
                final bytes = await selectDemoImage(context);
                if (mounted && bytes != null) {
                  setState(() => _referencePhoto = bytes);
                }
              },
            ),
          ],
        ),
        MarketCard(
          solid: true,
          children: [
            MarketHeading('Instant quote'),
            Text('Service  ${_money.format(base)}'),
            if (_urgent) Text('Urgent fee  ${_money.format(rushFee)}'),
            if (walkwayFee > 0)
              Text('Walkway clearing  ${_money.format(walkwayFee)}'),
            if (discount > 0)
              Text('Promo discount  -${_money.format(discount)}'),
            Text('Estimated tax  ${_money.format(tax)}'),
            const Divider(),
            MarketHeading('Total  ${_money.format(total)} CAD'),
            const Text('Payment is available after the booking is completed.'),
            FilledButton(
              onPressed: _scheduled == null
                  ? null
                  : () async {
                      if (!_scheduled!.isAfter(DateTime.now())) {
                        setState(() => _scheduled = null);
                        return;
                      }
                      final confirmed = await showCustomerDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Review checkout'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(service.label),
                              Text(property.address),
                              Text(_date.format(_scheduled!)),
                              const Divider(),
                              Text('Total: ${_money.format(total)} CAD'),
                              const Text('No charge will be made.'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: const Text('Back'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: const Text('Place booking'),
                            ),
                          ],
                        ),
                      );
                      if (!context.mounted || confirmed != true) return;
                      if (!_scheduled!.isAfter(DateTime.now())) {
                        setState(() => _scheduled = null);
                        return;
                      }
                      final placed = await ref
                          .read(bookingsProvider.notifier)
                          .place(
                            property,
                            service,
                            _scheduled!,
                            [
                              if (walkwayFee > 0) 'Includes walkway clearing.',
                              if (_notes.text.trim().isNotEmpty)
                                _notes.text.trim(),
                            ].join(' '),
                            _recurring,
                            referencePhoto: _referencePhoto,
                            urgent: _urgent,
                            walkway: _walkway,
                            discount: discount > 0,
                          );
                      if (placed && context.mounted) context.go('/bookings');
                    },
              child: const Text('Continue to checkout'),
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
    final available = ref.watch(demoSettingsProvider).available;
    final area = ref.watch(registrationDetailsProvider).area;
    final visible = bookings.where(
      (booking) =>
          !contractor ||
          (!booking.declined &&
              (booking.status != JobStatus.searching || available)),
    );
    return MarketPage(
      title: contractor ? 'Eden Contractor' : 'My bookings',
      nav: contractor ? null : 1,
      dark: true,
      darkNavigation: contractor
          ? const ContractorNavigation(index: 0)
          : const CustomerNavigation(index: 1),
      children: [
        if (contractor)
          _ContractorHeader(
            available: available,
            onAvailableChanged: (value) => ref
                .read(demoSettingsProvider.notifier)
                .update(available: value),
            open: visible
                .where((job) => job.status == JobStatus.searching)
                .length,
            active: visible
                .where(
                  (job) =>
                      job.status != JobStatus.searching &&
                      job.status != JobStatus.completed &&
                      job.status != JobStatus.cancelled,
                )
                .length,
            done: visible
                .where((job) => job.status == JobStatus.completed)
                .length,
          )
        else
          const MarketBanner(
            'Your bookings',
            'Follow service progress and review finished work.',
            Icons.receipt_long_outlined,
          ),
        if (visible.isEmpty)
          if (contractor)
            EmptyState(
              icon: Icons.inbox_outlined,
              message: available
                  ? 'No jobs to show right now. New requests will appear here.'
                  : 'You are offline. Turn on availability to see new jobs.',
              action: TextButton(
                onPressed: () => ref.read(bookingsProvider.notifier).refresh(),
                child: const Text('Refresh'),
              ),
            )
          else
            EmptyState(
              icon: Icons.receipt_long_outlined,
              message: 'Your orders will appear here after you book a service.',
              action: TextButton(
                onPressed: () => context.go('/customer-home'),
                child: const Text('Browse services'),
              ),
            ),
        for (final (title, statuses)
            in (contractor
                ? [
                    ('Available jobs', [JobStatus.searching]),
                    (
                      'Active jobs',
                      [
                        JobStatus.accepted,
                        JobStatus.enRoute,
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
                        (status) =>
                            status != JobStatus.completed &&
                            status != JobStatus.cancelled,
                      ),
                    ),
                    (
                      'Past bookings',
                      [JobStatus.completed, JobStatus.cancelled],
                    ),
                  ]))
          if (visible.any((booking) => statuses.contains(booking.status))) ...[
            MarketHeading(title),
            for (final booking in visible.where(
              (booking) => statuses.contains(booking.status),
            ))
              if (contractor)
                _JobCard(booking: booking)
              else
              MarketCard(
                children: [
                  MarketHeading(booking.service.label, compact: true),
                  Text(booking.property.address),
                  Text(
                    '${_date.format(booking.date)} · ${_money.format(booking.total)} CAD',
                  ),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(
                        label: booking.status.label,
                        status: _bookingStatus(booking.status),
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
        if (contractor) ...[
          const _ContractorShortcuts(),
          MarketCard(
            children: [ModeSwitchTile(contractor: true, area: area)],
          ),
        ],
      ],
    );
  }
}

class _ContractorHeader extends StatelessWidget {
  const _ContractorHeader({
    required this.available,
    required this.onAvailableChanged,
    required this.open,
    required this.active,
    required this.done,
  });
  final bool available;
  final ValueChanged<bool> onAvailableChanged;
  final int open;
  final int active;
  final int done;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          blur: true,
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: available
                    ? EdenDarkColors.accent
                    : EdenDarkColors.glass,
                child: const Icon(Icons.handyman_outlined),
              ),
              const SizedBox(width: EdenSpacing.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      available ? 'Available for jobs' : 'Offline',
                      style: text.titleLarge?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: EdenSpacing.xs),
                    Text(
                      available
                          ? 'Find new work and manage your accepted jobs.'
                          : 'Turn on to see new job requests.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(value: available, onChanged: onAvailableChanged),
            ],
          ),
        ),
        const SizedBox(height: EdenSpacing.gap),
        Row(
          children: [
            Expanded(child: _StatTile('Available', open)),
            const SizedBox(width: EdenSpacing.gap),
            Expanded(child: _StatTile('Active', active)),
            const SizedBox(width: EdenSpacing.gap),
            Expanded(child: _StatTile('Completed', done)),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      vertical: EdenSpacing.screen,
      horizontal: EdenSpacing.gap,
    ),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [EdenDarkColors.glassTop, EdenDarkColors.glassBottom],
      ),
      border: Border.all(color: EdenDarkColors.strongGlass),
      borderRadius: BorderRadius.circular(EdenRadius.field),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$count', style: EdenTypography.amount),
        const SizedBox(height: EdenSpacing.xs),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _ContractorShortcuts extends StatelessWidget {
  const _ContractorShortcuts();

  static const _items = [
    (Icons.verified_user_outlined, 'Verification', '/verification'),
    (Icons.schedule, 'Hours & radius', '/account/schedule'),
    (Icons.star_outline, 'Reviews', '/account/reviews'),
    (Icons.support_agent, 'Help & support', '/settings/support'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - EdenSpacing.gap) / 2;
      return Wrap(
        spacing: EdenSpacing.gap,
        runSpacing: EdenSpacing.gap,
        children: [
          for (final (icon, label, path) in _items)
            SizedBox(
              width: width,
              child: GlassCard(
                child: InkWell(
                  onTap: () => context.push(path),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon),
                      const SizedBox(height: EdenSpacing.gap),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(EdenRadius.field),
        onTap: () => context.push('/job-details/${booking.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.service.label,
                    style: text.titleLarge?.copyWith(fontSize: 18),
                  ),
                ),
                Text(
                  _money.format(booking.total),
                  style: EdenTypography.amount.copyWith(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: EdenSpacing.gap),
            _JobLine(Icons.location_on_outlined, booking.property.address),
            const SizedBox(height: EdenSpacing.sm),
            _JobLine(Icons.schedule, _date.format(booking.date)),
            const SizedBox(height: EdenSpacing.gap),
            Wrap(
              spacing: EdenSpacing.gap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  label: booking.status.label,
                  status: _bookingStatus(booking.status),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/job-details/${booking.id}'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('View details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JobLine extends StatelessWidget {
  const _JobLine(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: EdenDarkColors.secondary),
      const SizedBox(width: EdenSpacing.sm),
      Expanded(
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ],
  );
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
      if (bytes.length > 2 * 1024 * 1024) {
        throw StateError('Photo exceeds 2 MB');
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
            content: Text('Could not open photo. Try an image under 2 MB.'),
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
      return MarketPage(
        title: 'Booking details',
        dark: true,
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
      dark: true,
      actions: [
        TextButton(
          onPressed: () =>
              context.go(contractor ? '/contractor-home' : '/bookings'),
          child: Text(contractor ? 'All jobs' : 'All bookings'),
        ),
      ],
      children: [
        MarketBanner(
          booking.service.label,
          booking.property.address,
          Icons.assignment_outlined,
        ),
        MarketCard(
          children: [
            StatusChip(
              label: booking.status.label,
              status: _bookingStatus(booking.status),
            ),
            Text(_date.format(booking.date)),
            Text('${_money.format(booking.total)} CAD'),
            if (booking.recurring) const Text('Weekly service requested'),
            if (booking.property.pin case final pin?)
              OutlinedButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: const Text('View property on map'),
                onPressed: () => showCustomerDialog<void>(
                  dark: true,
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(booking.property.name),
                    content: SizedBox(
                      width: 560,
                      child: PropertyMap(
                        initial: LatLng(pin.latitude, pin.longitude),
                      ),
                    ),
                  ),
                ),
              ),
            if (booking.property.notes.isNotEmpty) Text(booking.property.notes),
            if (booking.notes.isNotEmpty) Text(booking.notes),
            if (booking.status != JobStatus.searching &&
                booking.status != JobStatus.cancelled)
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/chat/${booking.id}', extra: contractor),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Messages'),
              ),
          ],
        ),
        if (!contractor && booking.status == JobStatus.enRoute)
          MarketCard(
            children: [
              const Text('Your contractor is on the way'),
              CustomerTrackingMap(
                key: ValueKey(booking.id),
                bookingId: booking.id,
              ),
            ],
          ),
        if (!contractor && booking.status == JobStatus.completed)
          MarketCard(
            children: [
              MarketHeading('Booking summary'),
              Text('Booking #${booking.id} · ${booking.service.label}'),
              Text('Quoted total: ${_money.format(booking.total)} CAD'),
              TextButton(
                onPressed: () => context.push('/account/payments'),
                child: const Text('Payments & refunds'),
              ),
            ],
          ),
        if (booking.referencePhoto case final photo?)
          MarketCard(
            children: [const Text('Booking reference photo'), DemoImage(photo)],
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
              MarketHeading('Work photos'),
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
              if (contractor &&
                  booking.status == JobStatus.arrived &&
                  booking.before == null)
                const Text('Add a before photo to start work.'),
              if (contractor &&
                  booking.status == JobStatus.working &&
                  booking.after == null)
                const Text('Add an after photo to submit the job.'),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ref.watch(contractorVerificationProvider).value ==
                    'Approved')
                  SlideToConfirm(
                    label: 'Accept job',
                    onConfirm: () => advance(JobStatus.accepted),
                  )
                else
                  FilledButton(
                    onPressed: () async {
                      ref.invalidate(contractorVerificationProvider);
                      await context.push('/verification');
                      if (context.mounted)
                        ref.invalidate(contractorVerificationProvider);
                    },
                    child: const Text('Open verification'),
                  ),
                const SizedBox(height: EdenSpacing.gap),
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
            SlideToConfirm(
              label: 'Mark on the way',
              icon: Icons.directions_car_outlined,
              onConfirm: () => advance(JobStatus.enRoute),
            ),
          if (booking.status == JobStatus.enRoute)
            MarketCard(
              children: [
                ContractorLocationSharing(
                  key: ValueKey(booking.id),
                  bookingId: booking.id,
                ),
              ],
            ),
          if (booking.status == JobStatus.enRoute)
            SlideToConfirm(
              label: 'Mark arrived',
              icon: Icons.place_outlined,
              onConfirm: () => advance(JobStatus.arrived),
            ),
          if (booking.status == JobStatus.arrived)
            SlideToConfirm(
              label: 'Start work',
              icon: Icons.play_arrow,
              onConfirm: booking.before == null
                  ? null
                  : () => advance(JobStatus.working),
            ),
          if (booking.status == JobStatus.working)
            SlideToConfirm(
              label: 'Submit completed work',
              onConfirm: booking.after == null
                  ? null
                  : () => advance(JobStatus.submitted),
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
                          image: null,
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
            onPressed: () => showCustomerDialog<void>(
              dark: true,
              context: context,
              builder: (_) => _ReviewDialog(id: booking.id),
            ),
            child: const Text('Rate the service'),
          ),
        MarketCard(
          children: [
            MarketHeading('Service progress'),
            if (!contractor && booking.status == JobStatus.cancelled)
              const StatusChip(label: 'Cancelled')
            else
              StatusStepper(
                labels: JobStatus.values.map((status) => status.label).toList(),
                current: booking.status.index,
              ),
          ],
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
                  color: Theme.of(context).colorScheme.primary,
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
      return MarketPage(
        title: 'Messages',
        dark: true,
        children: [Text('Booking unavailable.')],
      );
    }
    Future<void> send([Uint8List? image]) async {
      final message = _message.text.trim();
      if (message.isEmpty && image == null) return;
      final sent = await ref
          .read(bookingsProvider.notifier)
          .change(
            booking.id,
            (current) => current.update(
              messages: [
                ...current.messages,
                (contractor: widget.contractor, text: message, image: image),
              ],
            ),
          );
      if (sent && mounted && _message.text.trim() == message) _message.clear();
    }

    return MarketPage(
      title: 'Messages',
      dark: true,
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
                    color:
                        widget.contractor &&
                            message.contractor == widget.contractor
                        ? EdenDarkColors.accent.withValues(alpha: .35)
                        : EdenDarkColors.strongGlass,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${message.contractor ? 'Contractor' : 'Customer'}\n${message.text}',
                      ),
                      if (message.image case final image?) DemoImage(image),
                    ],
                  ),
                ),
              ),
            TextField(
              controller: _message,
              onSubmitted: (_) => send(),
              decoration: InputDecoration(
                labelText: 'Message',
                prefixIcon: IconButton(
                  tooltip: 'Attach photo',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () async {
                    final bytes = await selectDemoImage(context);
                    if (mounted && bytes != null) send(bytes);
                  },
                ),
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
    final registration = ref.watch(registrationDetailsProvider);
    final user = auth.maybeWhen(
      authenticated: (user) => user,
      orElse: () => null,
    );
    return MarketPage(
      title: 'Profile & settings',
      dark: true,
      darkNavigation: contractor
          ? const ContractorNavigation(index: 2)
          : const CustomerNavigation(index: 3),
      nav: contractor ? null : 2,
      children: [
        MarketBanner(
          user?.name ?? 'Eden profile',
          contractor ? 'Contractor view' : 'Customer view',
          Icons.person_outline,
        ),
        MarketCard(
          children: [
            if (user != null) ...[
              if (ref.watch(accountImageProvider('profile')).value
                  case final photo?)
                CircleAvatar(radius: 28, backgroundImage: MemoryImage(photo)),
              Text(user.email),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit profile'),
                onTap: () => context.push('/profile/edit'),
              ),
            ],
            if (contractor)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Verification documents'),
                onTap: () => context.push('/verification'),
              ),
            if (registration.phone.isNotEmpty) Text(registration.phone),
            if (contractor && registration.area.isNotEmpty)
              Text(registration.area),
            if (contractor && registration.service.isNotEmpty)
              Text(registration.service),
            if (!contractor) const Divider(),
            if (!contractor)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Orders & activity'),
              ),
            if (contractor)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Integration previews'),
                onTap: () => context.push('/integration-demo'),
              ),
            for (final section in [
              AccountSection.reviews,
              if (contractor) AccountSection.schedule,
              if (!contractor) AccountSection.payments,
              if (!contractor) AccountSection.recurring,
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(section.icon),
                title: Text(section.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/account/${section.name}'),
              ),
            if (!contractor) const Divider(),
            if (!contractor)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Preferences & help'),
              ),
            for (final section in [
              SettingsSection.support,
              SettingsSection.preferences,
              if (contractor) SettingsSection.wallet,
              if (contractor) SettingsSection.verification,
              if (!contractor) SettingsSection.automatic,
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(section.icon),
                title: Text(section.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/${section.name}'),
              ),
            if (!contractor)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_work_outlined),
                title: const Text('Manage properties'),
                onTap: () => context.push('/properties'),
              ),
            if (!contractor)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('Integration previews'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/integration-demo'),
              ),
            if (!contractor) const Divider(),
            ModeSwitchTile(contractor: contractor, area: registration.area),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => signOut(context, ref),
            ),
          ],
        ),
      ],
    );
  }
}



// import '../../../../core/theme/app_colors.dart';
// import '../../../../core/theme/app_dark_theme.dart';
// import '../../../../core/theme/app_spacing.dart';
// import '../../../../core/widgets/app_background.dart';
// import '../../../../core/widgets/glass_controls.dart';

// import 'dart:typed_data';

// import 'package:flutter/material.dart';

// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:intl/intl.dart';

// import '../../../auth/providers/auth_provider.dart';
// import '../../../auth/domain/auth_state.dart';
// import '../../marketplace.dart';
// import 'demo_settings_screen.dart';
// import 'mode_switch_tile.dart';
// import 'profile_tools.dart';
// import 'account_extras_screen.dart';
// import 'property_map.dart';
// import 'booking_location.dart';

// import 'package:latlong2/latlong.dart';

// Future<void> signOut(BuildContext context, WidgetRef ref) async {
//   try {
//     await ref.read(authProvider.notifier).logout();
//   } catch (_) {
//     if (context.mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Could not log out. Please retry.')),
//       );
//     }
//   }
// }

// const _green = Color(0xFF164D36);
// const _mint = Color(0xFFEAF5ED);
// final _money = NumberFormat.simpleCurrency(name: 'CAD');
// final _date = DateFormat('EEE, MMM d • h:mm a');

// class CustomerNavigation extends StatelessWidget {
//   const CustomerNavigation({super.key, required this.index});
//   final int index;

//   @override
//   Widget build(BuildContext context) => Center(
//     heightFactor: 1,
//     child: ConstrainedBox(
//       constraints: const BoxConstraints(maxWidth: EdenSpacing.content),
//       child: GlassBottomNav(
//         selectedIndex: index,
//         onSelected: (selected) {
//           if (selected == index) return;
//           if (selected == 2) {
//             context.push('/settings/support');
//           } else {
//             context.go(
//               [
//                 '/customer-home',
//                 '/bookings',
//                 '/settings/support',
//                 '/profile',
//               ][selected],
//             );
//           }
//         },
//         destinations: const [
//           NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
//           NavigationDestination(
//             icon: Icon(Icons.receipt_long_outlined),
//             label: 'Orders',
//           ),
//           NavigationDestination(
//             icon: Icon(Icons.support_agent),
//             label: 'Support',
//           ),
//           NavigationDestination(
//             icon: Icon(Icons.person_outline),
//             label: 'Profile',
//           ),
//         ],
//       ),
//     ),
//   );
// }

// Future<T?> showCustomerDialog<T>({
//   required BuildContext context,
//   required WidgetBuilder builder,
//   bool? dark = true,
// }) => showDialog<T>(
//   context: context,
//   builder: (context) => Consumer(
//     builder: (context, ref, _) {
//       final useDark = dark ?? _customerTheme(ref);
//       return useDark
//           ? Theme(
//               data: EdenDarkTheme.data,
//               child: Builder(builder: builder),
//             )
//           : builder(context);
//     },
//   ),
// );

// bool _customerTheme(WidgetRef ref) => ref
//     .watch(authProvider)
//     .maybeWhen(
//       authenticated: (user) => user.role == 'customer',
//       orElse: () => false,
//     );
// EdenStatus _bookingStatus(JobStatus status) => switch (status) {
//   JobStatus.searching => EdenStatus.pending,
//   JobStatus.completed => EdenStatus.complete,
//   JobStatus.enRoute || JobStatus.working => EdenStatus.live,
//   _ => EdenStatus.neutral,
// };

// class MarketPage extends StatelessWidget {
//   const MarketPage({
//     super.key,
//     required this.title,
//     required this.children,
//     this.nav,
//     this.actions,
//     this.dark = false,
//     this.customerTheme = false,
//     this.customerTab,
//     this.showRibbon = false,
//     this.darkNavigation,
//   });
//   final String title;
//   final List<Widget> children;
//   final int? nav;
//   final List<Widget>? actions;
//   final bool dark;
//   final bool customerTheme;
//   final int? customerTab;
//   final bool showRibbon;
//   final Widget? darkNavigation;

//   Widget _darkPage(BuildContext context) => Theme(
//     data: EdenDarkTheme.data,
//     child: Scaffold(
//       extendBody: true,
//       appBar: AppBar(title: Text(title), actions: actions),
//       bottomNavigationBar:
//           darkNavigation ??
//           (customerTab == null
//               ? null
//               : CustomerNavigation(index: customerTab!)),
//       body: AppBackground(
//         showRibbon: showRibbon,
//         mainBackdrop: switch (customerTab ??
//             (darkNavigation is CustomerNavigation
//                 ? (darkNavigation as CustomerNavigation).index
//                 : null)) {
//           0 => MainBackdrop.home,
//           1 => MainBackdrop.orders,
//           2 => MainBackdrop.support,
//           3 => MainBackdrop.profile,
//           _ => null,
//         },
//         child: SafeArea(
//           bottom: darkNavigation == null && customerTab == null,
//           child: Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: EdenSpacing.content),
//               child: ListView(
//                 padding: EdgeInsets.fromLTRB(
//                   EdenSpacing.screen,
//                   EdenSpacing.screen,
//                   EdenSpacing.screen,
//                   darkNavigation == null && customerTab == null
//                       ? EdenSpacing.screen
//                       : MediaQuery.viewPaddingOf(context).bottom +
//                             EdenSpacing.control * 2,
//                 ),
//                 children: [
//                   for (final child in children)
//                     Padding(
//                       padding: const EdgeInsets.only(bottom: EdenSpacing.gap),
//                       child: child,
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         ),
//       ),
//     ),
//   );

//   @override
//   Widget build(BuildContext context) => customerTheme
//       ? Consumer(
//           builder: (context, ref, _) =>
//               _buildPage(context, _customerTheme(ref)),
//         )
//       : _buildPage(context, dark);

//   Widget _buildPage(BuildContext context, bool useDark) => useDark
//       ? _darkPage(context)
//       : Scaffold(
//           backgroundColor: const Color(0xFFF6F8F5),
//           appBar: AppBar(title: Text(title), actions: actions),
//           bottomNavigationBar: nav == null
//               ? null
//               : NavigationBar(
//                   selectedIndex: nav!,
//                   onDestinationSelected: (index) => context.go(
//                     ['/customer-home', '/bookings', '/profile'][index],
//                   ),
//                   destinations: const [
//                     NavigationDestination(
//                       icon: Icon(Icons.home_outlined),
//                       label: 'Home',
//                     ),
//                     NavigationDestination(
//                       icon: Icon(Icons.calendar_today_outlined),
//                       label: 'Bookings',
//                     ),
//                     NavigationDestination(
//                       icon: Icon(Icons.person_outline),
//                       label: 'Profile',
//                     ),
//                   ],
//                 ),
//           body: Center(
//             child: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 820),
//               child: ListView(
//                 padding: EdgeInsets.all(
//                   MediaQuery.sizeOf(context).width < 420 ? 16 : 24,
//                 ),
//                 children: [
//                   for (final child in children)
//                     Padding(
//                       padding: const EdgeInsets.only(bottom: 16),
//                       child: child,
//                     ),
//                 ],
//               ),
//             ),
//           ),
//         );
// }

// class MarketBanner extends StatelessWidget {
//   const MarketBanner(this.title, this.subtitle, this.icon, {super.key});
//   final String title;
//   final String subtitle;
//   final IconData icon;

//   @override
//   Widget build(BuildContext context) =>
//       Theme.of(context).brightness == Brightness.dark
//       ? GlassCard(
//           blur: true,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Icon(icon),
//               const SizedBox(height: EdenSpacing.screen),
//               Text(title, style: Theme.of(context).textTheme.headlineLarge),
//               const SizedBox(height: EdenSpacing.sm),
//               Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
//             ],
//           ),
//         )
//       : Container(
//           padding: EdgeInsets.all(
//             MediaQuery.sizeOf(context).width < 420 ? 18 : 26,
//           ),
//           decoration: BoxDecoration(
//             gradient: const LinearGradient(colors: [_green, Color(0xFF317754)]),
//             borderRadius: BorderRadius.circular(24),
//           ),
//           child: Row(
//             children: [
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       title,
//                       style: Theme.of(context).textTheme.headlineMedium
//                           ?.copyWith(
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold,
//                           ),
//                     ),
//                     const SizedBox(height: 8),
//                     Text(subtitle, style: const TextStyle(color: Colors.white)),
//                   ],
//                 ),
//               ),
//               const SizedBox(width: 16),
//               Icon(icon, color: const Color(0xFFC1E9CE), size: 42),
//             ],
//           ),
//         );
// }

// class MarketHeading extends StatelessWidget {
//   const MarketHeading(this.label, {super.key, this.compact = false});
//   final String label;
//   final bool compact;

//   @override
//   Widget build(BuildContext context) {
//     final text = Theme.of(context).textTheme;
//     return Text(label, style: compact ? text.titleMedium : text.titleLarge);
//   }
// }

// class MarketCard extends StatelessWidget {
//   const MarketCard({super.key, required this.children, this.solid = false});
//   final bool solid;
//   final List<Widget> children;

//   @override
//   Widget build(BuildContext context) =>
//       Theme.of(context).brightness == Brightness.dark
//       ? GlassCard(
//           solid: solid,
//           child: SizedBox(width: double.infinity, child: _contents()),
//         )
//       : Material(
//           color: Colors.white,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20),
//             side: const BorderSide(color: Color(0xFFDDE7DE)),
//           ),
//           clipBehavior: Clip.antiAlias,
//           child: Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(20),
//             child: _contents(),
//           ),
//         );

//   Widget _contents() => Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       for (final child in children)
//         Padding(
//           padding: const EdgeInsets.symmetric(vertical: EdenSpacing.xs),
//           child: child,
//         ),
//     ],
//   );
// }

// class PropertiesScreen extends ConsumerWidget {
//   const PropertiesScreen({super.key, this.service});
//   final Service? service;

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final properties = ref.watch(propertiesProvider);
//     return MarketPage(
//       dark: true,
//       title: 'Properties',
//       children: [
//         const MarketBanner(
//           'Your places',
//           'Choose where you need a service, or add another property.',
//           Icons.home_work_outlined,
//         ),
//         Align(
//           alignment: Alignment.centerLeft,
//           child: FilledButton.icon(
//             onPressed: () => showCustomerDialog<void>(
//               context: context,
//               builder: (_) => const _PropertyEditor(),
//             ),
//             icon: const Icon(Icons.add),
//             label: const Text('Add property'),
//           ),
//         ),
//         if (properties.isEmpty)
//           const MarketCard(
//             children: [Text('Add a property to start a booking.')],
//           ),
//         for (final property in properties)
//           MarketCard(
//             children: [
//               MarketHeading(property.name),
//               Text(property.address),
//               Text(
//                 '${property.type} · ${property.size}${property.isDefault ? ' · Default' : ''}',
//               ),
//               if (property.photo case final photo?) DemoImage(photo),
//               if (property.pin case final pin?)
//                 Text('Pin: ${pin.latitude}, ${pin.longitude}'),
//               if (!property.isDefault)
//                 TextButton(
//                   onPressed: () => ref
//                       .read(propertiesProvider.notifier)
//                       .setDefault(property.id),
//                   child: const Text('Set as default'),
//                 ),
//               if (property.notes.isNotEmpty) Text(property.notes),
//               Wrap(
//                 spacing: 8,
//                 runSpacing: 8,
//                 children: [
//                   FilledButton(
//                     onPressed: () =>
//                         context.push('/booking/${property.id}', extra: service),
//                     child: const Text('Book a service'),
//                   ),
//                   OutlinedButton(
//                     onPressed: () => showCustomerDialog<void>(
//                       context: context,
//                       builder: (_) => _PropertyEditor(property: property),
//                     ),
//                     child: const Text('Edit'),
//                   ),
//                   TextButton(
//                     onPressed: () async {
//                       final remove = await showCustomerDialog<bool>(
//                         context: context,
//                         builder: (dialogContext) => AlertDialog(
//                           title: Text('Remove ${property.name}?'),
//                           actions: [
//                             TextButton(
//                               onPressed: () => Navigator.pop(dialogContext),
//                               child: const Text('Cancel'),
//                             ),
//                             FilledButton(
//                               onPressed: () =>
//                                   Navigator.pop(dialogContext, true),
//                               child: const Text('Remove'),
//                             ),
//                           ],
//                         ),
//                       );
//                       if (context.mounted && remove == true) {
//                         ref
//                             .read(propertiesProvider.notifier)
//                             .remove(property.id);
//                       }
//                     },
//                     child: const Text('Remove'),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//       ],
//     );
//   }
// }

// class _PropertyEditor extends ConsumerStatefulWidget {
//   const _PropertyEditor({this.property});
//   final Property? property;

//   @override
//   ConsumerState<_PropertyEditor> createState() => _PropertyEditorState();
// }

// class _PropertyEditorState extends ConsumerState<_PropertyEditor> {
//   final _form = GlobalKey<FormState>();
//   late final _name = TextEditingController(text: widget.property?.name);
//   late final _address = TextEditingController(text: widget.property?.address);
//   late final _notes = TextEditingController(text: widget.property?.notes);
//   late String _type = widget.property?.type ?? 'House';
//   late Uint8List? _photo = widget.property?.photo;
//   late final _latitude = TextEditingController(
//     text: widget.property?.pin?.latitude.toString(),
//   );
//   late final _longitude = TextEditingController(
//     text: widget.property?.pin?.longitude.toString(),
//   );

//   String? _coordinate(
//     String? value,
//     double limit,
//     TextEditingController other,
//   ) {
//     final text = value?.trim() ?? '';
//     if (text.isEmpty && other.text.trim().isEmpty) return null;
//     final number = double.tryParse(text);
//     if (number == null || !number.isFinite || number.abs() > limit) {
//       return 'Enter a valid coordinate';
//     }
//     return null;
//   }

//   late String _size = widget.property?.size ?? 'Standard';

//   @override
//   void dispose() {
//     _name.dispose();
//     _address.dispose();
//     _latitude.dispose();
//     _longitude.dispose();
//     _notes.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) => AlertDialog(
//     title: Text(widget.property == null ? 'Add property' : 'Edit property'),
//     content: SizedBox(
//       width: 420,
//       child: Form(
//         key: _form,
//         child: SingleChildScrollView(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               _field(_name, 'Property name', required: true),
//               _field(
//                 _address,
//                 'Street address, city and postal code',
//                 required: true,
//               ),
//               DropdownButtonFormField<String>(
//                 initialValue: _size,
//                 decoration: const InputDecoration(labelText: 'Property size'),
//                 items: [
//                   for (final size in ['Small', 'Standard', 'Large'])
//                     DropdownMenuItem(value: size, child: Text(size)),
//                 ],
//                 onChanged: (size) => setState(() => _size = size!),
//               ),
//               DropdownButtonFormField<String>(
//                 initialValue: _type,
//                 decoration: const InputDecoration(labelText: 'Property type'),
//                 items: [
//                   for (final type in ['House', 'Apartment', 'Commercial'])
//                     DropdownMenuItem(value: type, child: Text(type)),
//                 ],
//                 onChanged: (value) => setState(() => _type = value!),
//               ),
//               _field(_notes, 'Access instructions'),
//               TextFormField(
//                 controller: _latitude,
//                 decoration: const InputDecoration(
//                   labelText: 'Latitude (optional)',
//                 ),
//                 validator: (value) => _coordinate(value, 90, _longitude),
//               ),
//               TextFormField(
//                 controller: _longitude,
//                 decoration: const InputDecoration(
//                   labelText: 'Longitude (optional)',
//                 ),
//                 validator: (value) => _coordinate(value, 180, _latitude),
//               ),
//               OutlinedButton.icon(
//                 icon: const Icon(Icons.map_outlined),
//                 label: const Text('Choose pin on map'),
//                 onPressed: () async {
//                   final lat = double.tryParse(_latitude.text);
//                   final lng = double.tryParse(_longitude.text);
//                   final valid =
//                       lat != null &&
//                       lng != null &&
//                       lat.abs() <= 90 &&
//                       lng.abs() <= 180;
//                   final pin = await showCustomerDialog<LatLng>(
//                     context: context,
//                     builder: (_) => AlertDialog(
//                       title: const Text('Property location'),
//                       content: SizedBox(
//                         width: 560,
//                         child: PropertyMap(
//                           initial: valid
//                               ? LatLng(lat, lng)
//                               : const LatLng(43.6532, -79.3832),
//                           editable: true,
//                         ),
//                       ),
//                     ),
//                   );
//                   if (!mounted || pin == null) return;
//                   _latitude.text = pin.latitude.toStringAsFixed(6);
//                   _longitude.text = pin.longitude.toStringAsFixed(6);
//                 },
//               ),
//               if (_photo case final photo?) DemoImage(photo),
//               OutlinedButton.icon(
//                 icon: const Icon(Icons.add_a_photo_outlined),
//                 label: const Text('Choose property photo'),
//                 onPressed: () async {
//                   final bytes = await selectDemoImage(context);
//                   if (mounted && bytes != null) setState(() => _photo = bytes);
//                 },
//               ),
//             ],
//           ),
//         ),
//       ),
//     ),
//     actions: [
//       TextButton(
//         onPressed: () => Navigator.pop(context),
//         child: const Text('Cancel'),
//       ),
//       FilledButton(
//         onPressed: () async {
//           if (!_form.currentState!.validate()) return;
//           final saved = await ref
//               .read(propertiesProvider.notifier)
//               .save(
//                 widget.property?.id,
//                 _name.text.trim(),
//                 _address.text.trim(),
//                 _size,
//                 _notes.text.trim(),
//                 type: _type,
//                 photo: _photo,
//                 pin: _latitude.text.trim().isEmpty
//                     ? null
//                     : (
//                         latitude: double.parse(_latitude.text.trim()),
//                         longitude: double.parse(_longitude.text.trim()),
//                       ),
//               );
//           if (saved && context.mounted) Navigator.pop(context);
//         },
//         child: const Text('Save property'),
//       ),
//     ],
//   );
// }

// Widget _field(
//   TextEditingController controller,
//   String label, {
//   bool required = false,
// }) => Padding(
//   padding: const EdgeInsets.symmetric(vertical: 6),
//   child: TextFormField(
//     controller: controller,
//     decoration: InputDecoration(labelText: label),
//     validator: required
//         ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
//         : null,
//   ),
// );

// class BookingScreen extends ConsumerStatefulWidget {
//   const BookingScreen({super.key, required this.propertyId, this.service});
//   final int? propertyId;
//   final Service? service;

//   @override
//   ConsumerState<BookingScreen> createState() => _BookingScreenState();
// }

// class _BookingScreenState extends ConsumerState<BookingScreen> {
//   late Service _service = widget.service ?? Service.snow;
//   final _notes = TextEditingController();
//   DateTime? _scheduled;
//   bool _urgent = false;
//   bool _recurring = false;
//   bool _walkway = false;
//   Uint8List? _referencePhoto;
//   final _coupon = TextEditingController();

//   @override
//   void dispose() {
//     _notes.dispose();
//     _coupon.dispose();
//     super.dispose();
//   }

//   Future<void> _pickSchedule() async {
//     final now = DateTime.now();
//     final day = await showDatePicker(
//       builder: (_, child) => Theme(data: EdenDarkTheme.data, child: child!),
//       context: context,
//       initialDate: _scheduled ?? now,
//       firstDate: DateUtils.dateOnly(now),
//       lastDate: now.add(const Duration(days: 365)),
//     );
//     if (!mounted || day == null) return;
//     final time = await showTimePicker(
//       builder: (_, child) => Theme(data: EdenDarkTheme.data, child: child!),
//       context: context,
//       initialTime: TimeOfDay.fromDateTime(
//         _scheduled ?? now.add(const Duration(hours: 1)),
//       ),
//     );
//     if (!mounted || time == null) return;
//     final selected = DateTime(
//       day.year,
//       day.month,
//       day.day,
//       time.hour,
//       time.minute,
//     );
//     if (selected.isBefore(DateTime.now())) {
//       ScaffoldMessenger.of(context)
//           .showSnackBar(const SnackBar(content: Text('Choose a future time.')));
//       return;
//     }
//     setState(() => _scheduled = selected);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final property = ref
//         .watch(propertiesProvider)
//         .where((item) => item.id == widget.propertyId)
//         .firstOrNull;
//     if (property == null) {
//       return const MarketPage(
//         dark: true,
//         title: 'Book a service',
//         children: [Text('Property unavailable.')],
//       );
//     }
//     final catalog = ref.watch(serviceCatalogProvider);
//     final options = catalog.value ?? const <Service, int>{};
//     if (options.isEmpty) {
//       return MarketPage(
//         dark: true,
//         title: 'Book a service',
//         children: [
//           if (catalog.isLoading)
//             const LinearProgressIndicator()
//           else
//             TextButton(
//               onPressed: () => ref.invalidate(serviceCatalogProvider),
//               child: const Text('Reload available services'),
//             ),
//         ],
//       );
//     }
//     final service = options.containsKey(_service)
//         ? _service
//         : options.keys.first;
//     final base = options[service]! / 100 + (property.size == 'Large' ? 15 : 0);
//     final rushFee = _urgent ? 20 : 0;
//     final walkwayFee = service == Service.snow && _walkway ? 12 : 0;
//     final subtotal = base + rushFee + walkwayFee;
//     final discount = _coupon.text.trim().toUpperCase() == 'EDEN10'
//         ? (subtotal * 10).round() / 100
//         : 0;
//     final tax = ((subtotal - discount) * 13).round() / 100;
//     final total = subtotal - discount + tax;
//     return MarketPage(
//       dark: true,
//       title: 'Book a service',
//       children: [
//         MarketBanner(
//           property.name,
//           property.address,
//           Icons.event_available_outlined,
//         ),
//         MarketCard(
//           solid: true,
//           children: [
//             DropdownButtonFormField<Service>(
//               initialValue: service,
//               decoration: const InputDecoration(labelText: 'Service'),
//               items: [
//                 for (final service in options.keys)
//                   DropdownMenuItem(value: service, child: Text(service.label)),
//               ],
//               onChanged: (service) => setState(() => _service = service!),
//             ),
//             OutlinedButton.icon(
//               onPressed: _pickSchedule,
//               icon: const Icon(Icons.schedule),
//               label: Text(
//                 _scheduled == null
//                     ? 'Choose date and time'
//                     : _date.format(_scheduled!),
//               ),
//             ),
//             SwitchListTile(
//               contentPadding: EdgeInsets.zero,
//               title: const Text('Urgent booking'),
//               value: _urgent,
//               onChanged: (value) => setState(() => _urgent = value),
//             ),
//             SwitchListTile(
//               contentPadding: EdgeInsets.zero,
//               title: const Text('Weekly service preference'),
//               value: _recurring,
//               onChanged: (value) => setState(() => _recurring = value),
//             ),
//             if (service == Service.snow)
//               CheckboxListTile(
//                 contentPadding: EdgeInsets.zero,
//                 title: const Text('Add walkway clearing · CAD 12'),
//                 value: _walkway,
//                 onChanged: (value) => setState(() => _walkway = value ?? false),
//               ),
//             TextField(
//               controller: _coupon,
//               onChanged: (_) => setState(() {}),
//               decoration: InputDecoration(
//                 labelText: 'Promo code',
//                 helperText: 'Demo code: EDEN10',
//                 errorText: _coupon.text.trim().isNotEmpty && discount == 0
//                     ? 'Code is not recognized'
//                     : null,
//               ),
//             ),
//             _field(_notes, 'Instructions for the contractor'),
//             if (_referencePhoto case final photo?) DemoImage(photo),
//             OutlinedButton.icon(
//               icon: const Icon(Icons.add_a_photo_outlined),
//               label: const Text('Choose reference photo'),
//               onPressed: () async {
//                 final bytes = await selectDemoImage(context);
//                 if (mounted && bytes != null) {
//                   setState(() => _referencePhoto = bytes);
//                 }
//               },
//             ),
//           ],
//         ),
//         MarketCard(
//           solid: true,
//           children: [
//             MarketHeading('Instant quote'),
//             Text('Service  ${_money.format(base)}'),
//             if (_urgent) Text('Urgent fee  ${_money.format(rushFee)}'),
//             if (walkwayFee > 0)
//               Text('Walkway clearing  ${_money.format(walkwayFee)}'),
//             if (discount > 0)
//               Text('Promo discount  -${_money.format(discount)}'),
//             Text('Estimated tax  ${_money.format(tax)}'),
//             const Divider(),
//             MarketHeading('Total  ${_money.format(total)} CAD'),
//             const Text('Payment is available after the booking is completed.'),
//             FilledButton(
//               onPressed: _scheduled == null
//                   ? null
//                   : () async {
//                       if (!_scheduled!.isAfter(DateTime.now())) {
//                         setState(() => _scheduled = null);
//                         return;
//                       }
//                       final confirmed = await showCustomerDialog<bool>(
//                         context: context,
//                         builder: (dialog) => AlertDialog(
//                           title: const Text('Review checkout'),
//                           content: Column(
//                             mainAxisSize: MainAxisSize.min,
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text(service.label),
//                               Text(property.address),
//                               Text(_date.format(_scheduled!)),
//                               const Divider(),
//                               Text('Total: ${_money.format(total)} CAD'),
//                               const Text('No charge will be made.'),
//                             ],
//                           ),
//                           actions: [
//                             TextButton(
//                               onPressed: () => Navigator.pop(dialog, false),
//                               child: const Text('Back'),
//                             ),
//                             FilledButton(
//                               onPressed: () => Navigator.pop(dialog, true),
//                               child: const Text('Place booking'),
//                             ),
//                           ],
//                         ),
//                       );
//                       if (!context.mounted || confirmed != true) return;
//                       if (!_scheduled!.isAfter(DateTime.now())) {
//                         setState(() => _scheduled = null);
//                         return;
//                       }
//                       final placed = await ref
//                           .read(bookingsProvider.notifier)
//                           .place(
//                             property,
//                             service,
//                             _scheduled!,
//                             [
//                               if (walkwayFee > 0) 'Includes walkway clearing.',
//                               if (_notes.text.trim().isNotEmpty)
//                                 _notes.text.trim(),
//                             ].join(' '),
//                             _recurring,
//                             referencePhoto: _referencePhoto,
//                             urgent: _urgent,
//                             walkway: _walkway,
//                             discount: discount > 0,
//                           );
//                       if (placed && context.mounted) context.go('/bookings');
//                     },
//               child: const Text('Continue to checkout'),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
// }

// class BookingListScreen extends ConsumerWidget {
//   const BookingListScreen({super.key, this.contractor = false});
//   final bool contractor;

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final bookings = ref.watch(bookingsProvider);
//     final available = ref.watch(demoSettingsProvider).available;
//     final visible = bookings.where(
//       (booking) =>
//           !contractor ||
//           (!booking.declined &&
//               (booking.status != JobStatus.searching || available)),
//     );
//     return MarketPage(
//       title: contractor ? 'Eden Contractor' : 'My bookings',
//       nav: contractor ? null : 1,
//       dark: true,
//       darkNavigation: contractor ? null : const CustomerNavigation(index: 1),
//       actions: contractor
//           ? [
//               IconButton(
//                 tooltip: 'Profile & settings',
//                 icon: const Icon(Icons.person_outline),
//                 onPressed: () => context.push('/profile', extra: true),
//               ),
//               TextButton.icon(
//                 onPressed: () => signOut(context, ref),
//                 icon: const Icon(Icons.logout),
//                 label: const Text('Log out'),
//               ),
//             ]
//           : null,
//       children: [
//         MarketBanner(
//           contractor ? 'Job dashboard' : 'Your bookings',
//           contractor
//               ? 'Find new work and manage your accepted jobs.'
//               : 'Follow service progress and review finished work.',
//           contractor ? Icons.handyman_outlined : Icons.receipt_long_outlined,
//         ),
//         if (contractor)
//           MarketCard(
//             children: [
//               MarketHeading(
//                 available ? 'Available for jobs' : 'Offline',
//                 compact: true,
//               ),
//               Wrap(
//                 spacing: EdenSpacing.gap,
//                 runSpacing: EdenSpacing.gap,
//                 children: [
//                   for (final (label, count) in [
//                     (
//                       'Available',
//                       visible
//                           .where((job) => job.status == JobStatus.searching)
//                           .length,
//                     ),
//                     (
//                       'Active',
//                       visible
//                           .where(
//                             (job) =>
//                                 job.status != JobStatus.searching &&
//                                 job.status != JobStatus.completed &&
//                                 job.status != JobStatus.cancelled,
//                           )
//                           .length,
//                     ),
//                     (
//                       'Completed',
//                       visible
//                           .where((job) => job.status == JobStatus.completed)
//                           .length,
//                     ),
//                   ])
//                     Chip(label: Text('$count $label')),
//                 ],
//               ),
//               Wrap(
//                 spacing: 8,
//                 runSpacing: 8,
//                 children: [
//                   OutlinedButton.icon(
//                     onPressed: () => context.push('/profile', extra: true),
//                     icon: const Icon(Icons.person_outline),
//                     label: const Text('Profile & settings'),
//                   ),
//                   OutlinedButton.icon(
//                     onPressed: () => context.push('/settings/wallet'),
//                     icon: const Icon(Icons.account_balance_wallet_outlined),
//                     label: const Text('Earnings'),
//                   ),
//                   TextButton(
//                     onPressed: () => context.go('/customer-home'),
//                     child: const Text('Switch to customer'),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         if (visible.isEmpty)
//           if (contractor)
//             EmptyState(
//               icon: Icons.inbox_outlined,
//               message: 'No jobs to show right now.',
//               action: TextButton(
//                 onPressed: () => context.push('/profile', extra: true),
//                 child: const Text('Open profile'),
//               ),
//             )
//           else
//             EmptyState(
//               icon: Icons.receipt_long_outlined,
//               message: 'Your orders will appear here after you book a service.',
//               action: TextButton(
//                 onPressed: () => context.go('/customer-home'),
//                 child: const Text('Browse services'),
//               ),
//             ),
//         for (final (title, statuses)
//             in (contractor
//                 ? [
//                     ('Available jobs', [JobStatus.searching]),
//                     (
//                       'Active jobs',
//                       [
//                         JobStatus.accepted,
//                         JobStatus.enRoute,
//                         JobStatus.arrived,
//                         JobStatus.working,
//                         JobStatus.submitted,
//                       ],
//                     ),
//                     ('Completed jobs', [JobStatus.completed]),
//                   ]
//                 : [
//                     (
//                       'Active',
//                       JobStatus.values.where(
//                         (status) =>
//                             status != JobStatus.completed &&
//                             status != JobStatus.cancelled,
//                       ),
//                     ),
//                     (
//                       'Past bookings',
//                       [JobStatus.completed, JobStatus.cancelled],
//                     ),
//                   ]))
//           if (visible.any((booking) => statuses.contains(booking.status))) ...[
//             MarketHeading(title),
//             for (final booking in visible.where(
//               (booking) => statuses.contains(booking.status),
//             ))
//               MarketCard(
//                 children: [
//                   MarketHeading(booking.service.label, compact: true),
//                   Text(booking.property.address),
//                   Text(
//                     '${_date.format(booking.date)} · ${_money.format(booking.total)} CAD',
//                   ),
//                   Wrap(
//                     spacing: 12,
//                     crossAxisAlignment: WrapCrossAlignment.center,
//                     children: [
//                       StatusChip(
//                         label: booking.status.label,
//                         status: _bookingStatus(booking.status),
//                       ),
//                       TextButton(
//                         onPressed: () => context.push(
//                           '/${contractor ? 'job-details' : 'bookings'}/${booking.id}',
//                         ),
//                         child: const Text('View details'),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//           ],
//       ],
//     );
//   }
// }

// class BookingDetailsScreen extends ConsumerWidget {
//   const BookingDetailsScreen({
//     super.key,
//     required this.id,
//     this.contractor = false,
//   });
//   final int? id;
//   final bool contractor;

//   Future<void> _pickPhoto(
//     BuildContext context,
//     WidgetRef ref,
//     Booking booking, {
//     required bool before,
//   }) async {
//     try {
//       final file = await ImagePicker().pickImage(
//         source: ImageSource.gallery,
//         maxWidth: 1600,
//         imageQuality: 85,
//       );
//       if (file == null) return;
//       final bytes = await file.readAsBytes();
//       if (!context.mounted) return;
//       if (bytes.length > 2 * 1024 * 1024) {
//         throw StateError('Photo exceeds 2 MB');
//       }
//       ref.read(bookingsProvider.notifier).change(booking.id, (current) {
//         if (current.status != booking.status) return current;
//         return before
//             ? current.update(before: bytes)
//             : current.update(after: bytes);
//       });
//     } catch (_) {
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Could not open photo. Try an image under 2 MB.'),
//           ),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final booking = ref
//         .watch(bookingsProvider)
//         .where((item) => item.id == id)
//         .firstOrNull;
//     if (booking == null) {
//       return MarketPage(
//         title: 'Booking details',
//         dark: !contractor,
//         children: [Text('Booking unavailable.')],
//       );
//     }
//     final notifier = ref.read(bookingsProvider.notifier);
//     void advance(JobStatus next) => notifier.change(
//       booking.id,
//       (current) => current.status == booking.status
//           ? current.update(status: next)
//           : current,
//     );
//     return MarketPage(
//       title: contractor ? 'Job details' : 'Booking details',
//       dark: !contractor,
//       actions: [
//         TextButton(
//           onPressed: () =>
//               context.go(contractor ? '/contractor-home' : '/bookings'),
//           child: Text(contractor ? 'All jobs' : 'All bookings'),
//         ),
//       ],
//       children: [
//         MarketBanner(
//           booking.service.label,
//           booking.property.address,
//           Icons.assignment_outlined,
//         ),
//         MarketCard(
//           children: [
//             if (contractor)
//               Chip(label: Text(booking.status.label), backgroundColor: _mint)
//             else
//               StatusChip(
//                 label: booking.status.label,
//                 status: _bookingStatus(booking.status),
//               ),
//             Text(_date.format(booking.date)),
//             Text('${_money.format(booking.total)} CAD'),
//             if (booking.recurring) const Text('Weekly service requested'),
//             if (booking.property.pin case final pin?)
//               OutlinedButton.icon(
//                 icon: const Icon(Icons.map_outlined),
//                 label: const Text('View property on map'),
//                 onPressed: () => showCustomerDialog<void>(
//                   dark: !contractor,
//                   context: context,
//                   builder: (_) => AlertDialog(
//                     title: Text(booking.property.name),
//                     content: SizedBox(
//                       width: 560,
//                       child: PropertyMap(
//                         initial: LatLng(pin.latitude, pin.longitude),
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             if (booking.property.notes.isNotEmpty) Text(booking.property.notes),
//             if (booking.notes.isNotEmpty) Text(booking.notes),
//             if (booking.status != JobStatus.searching &&
//                 booking.status != JobStatus.cancelled)
//               OutlinedButton.icon(
//                 onPressed: () =>
//                     context.push('/chat/${booking.id}', extra: contractor),
//                 icon: const Icon(Icons.chat_bubble_outline),
//                 label: const Text('Messages'),
//               ),
//           ],
//         ),
//         if (!contractor && booking.status == JobStatus.enRoute)
//           MarketCard(
//             children: [
//               const Text('Your contractor is on the way'),
//               CustomerTrackingMap(
//                 key: ValueKey(booking.id),
//                 bookingId: booking.id,
//               ),
//             ],
//           ),
//         if (!contractor && booking.status == JobStatus.completed)
//           MarketCard(
//             children: [
//               MarketHeading('Booking summary'),
//               Text('Booking #${booking.id} · ${booking.service.label}'),
//               Text('Quoted total: ${_money.format(booking.total)} CAD'),
//               TextButton(
//                 onPressed: () => context.push('/account/payments'),
//                 child: const Text('Payments & refunds'),
//               ),
//             ],
//           ),
//         if (booking.referencePhoto case final photo?)
//           MarketCard(
//             children: [const Text('Booking reference photo'), DemoImage(photo)],
//           ),
//         if (booking.before != null ||
//             booking.after != null ||
//             (contractor &&
//                 [
//                   JobStatus.arrived,
//                   JobStatus.working,
//                 ].contains(booking.status)))
//           MarketCard(
//             children: [
//               MarketHeading('Work photos'),
//               for (final (label, bytes) in [
//                 ('Before', booking.before),
//                 ('After', booking.after),
//               ])
//                 if (bytes != null) ...[
//                   Text(label),
//                   ClipRRect(
//                     borderRadius: BorderRadius.circular(12),
//                     child: Image.memory(
//                       bytes,
//                       height: 200,
//                       width: double.infinity,
//                       fit: BoxFit.cover,
//                       errorBuilder: (_, error, stackTrace) =>
//                           const Text('Photo preview unavailable'),
//                     ),
//                   ),
//                 ],
//               if (contractor &&
//                   booking.status == JobStatus.arrived &&
//                   booking.before == null)
//                 const Text('Add a before photo to start work.'),
//               if (contractor &&
//                   booking.status == JobStatus.working &&
//                   booking.after == null)
//                 const Text('Add an after photo to submit the job.'),
//               if (contractor && booking.status == JobStatus.arrived)
//                 OutlinedButton.icon(
//                   onPressed: () =>
//                       _pickPhoto(context, ref, booking, before: true),
//                   icon: const Icon(Icons.add_a_photo_outlined),
//                   label: const Text('Choose before photo'),
//                 ),
//               if (contractor && booking.status == JobStatus.working)
//                 OutlinedButton.icon(
//                   onPressed: () =>
//                       _pickPhoto(context, ref, booking, before: false),
//                   icon: const Icon(Icons.add_a_photo_outlined),
//                   label: const Text('Choose after photo'),
//                 ),
//             ],
//           ),
//         if (contractor && !booking.declined) ...[
//           if (booking.status == JobStatus.searching)
//             Wrap(
//               spacing: 8,
//               runSpacing: 8,
//               children: [
//                 if (ref.watch(contractorVerificationProvider).value ==
//                     'Approved')
//                   FilledButton(
//                     onPressed: () => advance(JobStatus.accepted),
//                     child: const Text('Accept job'),
//                   )
//                 else
//                   FilledButton(
//                     onPressed: () async {
//                       ref.invalidate(contractorVerificationProvider);
//                       await context.push('/verification');
//                       if (context.mounted)
//                         ref.invalidate(contractorVerificationProvider);
//                     },
//                     child: const Text('Open verification'),
//                   ),
//                 OutlinedButton(
//                   onPressed: () {
//                     notifier.change(
//                       booking.id,
//                       (current) => current.update(declined: true),
//                     );
//                     context.go('/contractor-home');
//                   },
//                   child: const Text('Decline'),
//                 ),
//               ],
//             ),
//           if (booking.status == JobStatus.accepted)
//             FilledButton(
//               onPressed: () => advance(JobStatus.enRoute),
//               child: const Text('Mark on the way'),
//             ),
//           if (booking.status == JobStatus.enRoute)
//             ContractorLocationSharing(
//               key: ValueKey(booking.id),
//               bookingId: booking.id,
//             ),
//           if (booking.status == JobStatus.enRoute)
//             FilledButton(
//               onPressed: () => advance(JobStatus.arrived),
//               child: const Text('Mark arrived'),
//             ),
//           if (booking.status == JobStatus.arrived)
//             FilledButton(
//               onPressed: booking.before == null
//                   ? null
//                   : () => advance(JobStatus.working),
//               child: const Text('Start work'),
//             ),
//           if (booking.status == JobStatus.working)
//             FilledButton(
//               onPressed: booking.after == null
//                   ? null
//                   : () => advance(JobStatus.submitted),
//               child: const Text('Submit completed work'),
//             ),
//         ],
//         if (!contractor && booking.status == JobStatus.submitted)
//           Wrap(
//             spacing: 8,
//             runSpacing: 8,
//             children: [
//               FilledButton(
//                 onPressed: () => advance(JobStatus.completed),
//                 child: const Text('Approve work'),
//               ),
//               OutlinedButton(
//                 onPressed: () {
//                   notifier.change(
//                     booking.id,
//                     (current) => current.update(
//                       status: JobStatus.working,
//                       clearAfter: true,
//                       messages: [
//                         ...current.messages,
//                         (
//                           contractor: false,
//                           text: 'I requested rework. Please check in before resubmitting.',
//                           image: null,
//                         ),
//                       ],
//                     ),
//                   );
//                 },
//                 child: const Text('Request rework'),
//               ),
//             ],
//           ),
//         if (!contractor &&
//             booking.status == JobStatus.completed &&
//             booking.rating == null)
//           FilledButton(
//             onPressed: () => showCustomerDialog<void>(
//               dark: !contractor,
//               context: context,
//               builder: (_) => _ReviewDialog(id: booking.id),
//             ),
//             child: const Text('Rate the service'),
//           ),
//         MarketCard(
//           children: [
//             MarketHeading('Service progress'),
//             if (!contractor && booking.status == JobStatus.cancelled)
//               const StatusChip(label: 'Cancelled')
//             else if (!contractor)
//               StatusStepper(
//                 labels: JobStatus.values.map((status) => status.label).toList(),
//                 current: booking.status.index,
//               ),
//             if (contractor)
//               for (final status in JobStatus.values)
//                 ListTile(
//                   dense: true,
//                   contentPadding: EdgeInsets.zero,
//                   leading: Icon(
//                     status.index < booking.status.index
//                         ? Icons.check_circle_outline
//                         : status == booking.status
//                         ? Icons.radio_button_checked
//                         : Icons.radio_button_unchecked,
//                     color: status.index <= booking.status.index ? _green : null,
//                   ),
//                   title: Text(status.label),
//                   selected: status == booking.status,
//                 ),
//           ],
//         ),
//         if (booking.rating != null)
//           MarketCard(
//             children: [
//               Text('Customer rating · ${booking.rating}/5'),
//               if (booking.review.isNotEmpty) Text(booking.review),
//             ],
//           ),
//       ],
//     );
//   }
// }

// class _ReviewDialog extends ConsumerStatefulWidget {
//   const _ReviewDialog({required this.id});
//   final int id;
//   @override
//   ConsumerState<_ReviewDialog> createState() => _ReviewDialogState();
// }

// class _ReviewDialogState extends ConsumerState<_ReviewDialog> {
//   int _rating = 0;
//   final _review = TextEditingController();

//   @override
//   void dispose() {
//     _review.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) => AlertDialog(
//     title: const Text('Rate the service'),
//     content: Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Wrap(
//           children: [
//             for (var value = 1; value <= 5; value++)
//               IconButton(
//                 tooltip: '$value stars',
//                 onPressed: () => setState(() => _rating = value),
//                 icon: Icon(
//                   value <= _rating ? Icons.star : Icons.star_border,
//                   color: Theme.of(context).colorScheme.primary,
//                 ),
//               ),
//           ],
//         ),
//         _field(_review, 'Write a review (optional)'),
//       ],
//     ),
//     actions: [
//       TextButton(
//         onPressed: () => Navigator.pop(context),
//         child: const Text('Cancel'),
//       ),
//       FilledButton(
//         onPressed: _rating == 0
//             ? null
//             : () {
//                 ref
//                     .read(bookingsProvider.notifier)
//                     .change(
//                       widget.id,
//                       (booking) => booking.update(
//                         rating: _rating,
//                         review: _review.text.trim(),
//                       ),
//                     );
//                 Navigator.pop(context);
//               },
//         child: const Text('Submit review'),
//       ),
//     ],
//   );
// }

// class ChatScreen extends ConsumerStatefulWidget {
//   const ChatScreen({super.key, required this.id, required this.contractor});
//   final int? id;
//   final bool contractor;

//   @override
//   ConsumerState<ChatScreen> createState() => _ChatScreenState();
// }

// class _ChatScreenState extends ConsumerState<ChatScreen> {
//   final _message = TextEditingController();

//   @override
//   void dispose() {
//     _message.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final booking = ref
//         .watch(bookingsProvider)
//         .where((item) => item.id == widget.id)
//         .firstOrNull;
//     if (booking == null) {
//       return MarketPage(
//         title: 'Messages',
//         dark: !widget.contractor,
//         children: [Text('Booking unavailable.')],
//       );
//     }
//     Future<void> send([Uint8List? image]) async {
//       final message = _message.text.trim();
//       if (message.isEmpty && image == null) return;
//       final sent = await ref
//           .read(bookingsProvider.notifier)
//           .change(
//             booking.id,
//             (current) => current.update(
//               messages: [
//                 ...current.messages,
//                 (contractor: widget.contractor, text: message, image: image),
//               ],
//             ),
//           );
//       if (sent && mounted && _message.text.trim() == message) _message.clear();
//     }

//     return MarketPage(
//       title: 'Messages',
//       dark: !widget.contractor,
//       children: [
//         MarketBanner(
//           booking.service.label,
//           'Conversation for this booking',
//           Icons.chat_bubble_outline,
//         ),
//         MarketCard(
//           children: [
//             if (booking.messages.isEmpty) const Text('No messages yet.'),
//             for (final message in booking.messages)
//               Align(
//                 alignment: message.contractor == widget.contractor
//                     ? Alignment.centerRight
//                     : Alignment.centerLeft,
//                 child: Container(
//                   constraints: const BoxConstraints(maxWidth: 460),
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: widget.contractor
//                         ? _mint
//                         : EdenDarkColors.strongGlass,
//                     borderRadius: BorderRadius.circular(14),
//                   ),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         '${message.contractor ? 'Contractor' : 'Customer'}\n${message.text}',
//                       ),
//                       if (message.image case final image?) DemoImage(image),
//                     ],
//                   ),
//                 ),
//               ),
//             TextField(
//               controller: _message,
//               onSubmitted: (_) => send(),
//               decoration: InputDecoration(
//                 labelText: 'Message',
//                 prefixIcon: IconButton(
//                   tooltip: 'Attach photo',
//                   icon: const Icon(Icons.image_outlined),
//                   onPressed: () async {
//                     final bytes = await selectDemoImage(context);
//                     if (mounted && bytes != null) send(bytes);
//                   },
//                 ),
//                 suffixIcon: IconButton(
//                   onPressed: send,
//                   tooltip: 'Send',
//                   icon: const Icon(Icons.send),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
// }

// class ProfileScreen extends ConsumerWidget {
//   const ProfileScreen({super.key, this.contractor = false});
//   final bool contractor;

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final auth = ref.watch(authProvider);
//     final registration = ref.watch(registrationDetailsProvider);
//     final user = auth.maybeWhen(
//       authenticated: (user) => user,
//       orElse: () => null,
//     );
//     return MarketPage(
//       title: 'Profile & settings',
//       dark: !contractor,
//       darkNavigation: contractor ? null : const CustomerNavigation(index: 3),
//       nav: contractor ? null : 2,
//       children: [
//         MarketBanner(
//           user?.name ?? 'Eden profile',
//           contractor ? 'Contractor view' : 'Customer view',
//           Icons.person_outline,
//         ),
//         MarketCard(
//           children: [
//             if (user != null) ...[
//               if (ref.watch(accountImageProvider('profile')).value
//                   case final photo?)
//                 CircleAvatar(radius: 28, backgroundImage: MemoryImage(photo)),
//               Text(user.email),
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: const Icon(Icons.edit_outlined),
//                 title: const Text('Edit profile'),
//                 onTap: () => context.push('/profile/edit'),
//               ),
//             ],
//             if (contractor)
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: const Icon(Icons.verified_user_outlined),
//                 title: const Text('Verification documents'),
//                 onTap: () => context.push('/verification'),
//               ),
//             if (registration.phone.isNotEmpty) Text(registration.phone),
//             if (contractor && registration.area.isNotEmpty)
//               Text(registration.area),
//             if (contractor && registration.service.isNotEmpty)
//               Text(registration.service),
//             if (!contractor) const Divider(),
//             if (!contractor)
//               const ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 title: Text('Orders & activity'),
//               ),
//             if (contractor)
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: const Icon(Icons.play_circle_outline),
//                 title: const Text('Integration previews'),
//                 onTap: () => context.push('/integration-demo'),
//               ),
//             for (final section in [
//               AccountSection.reviews,
//               if (contractor) AccountSection.schedule,
//               if (!contractor) AccountSection.payments,
//               if (!contractor) AccountSection.recurring,
//             ])
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: Icon(section.icon),
//                 title: Text(section.label),
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () => context.push('/account/${section.name}'),
//               ),
//             if (!contractor) const Divider(),
//             if (!contractor)
//               const ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 title: Text('Preferences & help'),
//               ),
//             for (final section in [
//               SettingsSection.support,
//               SettingsSection.preferences,
//               if (contractor) SettingsSection.wallet,
//               if (contractor) SettingsSection.verification,
//               if (!contractor) SettingsSection.automatic,
//             ])
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: Icon(section.icon),
//                 title: Text(section.label),
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () => context.push('/settings/${section.name}'),
//               ),
//             if (!contractor)
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: const Icon(Icons.home_work_outlined),
//                 title: const Text('Manage properties'),
//                 onTap: () => context.push('/properties'),
//               ),
//             if (!contractor)
//               ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: const Icon(Icons.play_circle_outline),
//                 title: const Text('Integration previews'),
//                 trailing: const Icon(Icons.chevron_right),
//                 onTap: () => context.push('/integration-demo'),
//               ),
//             if (!contractor) const Divider(),
//             ModeSwitchTile(contractor: contractor, area: registration.area),
//             ListTile(
//               contentPadding: EdgeInsets.zero,
//               leading: const Icon(Icons.logout),
//               title: const Text('Log out'),
//               onTap: () => signOut(context, ref),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
// }
