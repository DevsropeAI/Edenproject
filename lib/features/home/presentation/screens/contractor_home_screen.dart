import 'package:flutter/material.dart';

import 'marketplace_screens.dart';

class ContractorHomeScreen extends StatelessWidget {
  const ContractorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const BookingListScreen(contractor: true);
}
