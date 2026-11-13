import 'package:flutter/material.dart';

import 'account_form_screen.dart';

class CustomerRegisterScreen extends StatelessWidget {
  const CustomerRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AccountFormScreen(mode: AuthMode.customer);
}
