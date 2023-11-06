// ignore_for_file: public_member_api_docs, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:bloc/bloc.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// [RemoteBlocObserver] is used to observe the state of the bloc
/// and send the state changes to a remote server.
class RemoteBlocObserver extends BlocObserver {
  RemoteBlocObserver({
    required String apiKey,
    String baseUrl = 'http://localhost:8080',
    DirectoryProvider? directoryProvider,
  }) {
    _repository = _Repository(
      sessionId: const Uuid().v4(),
      apiKey: apiKey,
      directoryProvider: directoryProvider ?? defaultDirectoryProvider,
      baseUrl: baseUrl,
    );

    _repository.uploadPreviousSessions();
  }

  late final _Repository _repository;

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);

    final c = _Change(
      blocName: bloc.runtimeType.toString(),
      blocHashCode: bloc.hashCode,
      timestamp: DateTime.now().toUtc(),
      prevState: null,
      nextState: bloc.state,
    );

    _repository.saveChange(c);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);

    final c = _Change(
      blocName: bloc.runtimeType.toString(),
      blocHashCode: bloc.hashCode,
      timestamp: DateTime.now().toUtc(),
      prevState: change.currentState,
      nextState: change.nextState,
    );

    _repository.saveChange(c);
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);

    final e = _Event(
      blocName: bloc.runtimeType.toString(),
      blocHashCode: bloc.hashCode,
      timestamp: DateTime.now().toUtc(),
      event: event,
    );

    _repository.saveEvent(e);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);

    final e = _Error(
      blocName: bloc.runtimeType.toString(),
      blocHashCode: bloc.hashCode,
      timestamp: DateTime.now().toUtc(),
      error: error,
      stackTrace: stackTrace,
    );

    _repository.saveError(e);
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);

    final c = _Change(
      blocName: bloc.runtimeType.toString(),
      blocHashCode: bloc.hashCode,
      timestamp: DateTime.now().toUtc(),
      prevState: bloc.state,
      nextState: null,
    );

    _repository.saveChange(c);
  }
}

class _Repository {
  _Repository({
    required this.sessionId,
    required this.apiKey,
    required this.directoryProvider,
    required this.baseUrl,
  }) {
    _createSessionMetadata();

    _changesStreamSub = _changesStream.stream
        .asyncMap(_handleChange)
        .listen((change) => print('Change handled $change'));

    _eventsStreamSub = _eventsStream.stream
        .asyncMap(_handleEvent)
        .listen((event) => print('Event handled $event'));

    _errorsStreamSub = _errorsStream.stream
        .asyncMap(_handleError)
        .listen((error) => print('Error handled $error'));
  }

  Future<void> _createSessionMetadata() async {
    try {
      /// TODO: optimize, store in local variable.
      final directory = await directoryProvider();
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      final sessionMetadataFile = File(
        path.join(
          directory.path,
          '$apiKey/$sessionId/sessionMetadata.json',
        ),
      );

      /// TODO: optimize, store info if it exists in a local variable.
      if (!sessionMetadataFile.existsSync()) {
        final sessionMetadata = SessionMetadata(
          startedDate: DateTime.now(),
        );
        final sessionMetadataJsonString = jsonEncode(sessionMetadata.toJson());

        await sessionMetadataFile.create(recursive: true);
        await sessionMetadataFile.writeAsString(sessionMetadataJsonString);
      }
    } catch (e) {
      print(e);
    }
  }

  final String sessionId;
  final String apiKey;
  final DirectoryProvider directoryProvider;
  final String baseUrl;

  // ignore: unused_field, cancel_subscriptions
  late final StreamSubscription<_Change> _changesStreamSub;
  final StreamController<_Change> _changesStream = StreamController<_Change>();

  // ignore: unused_field, cancel_subscriptions
  late final StreamSubscription<_Event> _eventsStreamSub;
  final StreamController<_Event> _eventsStream = StreamController<_Event>();

  // ignore: unused_field, cancel_subscriptions
  late final StreamSubscription<_Error> _errorsStreamSub;
  final StreamController<_Error> _errorsStream = StreamController<_Error>();

  Future<void> saveChange(_Change change) async {
    _changesStream.add(change);
  }

  Future<void> saveEvent(_Event event) async {
    _eventsStream.add(event);
  }

  Future<void> saveError(_Error error) async {
    _errorsStream.add(error);
  }

