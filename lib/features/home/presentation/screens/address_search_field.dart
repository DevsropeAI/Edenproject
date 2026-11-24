import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/providers/auth_provider.dart';

final geoCapabilitiesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      if (ref.watch(activeAccountIdProvider) == null) return {};
      final response = await ref
          .watch(apiClientProvider)
          .get('/geo/capabilities');
      return Map<String, dynamic>.from(response.data as Map);
    });
final registrationCityCapabilitiesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final response = await ref
          .watch(apiClientProvider)
          .get('/auth/work-city-options');
      return Map<String, dynamic>.from(response.data as Map);
    });

class AddressSearchField extends ConsumerStatefulWidget {
  const AddressSearchField({
    super.key,
    required this.controller,
    required this.label,
    required this.onSelected,
    this.required = false,
    this.enabled = true,
    this.onEdited,
    this.citiesOnly = false,
    this.registration = false,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final VoidCallback? onEdited;
  final bool required;
  final bool enabled;
  final bool citiesOnly;
  final bool registration;

  @override
  ConsumerState<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends ConsumerState<AddressSearchField> {
  static String _newSessionToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _sessionToken = _newSessionToken();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  List<Map<String, dynamic>>? _results;
  String? _message;

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    super.dispose();
  }

  Future<void> _search(bool autocomplete) async {
    _debounce?.cancel();
    final query = widget.controller.text.trim();
    final generation = ++_generation;
    if (query.length < 3 || query.length > 250) {
      setState(
        () => _message = 'Enter between 3 and 250 characters to search.',
      );
      return;
    }
    setState(() {
      _loading = true;
      _message = null;
      _results = null;
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .get(
            widget.registration
                ? (autocomplete
                      ? '/auth/work-city-autocomplete'
                      : '/auth/work-city-search')
                : (autocomplete ? '/geo/autocomplete' : '/geo/search'),
            queryParameters: {
              'q': query,
              'sessionToken': _sessionToken,
              if (widget.citiesOnly) 'type': 'city',
            },
          );
      if (!mounted || generation != _generation) return;
      setState(
        () => _results = (response.data as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = apiError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _select(Map<String, dynamic> result) async {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _results = null;
      _message = null;
      _loading = result['needsDetails'] == true;
    });
    try {
      var selected = result;
      if (result['needsDetails'] == true) {
        final response = await ref
            .read(apiClientProvider)
            .get(
              widget.registration ? '/auth/work-city-place' : '/geo/place',
              queryParameters: {
                'placeId': result['placeId'],
                'sessionToken': _sessionToken,
                if (widget.citiesOnly) 'type': 'city',
              },
            );
        selected = Map<String, dynamic>.from(response.data as Map);
      }
      if (!mounted || generation != _generation) return;
      _sessionToken = _newSessionToken();
      widget.onSelected(selected);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _message = apiError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = ref.watch(
      widget.registration
          ? registrationCityCapabilitiesProvider
          : geoCapabilitiesProvider,
    );
    final autocomplete = capabilities.value?['autocomplete'] == true;
    final canSearch = autocomplete || capabilities.value?['search'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: EdenSpacing.sm,
      children: [
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          maxLength: 150,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: canSearch
                ? IconButton(
                    tooltip: autocomplete ? 'Find suggestions' : 'Search',
                    onPressed: widget.enabled && !_loading
                        ? () => _search(autocomplete)
                        : null,
                    icon: const Icon(Icons.search),
                  )
                : null,
          ),
          validator: (value) {
            final text = (value ?? '').trim();
            if (widget.required && text.isEmpty) {
              return 'Enter ${widget.label.toLowerCase()}';
            }
            if (text.length > 150) return 'Use 150 characters or fewer.';
            if (widget.required && !widget.citiesOnly && text.contains(',')) {
              return 'Enter street and city in their separate fields.';
            }
            return null;
          },
          onFieldSubmitted: canSearch ? (_) => _search(autocomplete) : null,
          onChanged: (_) {
            widget.onEdited?.call();
            _debounce?.cancel();
            _generation++;
            setState(() {
              _results = null;
              _message = null;
              _loading = false;
            });
            if (autocomplete && widget.controller.text.trim().length >= 3) {
              _debounce = Timer(
                const Duration(milliseconds: 400),
                () => _search(true),
              );
            }
          },
        ),
        if (canSearch && !autocomplete)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: widget.enabled && !_loading
                  ? () => _search(false)
                  : null,
              icon: const Icon(Icons.search),
              label: Text(
                widget.citiesOnly ? 'Search cities' : 'Search addresses',
              ),
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
        if (!canSearch && !capabilities.isLoading)
          const Text(
            'Address lookup is unavailable. Enter your details manually.',
          ),
        if (capabilities.hasError)
          TextButton(
            onPressed: () {
              if (widget.registration) {
                ref.invalidate(registrationCityCapabilitiesProvider);
              } else {
                ref.invalidate(geoCapabilitiesProvider);
              }
            },
            child: const Text('Retry address lookup'),
          ),
        if (_results?.isEmpty == true)
          Text(
            widget.citiesOnly
                ? 'No cities found. Search for a city, such as Houston, Texas, United States.'
                : 'No results. Try a more specific search or enter the address manually.',
          ),
        if (_results case final results?)
          for (final result in results)
            ListTile(
              dense: true,
              title: Text(result['label'] as String? ?? ''),
              subtitle: Text(
                [result['city'], result['state'], result['country']]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(', '),
              ),
              onTap: widget.enabled && !_loading ? () => _select(result) : null,
            ),
        if ((capabilities.value?['attribution'] as String? ?? '').isNotEmpty)
          Text(
            capabilities.value?['attribution'] as String? ?? '',
            softWrap: false,
            style: capabilities.value?['attribution'] == 'Google Maps'
                ? Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.normal,
                    letterSpacing: 0,
                  )
                : Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
