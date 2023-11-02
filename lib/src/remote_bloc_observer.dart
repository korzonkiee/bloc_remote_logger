// ignore_for_file: public_member_api_docs, avoid_print

import 'dart:async';
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
    DirectoryProvider? directoryProvider,
  }) {
    _repository = _Repository(
      sessionId: const Uuid().v4(),
      apiKey: apiKey,
      directoryProvider: directoryProvider ?? defaultDirectoryProvider,
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
}

class _Repository {
  _Repository({
    required this.sessionId,
    required this.apiKey,
    required this.directoryProvider,
  }) {
    _createSessionMetadata();

    _streamSubscription = _streamController.stream
        .asyncMap(_handleChange)
        .listen((change) => print('Change handled $change'));
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
          sessionId: sessionId,
          startDate: DateTime.now(),
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

  // ignore: unused_field, cancel_subscriptions
  late final StreamSubscription<_Change> _streamSubscription;
  final StreamController<_Change> _streamController =
      StreamController<_Change>();

  /// saveChange
  Future<void> saveChange(_Change change) async {
    _streamController.add(change);
  }

  Future<_Change> _handleChange(_Change change) async {
    final directory = await directoryProvider();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final blocName = change.blocName;
    final blocHashCode = change.blocHashCode;

    final file = File(
      path.join(
        directory.path,
        '$apiKey/$sessionId/$blocName/$blocHashCode/state.txt',
      ),
    );

    // ignore: avoid_slow_async_io
    if (!(await file.exists())) {
      await file.create(recursive: true);
    }

    /// Keep the file open for writing.
    await file.writeAsString(
      change.diff(),
      mode: FileMode.append,
    );

    return change;
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
        'http://localhost:8080/files',
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
    required this.sessionId,
    required this.startDate,
  });

  factory SessionMetadata.fromJson(Map<String, dynamic> json) {
    return SessionMetadata(
      sessionId: json['sessionId'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
    );
  }

  final String sessionId;
  final DateTime startDate;

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'startDate': startDate.toIso8601String(),
    };
  }
}
