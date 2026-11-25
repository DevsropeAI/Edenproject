import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_spacing.dart';
import 'property_map.dart';

typedef WorkPin = ({double latitude, double longitude});

WorkPin? workPinFromJson(Object? input) {
  if (input is! Map || input['latitude'] is! num || input['longitude'] is! num) return null;
  final lat = (input['latitude'] as num).toDouble();
  final lng = (input['longitude'] as num).toDouble();
  return lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180 ? (latitude:lat,longitude:lng) : null;
}

class WorkLocationPinField extends StatelessWidget {
  const WorkLocationPinField({super.key, required this.value, required this.onChanged, this.enabled=true, this.required=false, this.pick});
  final WorkPin? value;
  final ValueChanged<WorkPin> onChanged;
  final bool enabled;
  final bool required;
  final Future<WorkPin?> Function(BuildContext, WorkPin?)? pick;

  Future<WorkPin?> _pick(BuildContext context) async {
    if (pick != null) return pick!(context,value);
    final pin=await showDialog<LatLng>(context:context,builder:(dialog)=>AlertDialog(
      title:const Text('Work location'), scrollable:true,
      content:SizedBox(width:560,child:PropertyMap(
        initial:value == null ? const LatLng(0,0) : LatLng(value!.latitude,value!.longitude),
        editable:true,locateOnOpen:value == null,
      )),
    ));
    return pin == null ? null : (latitude:pin.latitude,longitude:pin.longitude);
  }

  @override
  Widget build(BuildContext context) => FormField<WorkPin>(
    key:ValueKey(value), initialValue:value, enabled:enabled,
    validator:(pin)=>required && pin == null ? 'Choose your work location on the map.' : null,
    builder:(field)=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Work location',style:Theme.of(context).textTheme.titleMedium),
      const SizedBox(height:EdenSpacing.gap),
      Text(value == null ? 'Choose a pin or use your current location.' : 'Selected pin: ${value!.latitude.toStringAsFixed(5)}, ${value!.longitude.toStringAsFixed(5)}'),
      const SizedBox(height:EdenSpacing.gap),
      OutlinedButton.icon(onPressed:!enabled?null:() async {
        final pin=await _pick(context);
        if(pin!=null&&context.mounted){field.didChange(pin);onChanged(pin);}
      },icon:const Icon(Icons.location_on_outlined),label:Text(value == null ? 'Choose work location on map' : 'Change work location pin')),
      const SizedBox(height:EdenSpacing.sm),
      Text('This is your saved work location. Live GPS sharing remains separate.',style:Theme.of(context).textTheme.bodySmall),
      if(field.errorText!=null)Text(field.errorText!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ]),
  );
}
