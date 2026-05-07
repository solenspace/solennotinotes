import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:noti_notes_app/app/logging_bloc_observer.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_bloc.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_event.dart';
import 'package:noti_notes_app/features/home/screen.dart';
import 'package:noti_notes_app/features/note_editor/screen.dart';
import 'package:noti_notes_app/features/search/cubit/search_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/theme_state.dart';
import 'package:noti_notes_app/features/settings/screen.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_cubit.dart';
import 'package:noti_notes_app/features/user_info/screen.dart';
import 'package:noti_notes_app/repositories/audio/audio_repository.dart';
import 'package:noti_notes_app/repositories/audio/file_system_audio_repository.dart';
import 'package:noti_notes_app/repositories/notes/hive_notes_repository.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/repositories/noti_identity/hive_noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/settings/hive_settings_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/services/ai/llm_model_downloader.dart';
import 'package:noti_notes_app/services/device/device_capability_probe.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/services/speech/stt_capability_probe.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';
import 'package:noti_notes_app/services/speech/tts_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    Bloc.observer = const LoggingBlocObserver();
  }

  final notesRepository = HiveNotesRepository();
  final notiIdentityRepository = HiveNotiIdentityRepository();
  final settingsRepository = HiveSettingsRepository();
  final audioRepository = FileSystemAudioRepository();
  await notesRepository.init();
  await notiIdentityRepository.init();
  // Settings init runs AFTER identity init so the one-shot
  // `appThemeColor → signaturePalette[2]` migration can read+update the
  // identity record.
  await settingsRepository.init(identityRepository: notiIdentityRepository);

  // Cold-start device-capability probe (Spec 17). Runs before the STT
  // probe so the cap cache is the single source of truth for OS / arch /
  // RAM going forward. Cached values short-circuit the plugin handshake
  // on subsequent cold starts; an OS-version change re-probes
  // automatically.
  final deviceCapabilityService =
      await const DeviceCapabilityProbe().probe(settings: settingsRepository);

  // Cold-start STT capability probe (Spec 15). The probe is conservative —
  // any failure path resolves false so the dictation UI hides itself rather
  // than risk a network fallback. Result is cached in `settings_v2` so
  // subsequent cold starts skip the plugin handshake.
  final sttOfflineCapable = await const SttCapabilityProbe().probe();
  await settingsRepository.setSttOfflineCapable(sttOfflineCapable);
  final sttService = PluginSttService(isOfflineCapable: sttOfflineCapable);

  // TTS has no cold-start probe — `flutter_tts` self-initializes lazily on
  // the first `speak()` call, and the OS-bundled voices are uniformly
  // available offline (unlike STT, where Android's offline recognizer is
  // patchy). See architecture.md decision 29.
  final ttsService = PluginTtsService();

  runApp(
    MyApp(
      notesRepository: notesRepository,
      notiIdentityRepository: notiIdentityRepository,
      settingsRepository: settingsRepository,
      audioRepository: audioRepository,
      deviceCapabilityService: deviceCapabilityService,
      sttService: sttService,
      ttsService: ttsService,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.notesRepository,
    required this.notiIdentityRepository,
    required this.settingsRepository,
    required this.audioRepository,
    required this.deviceCapabilityService,
    required this.sttService,
    required this.ttsService,
  });

  final NotesRepository notesRepository;
  final NotiIdentityRepository notiIdentityRepository;
  final SettingsRepository settingsRepository;
  final AudioRepository audioRepository;
  final DeviceCapabilityService deviceCapabilityService;
  final SttService sttService;
  final TtsService ttsService;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(Duration.zero).then(
      (_) {
        LocalNotificationService.setup(notificationResponse).asStream().listen(
              (event) => notificationResponse,
            );
      },
    );
    super.initState();
  }

  void notificationResponse(NotificationResponse response) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteEditorScreen(noteId: response.payload),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<NotesRepository>.value(value: widget.notesRepository),
        RepositoryProvider<NotiIdentityRepository>.value(
          value: widget.notiIdentityRepository,
        ),
        RepositoryProvider<SettingsRepository>.value(value: widget.settingsRepository),
        RepositoryProvider<AudioRepository>.value(value: widget.audioRepository),
        RepositoryProvider<DeviceCapabilityService>.value(
          value: widget.deviceCapabilityService,
        ),
        RepositoryProvider<SttService>.value(value: widget.sttService),
        RepositoryProvider<TtsService>.value(value: widget.ttsService),
        RepositoryProvider<PermissionsService>.value(
          value: const PluginPermissionsService(),
        ),
        // Spec 19: stateless downloader. Cubit lifecycle is owned by the
        // settings screen (not at app root) so the download stream is only
        // open while the user is on that surface.
        RepositoryProvider<LlmModelDownloader>.value(
          value: const LlmModelDownloader(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (ctx) => ThemeCubit(
              settingsRepository: ctx.read<SettingsRepository>(),
              identityRepository: ctx.read<NotiIdentityRepository>(),
            )..start(),
          ),
          BlocProvider(
            create: (ctx) => NotesListBloc(repository: ctx.read<NotesRepository>())
              ..add(const NotesListSubscribed()),
          ),
          BlocProvider(create: (_) => SearchCubit()),
          BlocProvider(
            create: (ctx) => NotiIdentityCubit(
              repository: ctx.read<NotiIdentityRepository>(),
            )..load(),
          ),
        ],
        child: BlocBuilder<ThemeCubit, ThemeState>(
          buildWhen: (a, b) =>
              a.themeMode != b.themeMode ||
              a.boneTheme != b.boneTheme ||
              a.darkTheme != b.darkTheme,
          builder: (context, state) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'NotiNotes',
              theme: state.boneTheme,
              darkTheme: state.darkTheme,
              themeMode: state.themeMode,
              home: const HomeScreen(),
              routes: {
                HomeScreen.routeName: (context) => const HomeScreen(),
                NoteEditorScreen.routeName: (context) => const NoteEditorScreen(),
                UserInfoScreen.routeName: (context) => const UserInfoScreen(),
                SettingsScreen.routeName: (context) => const SettingsScreen(),
              },
            );
          },
        ),
      ),
    );
  }
}
