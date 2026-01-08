import 'package:flutter/material.dart';

/// Creates a smooth page transition without the refresh-like effect
class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  SmoothPageRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 250),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade transition for smooth appearance
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );
}

/// Creates a smooth replacement page transition
class SmoothPageReplacementRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final Duration duration;

  SmoothPageReplacementRoute({
    required this.page,
    this.duration = const Duration(milliseconds: 200),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Crossfade for seamless replacement
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );
}

/// Helper extension for smooth navigation
extension SmoothNavigation on BuildContext {
  /// Push a new page with smooth transition
  Future<T?> pushSmooth<T>(Widget page) {
    return Navigator.of(this).push<T>(
      SmoothPageRoute(page: page),
    );
  }

  /// Replace current page with smooth transition
  Future<T?> replaceSmooth<T>(Widget page) {
    return Navigator.of(this).pushReplacement<T, void>(
      SmoothPageReplacementRoute(page: page),
    );
  }

  /// Push named route with smooth transition
  Future<T?> pushNamedSmooth<T>(String routeName, {Object? arguments}) {
    return Navigator.of(this).pushNamed<T>(
      routeName,
      arguments: arguments,
    );
  }

  /// Replace named route with smooth transition
  Future<T?> replaceNamedSmooth<T>(String routeName, {Object? arguments}) {
    return Navigator.of(this).pushReplacementNamed<T, void>(
      routeName,
      arguments: arguments,
    );
  }
}
