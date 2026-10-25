import 'dart:ffi';
import 'dart:io';

/// Quits the app like [exit], but on Windows without running the libraries'
/// shutdown code: flutter_inappwebview's static destructor crashes there
/// (releasing a DirectComposition object once its threads are gone), and
/// Windows Error Reporting then kept the frozen window on screen for seconds.
///
/// Skipping it loses nothing: [exit] doesn't wait for anything on the Dart side
/// either, and SQLite doesn't rely on it to keep its data.
Never exitApp([int code = 0]) {
  if (Platform.isWindows) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess = kernel32
        .lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
    final terminateProcess = kernel32
        .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
    );
    terminateProcess(getCurrentProcess(), code);
  }
  exit(code);
}
