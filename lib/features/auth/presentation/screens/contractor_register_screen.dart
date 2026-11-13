import 'package:flutter/material.dart';

import 'account_form_screen.dart';

class ContractorRegisterScreen extends StatelessWidget {
  const ContractorRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AccountFormScreen(mode: AuthMode.contractor);
}