  Future<_Change> _handleChange(_Change change) async {
    /// TODO: optimize, store in local variable.
    final directory = await directoryProvider();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final blocName = change.blocName;
    final blocHashCode = change.blocHashCode;

    /// If prevState is null, then it is means that the bloc has been created.
    if (change.prevState == null) {
      final blocMetadataFile = await File(
        path.join(
          directory.path,
          '$apiKey/$sessionId/$blocName/$blocHashCode/blocMetadata.json',
        ),
      ).create(recursive: true);

      final blocMetadata = BlocMetadata(
        id: const Uuid().v4(),
        createdDate: change.timestamp,
        closedDate: null,
      );

      final blocMetadataJsonString = jsonEncode(blocMetadata.toJson());

      await blocMetadataFile.writeAsString(
        blocMetadataJsonString,
        mode: FileMode.write,
      );
    }

    /// If nextState is null, then it is means that the bloc has been closed.
    if (change.nextState == null) {
      final blocMetadataFile = await File(
        path.join(
          directory.path,
          '$apiKey/$sessionId/$blocName/$blocHashCode/blocMetadata.json',
        ),
      ).create(recursive: true);

      final blocMetadataJsonString = await blocMetadataFile.readAsString();
      final blocMetadataJson =
          jsonDecode(blocMetadataJsonString) as Map<String, dynamic>;
      final blocMetadata = BlocMetadata.fromJson(blocMetadataJson);

      final updatedBlocMetadata = BlocMetadata(
        id: blocMetadata.id,
        createdDate: blocMetadata.createdDate,
        closedDate: change.timestamp,
      );

      final updatedBlocMetadataJsonString =
          jsonEncode(updatedBlocMetadata.toJson());

      await blocMetadataFile.writeAsString(
        updatedBlocMetadataJsonString,
        mode: FileMode.write,
      );
    }

    final file = File(
      path.join(
        directory.path,
        '$apiKey/$sessionId/$blocName/$blocHashCode/states.csv',
      ),
    );

    // ignore: avoid_slow_async_io
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }

    /// Keep the file open for writing.
    await file.writeAsString(
      '${change.toCSV()}\n',
      mode: FileMode.append,
    );

    return change;
  }

  Future<_Event> _handleEvent(_Event event) async {
    final directory = await directoryProvider();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final blocName = event.blocName;
    final blocHashCode = event.blocHashCode;

    final file = File(
      path.join(
        directory.path,
        '$apiKey/$sessionId/$blocName/$blocHashCode/events.csv',
      ),
    );

    // ignore: avoid_slow_async_io
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }

    /// Keep the file open for writing.
    /// TODO: optimize, don't write to file every time.
    await file.writeAsString(
      '${event.toCSV()}\n',
      mode: FileMode.append,
    );

    return event;
  }

  Future<_Error> _handleError(_Error error) async {
    final directory = await directoryProvider();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final blocName = error.blocName;
    final blocHashCode = error.blocHashCode;

    final file = File(
      path.join(
        directory.path,
        '$apiKey/$sessionId/$blocName/$blocHashCode/errors.csv',
      ),
    );

    // ignore: avoid_slow_async_io
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }

    /// Keep the file open for writing.
    /// TODO: optimize, don't write to file every time.
    await file.writeAsString(
      '${error.toCSV()}\n',
      mode: FileMode.append,
    );

    return error;
  }

  Future<void> uploadPreviousSessions() async {
    final directory = await directoryProvider();
    if (!directory.existsSync()) {
      print("Directory $directory doesn't exist");
      return;
    }

    final apiKeyDirectory = Directory(path.join(directory.path, apiKey));
    if (!apiKeyDirectory.existsSync()) {
      print("Directory $directory doesn't exist");
      return;
    }

    /// Get all the past sessions directories.
    final pastSessions = apiKeyDirectory
        .listSync()
        .whereType<Directory>()
        .where((element) => path.basename(element.path) != sessionId);

    final pastSessionsPath = '${apiKeyDirectory.path}/sessions.zip';

    // Manually create a zip of a directory and individual files.
    final encoder = ZipFileEncoder()..create(pastSessionsPath);

    for (final pastSession in pastSessions) {
      await encoder.addDirectory(pastSession);
    }
    encoder.close();

    /// Upload the zip file using dio package to localhost:8080/files
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        pastSessionsPath,
        filename: 'sessions.zip',
      ),
    });

    try {
      // ignore: inference_failure_on_function_invocation
      final response = await Dio().put(
        '$baseUrl/files',
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
            'Authorization': 'Bearer $apiKey',
          },
        ),
        data: formData,
      );

      if (response.statusCode == HttpStatus.ok) {
        /// Remove the zip file and the past sessions directories.
        await File(pastSessionsPath).delete();
        for (final pastSession in pastSessions) {
          await pastSession.delete(recursive: true);
        }
      }
    } catch (e) {
      print(e);
    }
  }
}

