import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:yolx/common/const.dart';
import 'package:yolx/common/global.dart';
import 'package:yolx/generated/l10n.dart';
import 'package:yolx/model/download_list_model.dart';
import 'package:yolx/screens/downloading.dart';
import 'package:yolx/screens/waiting.dart';
import 'package:yolx/screens/stopped.dart';
import 'package:yolx/screens/settings.dart';
import 'package:fluent_ui/fluent_ui.dart' hide Page;
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:system_theme/system_theme.dart';
import 'package:url_launcher/link.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yolx/utils/aria2_manager.dart';
import 'package:yolx/utils/common_utils.dart';
import 'package:yolx/utils/log.dart';
import 'package:yolx/utils/permission_util.dart';

import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Global.init();
  if (!kIsWeb &&
      [
        TargetPlatform.windows,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform)) {
    SystemTheme.accentColor.load();
  }

  if (isDesktop) {
    if (!await FlutterSingleInstance.platform.isFirstInstance()) {
      Log.w("App is already running");
      exit(0);
    }

    await WindowManager.instance.ensureInitialized();
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setMinimumSize(const Size(400, 600));
      await windowManager
          .setSize(Size(Global.windowWidth, Global.windowHeight));
      if (Global.silentStart) {
        await windowManager.hide();
      } else {
        await windowManager.show();
      }
      await windowManager.setPreventClose(true);
      await windowManager.setSkipTaskbar(false);
    });
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/logo.ico' : 'assets/logo.png',
    );
    final strings = await S.load(Locale.fromSubtags(
        languageCode: Global.prefs.getString('Language') ?? 'en'));
    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: strings.showWindow,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: strings.exitApp,
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }
  if (Platform.isAndroid) {
    bool isGranted = await checkStoragePermission();
    if (!isGranted) {
      EasyLoading.showToast('没有存储权限');
      return;
    }
    SystemUiOverlayStyle style = const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    );
    SystemChrome.setSystemUIOverlayStyle(style);
  }
  await Aria2Manager().initAria2Conf();
  await Aria2Manager().startServer();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DownloadListModel()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: Global.appTheme,
      builder: (context, child) {
        final appTheme = context.watch<AppTheme>();
        return FluentApp.router(
          title: appTitle,
          themeMode: appTheme.mode,
          debugShowCheckedModeBanner: false,
          color: appTheme.color,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen(context) ? 2.0 : 0.0,
            ),
          ),
          theme: FluentThemeData(
            accentColor: appTheme.color,
            visualDensity: VisualDensity.standard,
            focusTheme: FocusThemeData(
              glowFactor: is10footScreen(context) ? 2.0 : 0.0,
            ),
          ),
          locale: appTheme.locale,
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          routeInformationProvider: router.routeInformationProvider,
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.child,
    required this.shellContext,
  });

  final Widget child;
  final BuildContext? shellContext;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with WindowListener, TrayListener {
  bool value = false;

  // int index = 0;

  final viewKey = GlobalKey(debugLabel: 'Navigation View Key');

  late final List<NavigationPaneItem> originalItems = [
    PaneItem(
      key: const ValueKey('/'),
      icon: const Icon(FluentIcons.download),
      title: Text(S.of(context).downloading),
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      key: const ValueKey('/waiting'),
      icon: const Icon(FluentIcons.pause),
      title: Text(S.of(context).waiting),
      body: const SizedBox.shrink(),
    ),
    PaneItem(
      key: const ValueKey('/stopped'),
      icon: const Icon(FluentIcons.stop),
      title: Text(S.of(context).stopped),
      body: const SizedBox.shrink(),
    ),
  ].map<NavigationPaneItem>((e) {
    PaneItem buildPaneItem(PaneItem item) {
      return PaneItem(
        key: item.key,
        icon: item.icon,
        title: item.title,
        body: item.body,
        onTap: () {
          final path = (item.key as ValueKey).value;
          if (GoRouterState.of(context).uri.toString() != path) {
            context.go(path);
          }
          item.onTap?.call();
        },
      );
    }

    if (e is PaneItemExpander) {
      return PaneItemExpander(
        key: e.key,
        icon: e.icon,
        title: e.title,
        body: e.body,
        items: e.items.map((item) {
          if (item is PaneItem) return buildPaneItem(item);
          return item;
        }).toList(),
      );
    }
    return buildPaneItem(e);
  }).toList();
  late final List<NavigationPaneItem> footerItems = [
    PaneItemSeparator(),
    PaneItem(
      key: const ValueKey('/settings'),
      icon: const Icon(FluentIcons.settings),
      title: Text(S.of(context).settings),
      body: const SizedBox.shrink(),
      onTap: () {
        if (GoRouterState.of(context).uri.toString() != '/settings') {
          context.go('/settings');
        }
      },
    ),
    _LinkPaneItemAction(
      icon: const Icon(FluentIcons.open_source),
      title: Text(S.of(context).sourceCode),
      link: githubURL,
      body: const SizedBox.shrink(),
    ),
  ];

  @override
  void initState() {
    windowManager.addListener(this);
    trayManager.addListener(this);
    Provider.of<DownloadListModel>(context, listen: false)
        .loadHistoryListFromJson();
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.show();
      windowManager.focus();
      showExitDialog();
    }
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int indexOriginal = originalItems
        .where((item) => item.key != null)
        .toList()
        .indexWhere((item) => item.key == Key(location));

    if (indexOriginal == -1) {
      int indexFooter = footerItems
          .where((element) => element.key != null)
          .toList()
          .indexWhere((element) => element.key == Key(location));
      if (indexFooter == -1) {
        return 0;
      }
      return originalItems
              .where((element) => element.key != null)
              .toList()
              .length +
          indexFooter;
    } else {
      return indexOriginal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.watch<AppTheme>();
    return NavigationView(
      key: viewKey,
      appBar: NavigationAppBar(
        automaticallyImplyLeading: false,
        title: () {
          return const DragToMoveArea(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(appTitle),
            ),
          );
        }(),
        actions: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (isDesktop) const WindowButtons(),
        ]),
      ),
      paneBodyBuilder: (item, child) {
        return widget.child;
      },
      pane: NavigationPane(
        size: const NavigationPaneSize(openMaxWidth: 214),
        selected: _calculateSelectedIndex(context),
        displayMode: appTheme.displayMode,
        indicator: () {
          switch (appTheme.indicator) {
            case NavigationIndicators.end:
              return const EndNavigationIndicator();
            case NavigationIndicators.sticky:
            default:
              return const StickyNavigationIndicator();
          }
        }(),
        items: originalItems,
        footerItems: footerItems,
      ),
    );
  }

  void showExitDialog() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose && mounted) {
      showDialog(
        context: context,
        builder: (_) {
          return ContentDialog(
            title: Text(S.of(context).confirmClose),
            content: Text(S.of(context).closeInfo),
            actions: [
              FilledButton(
                child: Text(S.of(context).yes),
                onPressed: () async {
                  Navigator.pop(context);
                  Provider.of<DownloadListModel>(context, listen: false)
                      .saveHistoryListToJson();
                  if (Global.rememberWindowSize) {
                    await windowManager.getSize().then((size) {
                      Global.prefs.setDouble('WindowWidth', size.width);
                      Global.prefs.setDouble('WindowHeight', size.height);
                    });
                  }
                  windowManager.destroy();
                  Aria2Manager().closeServer();
                },
              ),
              Button(
                child: Text(S.of(context).no),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void onWindowClose() {
    windowManager.hide();
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);

    return SizedBox(
      width: 138,
      height: 50,
      child: WindowCaption(
        brightness: theme.brightness,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}

class _LinkPaneItemAction extends PaneItem {
  _LinkPaneItemAction({
    required super.icon,
    required this.link,
    required super.body,
    super.title,
  });

  final String link;

  @override
  Widget build(
    BuildContext context,
    bool selected,
    VoidCallback? onPressed, {
    PaneDisplayMode? displayMode,
    bool showTextOnTop = true,
    bool? autofocus,
    int? itemIndex,
  }) {
    return Link(
      uri: Uri.parse(link),
      builder: (context, followLink) => Semantics(
        link: true,
        child: super.build(
          context,
          selected,
          followLink,
          displayMode: displayMode,
          showTextOnTop: showTextOnTop,
          itemIndex: itemIndex,
          autofocus: autofocus,
        ),
      ),
    );
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final router = GoRouter(navigatorKey: rootNavigatorKey, routes: [
  ShellRoute(
    navigatorKey: _shellNavigatorKey,
    builder: (context, state, child) {
      return MyHomePage(
        shellContext: _shellNavigatorKey.currentContext,
        child: child,
      );
    },
    routes: [
      /// Downloading
      GoRoute(path: '/', builder: (context, state) => const DownloadingPage()),

      /// Waiting
      GoRoute(
          path: '/waiting', builder: (context, state) => const WaitingPage()),

      /// Waiting
      GoRoute(
          path: '/stopped', builder: (context, state) => const StoppedPage()),

      /// Settings
      GoRoute(path: '/settings', builder: (context, state) => const Settings()),
    ],
  ),
]);
