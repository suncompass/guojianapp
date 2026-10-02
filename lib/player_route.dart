import 'package:flutter/material.dart';

Route<void> playerRoute(Widget child) => PageRouteBuilder<void>(
  opaque: true,
  barrierColor: Colors.black,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, animation, secondaryAnimation) => child,
);
