// lib/widgets/footer_widget.dart

import 'package:flutter/material.dart';

class FooterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        'Copyright © 2025 Yikang. All Rights Reserved.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}