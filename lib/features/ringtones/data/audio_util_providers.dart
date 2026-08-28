import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audio_util_service.dart';

/// Public access to the shared [AudioUtilService].
///
/// Tests override this with a fake service so the cutter UI and its state can
/// be exercised without a real Android method channel.
final audioUtilServiceProvider = Provider<AudioUtilService>(
  (ref) => MethodChannelAudioUtilService(),
);
