import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../marketplace.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/providers/auth_provider.dart';

final contractorServicesProvider=FutureProvider.autoDispose<List<String>>((ref) async {
  ref.watch(activeAccountIdProvider);
  final response=await ref.watch(apiClientProvider).get('/contractor/services');
  return List<String>.from(response.data['serviceIds'] as List);
});

class ContractorServicesEditor extends ConsumerStatefulWidget {
  const ContractorServicesEditor({super.key});
  @override
  ConsumerState<ContractorServicesEditor> createState()=>_ContractorServicesEditorState();
}
class _ContractorServicesEditorState extends ConsumerState<ContractorServicesEditor> {
  Set<String>? _selected;
  bool _busy=false;
  String? _message;
  @override
  Widget build(BuildContext context){
    final saved=ref.watch(contractorServicesProvider);
    final catalog=ref.watch(serviceDetailsProvider);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Additional services',style:Theme.of(context).textTheme.titleMedium),
      const Text('Keep your primary service and choose other services you offer.'),
      if(saved.isLoading||catalog.isLoading)const LinearProgressIndicator(),
      if(saved.hasError||catalog.hasError)TextButton(onPressed:(){ref.invalidate(contractorServicesProvider);ref.invalidate(serviceDetailsProvider);},child:const Text('Retry loading services')),
      if(saved.hasValue&&catalog.hasValue)...[
        for(final service in catalog.value!) CheckboxListTile(
          contentPadding:EdgeInsets.zero,title:Text(service['title'] as String),
          value:(_selected??saved.value!.toSet()).contains(service['id']),
          onChanged:_busy?null:(value)=>setState((){_selected??=saved.value!.toSet();if(value==true){_selected!.add(service['id'] as String);}else{_selected!.remove(service['id']);}}),
        ),
        OutlinedButton(onPressed:_busy?null:()async{
          setState((){_busy=true;_message=null;});
          try{await ref.read(apiClientProvider).post('/contractor/services',data:{'serviceIds':(_selected??saved.value!.toSet()).toList()});
            ref.invalidate(contractorServicesProvider);
            await ref.read(bookingsProvider.notifier).refresh(silent:true);
            if(mounted)setState(()=>_message='Services saved.');
          }catch(e){if(mounted)setState(()=>_message=apiError(e));}
          finally{if(mounted)setState(()=>_busy=false);}
        },child:Text(_busy?'Saving…':'Save services')),
      ],
      if(_message!=null)Text(_message!),
    ]);
  }
}
