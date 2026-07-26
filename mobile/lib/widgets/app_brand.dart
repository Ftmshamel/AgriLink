import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        CircleAvatar(
          backgroundColor: green,
          child: Icon(Icons.eco, color: Colors.white),
        ),
        SizedBox(width: 10),
        Text(
          'AgriLink',
          style: TextStyle(
            color: darkGreen,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
