import 'package:flutter/material.dart';

import 'account_form_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AccountFormScreen(mode: AuthMode.login);
}
