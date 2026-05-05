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
import 'package:noti_notes_app/features/settings/screen.dart';
import 'package:noti_notes_app/features/user_info/cubit/noti_identity_cubit.dart';
import 'package:noti_notes_app/features/user_info/screen.dart';
import 'package:noti_notes_app/repositories/notes/hive_notes_repository.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/repositories/noti_identity/hive_noti_identity_repository.dart';
import 'package:noti_notes_app/repositories/noti_identity/noti_identity_repository.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/theme_provider.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    Bloc.observer = const LoggingBlocObserver();
  }

  final notesRepository = HiveNotesRepository();
  final notiIdentityRepository = HiveNotiIdentityRepository();
  await notesRepository.init();
  await notiIdentityRepository.init();
  await ThemeProvider.ensureBoxOpen();

  runApp(
    MyApp(
      notesRepository: notesRepository,
      notiIdentityRepository: notiIdentityRepository,
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.notesRepository,
    required this.notiIdentityRepository,
  });

  final NotesRepository notesRepository;
  final NotiIdentityRepository notiIdentityRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final ThemeProvider themeProvider;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    themeProvider = ThemeProvider()..load();

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
      ],
      // TODO(spec-10-theme-tokens): migrate ThemeProvider to a ThemeBloc/Cubit
      // and remove the `provider` package along with this ChangeNotifierProvider.
      child: ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MultiBlocProvider(
          providers: [
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
          child: Consumer<ThemeProvider>(
            builder: (context, theme, _) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'NotiNotes',
                theme: AppTheme.light(theme.writingFont, theme.appColor),
                darkTheme: AppTheme.dark(theme.writingFont, theme.appColor),
                themeMode: theme.themeMode,
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
      ),
    );
  }
}
