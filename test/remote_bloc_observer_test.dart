// ignore_for_file: cascade_invocations

import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:bloc_remote_logger/src/remote_bloc_observer.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlocRemoteLogger', () {
    setUpAll(() async {
      final tempDirectory = await testDirectoryProvider();
      await tempDirectory.create();

      Bloc.observer = RemoteBlocObserver(
        apiKey: 'api-key',
        directoryProvider: testDirectoryProvider,
      );
    });

    tearDownAll(() async {
      /// Wait a few seconds to finish writing to the files.
      await Future<void>.delayed(const Duration(seconds: 2));
    });

    test('CounterBloc', () async {
      final bloc = CounterBloc();

      for (var i = 0; i < 10; i++) {
        final random = Random().nextInt(1000);
        if (random % 2 == 0) {
          bloc.add(CounterIncrementPressed());
        } else {
          bloc.add(CounterDecrementPressed());
        }

        if (random % 3 == 0) {
          // ignore: invalid_use_of_protected_member
          bloc.addError(Exception('Something went wrong'), StackTrace.current);
        }
      }

      await bloc.close();

      final bloc2 = CounterBloc();

      for (var i = 0; i < 10; i++) {
        final random = Random().nextInt(1000);
        if (random % 2 == 0) {
          bloc2.add(CounterIncrementPressed());
        } else {
          bloc2.add(CounterDecrementPressed());
        }

        if (random % 3 == 0) {
          // ignore: invalid_use_of_protected_member
          bloc2.addError(Exception('Something went wrong'), StackTrace.current);
        }
      }

      await bloc2.close();
    });
  });
}

/// Event being processed by [CounterBloc].
abstract class CounterEvent {}

/// Notifies bloc to increment state.
class CounterIncrementPressed extends CounterEvent {}

/// Notifies bloc to decrement state.
class CounterDecrementPressed extends CounterEvent {}

/// {@template counter_bloc}
/// A simple [Bloc] that manages an `int` as its state.
/// {@endtemplate}
class CounterBloc extends Bloc<CounterEvent, CounterState> {
  /// {@macro counter_bloc}
  CounterBloc() : super(const CounterState(0)) {
    on<CounterIncrementPressed>((event, emit) {
      emit(state.copyWith(value: state.value + 1));
    });
    on<CounterDecrementPressed>((event, emit) {
      emit(state.copyWith(value: state.value - 1));
    });
  }
}

class CounterState extends Equatable {
  const CounterState(this.value);

  final int value;

  CounterState copyWith({
    int? value,
  }) {
    return CounterState(
      value ?? this.value,
    );
  }

  @override
  List<Object?> get props => [value];
}