class _Change {
  _Change({
    required this.blocName,
    required this.blocHashCode,
    required this.timestamp,
    required this.nextState,
    this.prevState,
  });

  final String blocName;
  final int blocHashCode;
  final DateTime timestamp;
  final dynamic prevState;
  final dynamic nextState;

  String toCSV() {
    final timestamp = this.timestamp.toUtc().toIso8601String();
    final contentChange = base64.encode(utf8.encode(diff()));

    return [
      timestamp,
      contentChange,
    ].join(',');
  }

  String diff() {
    return patchToText(
      patchMake(
        prevState?.toString() ?? '',
        b: nextState.toString(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'blocName': blocName,
      'blocHashCode': blocHashCode,
      'prevState': prevState,
      'nextState': nextState,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  String toString() {
    return toJson().toString();
  }
}

class _Event {
  _Event({
    required this.blocName,
    required this.blocHashCode,
    required this.timestamp,
    required this.event,
  });

  final String blocName;
  final int blocHashCode;
  final DateTime timestamp;
  final dynamic event;

  String toCSV() {
    final timestamp = this.timestamp.toUtc().toIso8601String();
    final content = base64.encode(utf8.encode(event.toString()));

    return [
      timestamp,
      content,
    ].join(',');
  }

  Map<String, dynamic> toJson() {
    return {
      'blocName': blocName,
      'blocHashCode': blocHashCode,
      'timestamp': timestamp.toIso8601String(),
      'event': event.toString(),
    };
  }

  @override
  String toString() {
    return toJson().toString();
  }
}

class _Error {
  _Error({
    required this.blocName,
    required this.blocHashCode,
    required this.timestamp,
    required this.error,
    required this.stackTrace,
  });

  final String blocName;
  final int blocHashCode;
  final DateTime timestamp;
  final dynamic error;
  final StackTrace stackTrace;

  String toCSV() {
    final timestamp = this.timestamp.toUtc().toIso8601String();
    final errorContent = base64.encode(utf8.encode(error.toString()));
    final errorStackTrace = base64.encode(utf8.encode(stackTrace.toString()));

    return [
      timestamp,
      errorContent,
      errorStackTrace,
    ].join(',');
  }

  Map<String, dynamic> toJson() {
    return {
      'blocName': blocName,
      'blocHashCode': blocHashCode,
      'timestamp': timestamp.toIso8601String(),
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    };
  }

  @override
  String toString() {
    return toJson().toString();
  }
}

typedef DirectoryProvider = Future<Directory> Function();

/// TODO: optimize, don't create directory every time.
DirectoryProvider defaultDirectoryProvider = () async {
  /// TODO: optimize, don't create directory every time.
  final appDocumentsDir = await getApplicationDocumentsDirectory();
  final directoryPath = path.join(appDocumentsDir.path, 'bloc_remote_logger');
  return Directory(directoryPath);
};

DirectoryProvider testDirectoryProvider = () async {
  /// Root of the project.
  final currentDirectory = Directory.current;

  /// Temp directory in the test directory.
  return Directory('${currentDirectory.path}/test/temp')
      .create(recursive: true);
};

class SessionMetadata {
  SessionMetadata({
    required this.startedDate,
  });

  factory SessionMetadata.fromJson(Map<String, dynamic> json) {
    return SessionMetadata(
      startedDate: DateTime.parse(json['startedDate'] as String),
    );
  }

  final DateTime startedDate;

  Map<String, dynamic> toJson() {
    return {
      'startedDate': startedDate.toUtc().toIso8601String(),
    };
  }
}

class BlocMetadata {
  BlocMetadata({
    required this.id,
    required this.createdDate,
    required this.closedDate,
  });

  factory BlocMetadata.fromJson(Map<String, dynamic> json) {
    return BlocMetadata(
      id: json['id'] as String,
      createdDate: DateTime.tryParse(json['createdDate'] as String),
      closedDate: DateTime.tryParse(json['closedDate'] as String),
    );
  }

  final String id;
  final DateTime? createdDate;
  final DateTime? closedDate;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdDate': createdDate?.toUtc().toIso8601String() ?? '',
      'closedDate': closedDate?.toUtc().toIso8601String() ?? '',
    };
  }
}
