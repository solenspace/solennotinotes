import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:noti_notes_app/app/logging_bloc_observer.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_bloc.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_event.dart';
import 'package:noti_notes_app/features/home/screen.dart';
import 'package:noti_notes_app/features/inbox/cubit/inbox_badge_cubit.dart';
import 'package:noti_notes_app/features/inbox/screen.dart';
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
import 'package:noti_notes_app/repositories/received_inbox/hive_received_inbox_repository.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/screens/manage_ai_screen.dart';
import 'package:noti_notes_app/repositories/settings/hive_settings_repository.dart';
import 'package:noti_notes_app/repositories/settings/settings_repository.dart';
import 'package:noti_notes_app/services/ai/llama_cpp_llm_runtime.dart';
import 'package:noti_notes_app/services/ai/llm_runtime.dart';
import 'package:noti_notes_app/services/ai/model_downloader.dart';
import 'package:noti_notes_app/services/ai/whisper_cpp_runtime.dart';
import 'package:noti_notes_app/services/ai/whisper_runtime.dart';
import 'package:noti_notes_app/services/crypto/flutter_secure_keypair_service.dart';
import 'package:noti_notes_app/services/crypto/keypair_service.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_probe.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';
import 'package:noti_notes_app/services/share/channel_peer_service.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';
import 'package:noti_notes_app/services/speech/stt_capability_probe.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';
import 'package:noti_notes_app/services/speech/tts_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    Bloc.observer = const LoggingBlocObserver();
  }

  final notesRepository = HiveNotesRepository();
  final keypairService = FlutterSecureKeypairService();
  final notiIdentityRepository = HiveNotiIdentityRepository(keypairService: keypairService);
  final settingsRepository = HiveSettingsRepository();
  final audioRepository = FileSystemAudioRepository();
  final receivedInboxRepository = HiveReceivedInboxRepository(notesRepository: notesRepository);
  await notesRepository.init();
  await notiIdentityRepository.init();
  await receivedInboxRepository.init();
  // Inbox decoder needs the documents root synchronously when the inbox
  // route mounts; resolve it once here so the screen never blocks on a
  // platform channel during build.
  await primeInboxDocumentsRoot();
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

  // Spec 22: P2P transport, opt-in per session. The service starts no
  // listener at construction — the share UI calls start()/stop() around
  // its sheet. PermissionsService is shared with the rest of the app.
  const permissions = PluginPermissionsService();
  final peerService = ChannelPeerService(permissions: permissions);

  runApp(
    MyApp(
      notesRepository: notesRepository,
      notiIdentityRepository: notiIdentityRepository,
      settingsRepository: settingsRepository,
      audioRepository: audioRepository,
      deviceCapabilityService: deviceCapabilityService,
      sttService: sttService,
      ttsService: ttsService,
      keypairService: keypairService,
      peerService: peerService,
      receivedInboxRepository: receivedInboxRepository,
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
    required this.keypairService,
    required this.peerService,
    required this.receivedInboxRepository,
  });

  final NotesRepository notesRepository;
  final NotiIdentityRepository notiIdentityRepository;
  final SettingsRepository settingsRepository;
  final AudioRepository audioRepository;
  final DeviceCapabilityService deviceCapabilityService;
  final SttService sttService;
  final TtsService ttsService;
  final KeypairService keypairService;
  final PeerService peerService;
  final ReceivedInboxRepository receivedInboxRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    Future<void>.delayed(Duration.zero).then(
      (_) {
        LocalNotificationService.setup(notificationResponse).asStream().listen(
              (event) => notificationResponse,
            );
      },
    );
    super.initState();
  }

  void notificationResponse(NotificationResponse response) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
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
        RepositoryProvider<KeypairService>.value(value: widget.keypairService),
        RepositoryProvider<PeerService>.value(value: widget.peerService),
        RepositoryProvider<ReceivedInboxRepository>.value(
          value: widget.receivedInboxRepository,
        ),
        // Specs 19 + 21: stateless model downloader, the one authorised
        // network surface. Both `LlmReadinessCubit` and (Spec 21)
        // `WhisperReadinessCubit` resolve this single instance — each
        // cubit injects its own `ModelDownloadSpec` so the downloader
        // stays model-agnostic.
        RepositoryProvider<ModelDownloader>.value(
          value: const ModelDownloader(),
        ),
        // Spec 20: shared on-device LLM runtime. One worker isolate is
        // shared across the editor's `AiAssistCubit` and any future
        // surface (Spec 21 audio transcription). Stateful — singleton
        // for the app lifetime.
        RepositoryProvider<LlmRuntime>(
          create: (_) => LlamaCppLlmRuntime(),
          dispose: (runtime) => runtime.unload(),
        ),
        // Spec 21: shared on-device Whisper runtime. One worker isolate
        // is reused across every `TranscriptionCubit` (one per
        // long-pressed audio block). Stateful — singleton for the app
        // lifetime, torn down via `dispose`.
        RepositoryProvider<WhisperRuntime>(
          create: (_) => WhisperCppRuntime(),
          dispose: (runtime) => runtime.unload(),
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
          // Spec 25: app-shell badge cubit. Subscribes to the inbox
          // repository's watch stream so the home AppBar reflects new
          // arrivals even when the inbox screen is not mounted.
          BlocProvider(
            create: (ctx) => InboxBadgeCubit(
              repository: ctx.read<ReceivedInboxRepository>(),
            )..start(),
          ),
          // Spec 20: hoisted from `SettingsScreen` so the editor's ✦
          // button can read the same readiness state without re-probing
          // disk on every open. `bootstrap()` is idempotent — the row
          // paints "ready" on first frame for users who already
          // downloaded on a previous run.
          BlocProvider(
            create: (ctx) => LlmReadinessCubit(
              downloader: ctx.read<ModelDownloader>(),
            )..bootstrap(),
          ),
          // Spec 21: hoisted next to LLM readiness so the editor's
          // audio-block "Transcribe" affordance and the settings
          // "Voice transcription" tile read the same readiness state.
          // The tier is read once at construction (architecture
          // decision #7); UI must additionally check
          // `aiTier.canRunWhisper` before rendering, since the cubit
          // would throw `StateError` for `AiTier.unsupported`.
          BlocProvider(
            create: (ctx) {
              final tier = ctx.read<DeviceCapabilityService>().aiTier;
              if (!tier.canRunWhisper) {
                // Cubit factory still must return a cubit; we hand back
                // an idle one without bootstrap so it never resolves a
                // spec. UI gates ensure no consumer reads its state.
                return WhisperReadinessCubit(
                  downloader: ctx.read<ModelDownloader>(),
                  tier: AiTier.compact,
                );
              }
              return WhisperReadinessCubit(
                downloader: ctx.read<ModelDownloader>(),
                tier: tier,
              )..bootstrap();
            },
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
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const HomeScreen(),
              routes: {
                HomeScreen.routeName: (context) => const HomeScreen(),
                NoteEditorScreen.routeName: (context) => const NoteEditorScreen(),
                UserInfoScreen.routeName: (context) => const UserInfoScreen(),
                SettingsScreen.routeName: (context) => const SettingsScreen(),
                ManageAiScreen.routeName: (context) => const ManageAiScreen(),
                InboxScreen.routeName: (context) => const InboxScreen(),
              },
            );
          },
        ),
      ),
    );
  }
}
