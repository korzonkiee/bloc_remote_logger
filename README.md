# Bloc Remote Logger

## Getting started

1. Request login credentials from @korzonkiee.
2. Sign in to the [Bloc Remote Logs Viewer](https://korzonkiee.github.io/) website.
3. Tap "Add project" button.
4. Enter project's name, e.g. "My application".
5. Tap "Copy project key" button.
6. Add `bloc_remote_logger` to `pubspec.yaml`
    ```yaml
    dependencies:
        bloc_remote_logger:
            git: https://github.com/korzonkiee/bloc_remote_logger
    ```
7. Run `flutter packages get`.
8. Register `RemoteBlocObserver`
    ```dart
    Bloc.observer = RemoteBlocObserver(
        projectKey: '<project-key>',
    );
    ```

    if you already have a custom instance of BlocObserver assigned, let's call it `AppBlocObserver`, then you can extend `RemoteBlocObserver` instead of `BlocObserver`. Make sure to override `onCreate`, `onChange`, `onEvent`, `onError` and `onClose` and call `super.method()` in each override.

    ```dart
    class AppBlocObserver extends RemoteBlocObserver {
      AppBlocObserver({
        super.projectKey = '<project-key>',
      });

      @override
      void onCreate(BlocBase<dynamic> bloc) {
        /// ...
        super.onCreate(bloc);
      }

      @override
      void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
        /// ...
        super.onChange(bloc, change);
      }

      @override
      void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
        /// ...
        super.onEvent(bloc, event);
      }

      @override
      void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
        /// ...
        super.onError(bloc, error, stackTrace);
      }

      @override
      void onClose(BlocBase<dynamic> bloc) {
        /// ...
        super.onClose(bloc);
      }
    }
    ```
9. Restart the app and generate some events, state or errors.
10. Logs are be uploaded on the next app launch. In the future they may be stream in the real-time.
11. Use [Bloc Remote Logs Viewer](https://korzonkiee.github.io/) website to browse through logs.