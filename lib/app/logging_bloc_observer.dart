import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

class LoggingBlocObserver extends BlocObserver {
  const LoggingBlocObserver();

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    if (kDebugMode) {
      debugPrint(
        '[bloc] ${bloc.runtimeType}: '
        '${transition.event.runtimeType} -> ${transition.nextState.runtimeType}',
      );
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    if (kDebugMode) {
      debugPrint('[bloc] ${bloc.runtimeType} error: $error');
    }
  }
}
