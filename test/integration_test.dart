// ignore_for_file: cascade_invocations

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
        apiKey: 'test-api-key',
        directoryProvider: testDirectoryProvider,
      );
    });

    tearDownAll(() async {
      /// Wait a few seconds to finish writing to the files.
      await Future<void>.delayed(const Duration(seconds: 5));
    });

    test('CounterBloc 1', () async {
      final bloc = CounterBloc();

      bloc.add(CounterIncrementPressed());
      bloc.add(CounterIncrementPressed());
      bloc.add(CounterIncrementPressed());

      await bloc.close();
    });

    test('CounterBloc 2', () async {
      final bloc = CounterBloc();

      bloc.add(CounterIncrementPressed());
      bloc.add(CounterIncrementPressed());
      bloc.add(CounterIncrementPressed());

      await bloc.close();
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
