import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:noti_notes_app/features/home/legacy/notes_provider.dart';
import 'package:noti_notes_app/features/home/screen.dart';
import 'package:noti_notes_app/features/note_editor/screen.dart';
import 'package:noti_notes_app/features/search/legacy/search_provider.dart';
import 'package:noti_notes_app/features/settings/screen.dart';
import 'package:noti_notes_app/features/user_info/legacy/user_data_provider.dart';
import 'package:noti_notes_app/features/user_info/screen.dart';
import 'package:noti_notes_app/helpers/database_helper.dart';
import 'package:noti_notes_app/repositories/notes/hive_notes_repository.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/theme_provider.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notesRepository = HiveNotesRepository();
  await notesRepository.init();
  await DbHelper.initBox(DbHelper.userBoxName);
  await ThemeProvider.ensureBoxOpen();

  runApp(MyApp(notesRepository: notesRepository));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.notesRepository});

  final NotesRepository notesRepository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final UserData userData;
  late final ThemeProvider themeProvider;

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    userData = UserData();
    themeProvider = ThemeProvider()..load();
    userData.loadUserFromDataBase();
    if (userData.curentUserData.name != '') {
      userData.randomGreetings(userData.curentUserData);
    }

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
    return MultiProvider(
      providers: [
        Provider<NotesRepository>.value(value: widget.notesRepository),
        ChangeNotifierProvider(create: (_) => userData),
        ChangeNotifierProvider(
          create: (ctx) {
            final notes = Notes(repository: ctx.read<NotesRepository>());
            notes.loadNotesFromDataBase().then((_) => notes.sortByDateCreated());
            return notes;
          },
        ),
        ChangeNotifierProvider(create: (_) => Search()),
        ChangeNotifierProvider.value(value: themeProvider),
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
    );
  }
}
