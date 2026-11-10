import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wake_my_pc/agent_client.dart';
import 'package:wake_my_pc/main.dart';
import 'package:wake_my_pc/models.dart';
import 'package:wake_my_pc/services.dart';
import 'package:wake_my_pc/siri_shortcuts.dart';
import 'package:wake_my_pc/siri_setup.dart';
import 'package:wake_my_pc/siri_help.dart';
import 'package:wake_my_pc/workspace.dart';
import 'package:wake_my_pc/siri_background.dart';

class HomeSiriNetwork extends NetworkService {
  int wakes = 0;
  @override
  Future<Lan?> network() async => Lan('192.168.1.20', '255.255.255.0');
  @override
  Future<bool> reachable(String ip) async => false;
  @override
  Future<void> wake(Pc pc, Lan lan) async {
    wakes++;
  }
}

class HomeSiriAgent extends AgentClient {
  final commands = <String>[];
  String response = 'accepted';
  @override
  Future<String?> keyFor(String id) async => '0123456789abcdef0123456789abcdef';
  @override
  Future<String> command(Pc pc, String command) async {
    commands.add(command);
    if (command == 'status') return 'online';
    return command == 'cancel' ? 'cancelled' : response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platformCalls = <MethodCall>[];
  setUp(() {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          platformCalls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  for (final width in [320.0, 430.0]) {
    testWidgets(
      'workspace owns Siri setup and links to Help without PC commands at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SiriShortcuts.channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SiriShortcuts.channel,
            null,
          ),
        );
        SharedPreferences.setMockInitialValues({});
        final store = DeviceStore(await SharedPreferences.getInstance());
        await store.save([
          const Pc(
            id: 'studio',
            name: 'Studio PC',
            mac: 'A4:BB:6D:12:34:56',
            ip: '192.168.1.10',
            favorite: true,
            agentPaired: true,
          ),
        ]);
        final network = HomeSiriNetwork();
        final agent = HomeSiriAgent();
        await tester.pumpWidget(
          WakeApp(store: store, network: network, agentClient: agent),
        );
        await tester.pumpAndSettle();
        expect(find.text('Thiết lập Siri'), findsNothing);
        expect(find.byType(UiKitView), findsNothing);
        await tester.tap(find.byTooltip('Mở menu'));
        await tester.pumpAndSettle();
        final headerPosition = tester.getTopLeft(
          find.text('Không gian của bạn'),
        );
        final workspaceScroll = find.descendant(
          of: find.byKey(WorkspaceSheet.scrollKey),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Thiết lập Siri'),
          150,
          scrollable: workspaceScroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('Thiết lập Siri'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Không gian của bạn')),
          headerPosition,
        );
        expect(
          tester.widget<UiKitView>(find.byType(UiKitView)).viewType,
          SiriSetupCard.viewType,
        );
        final creations = platformCalls.where(
          (call) => call.method == 'create',
        );
        expect(creations, isNotEmpty);
        expect(
          creations.every(
            (call) =>
                (call.arguments as Map)['viewType'] == SiriSetupCard.viewType,
          ),
          isTrue,
        );
        expect(network.wakes, 0);
        expect(agent.commands.where((command) => command != 'status'), isEmpty);
        expect(store.history(), isEmpty);
        await tester.scrollUntilVisible(
          find.text('Hướng dẫn dùng Siri'),
          100,
          scrollable: workspaceScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hướng dẫn dùng Siri'));
        await tester.pumpAndSettle();
        expect(find.text('Hướng dẫn sử dụng'), findsOneWidget);
        expect(find.byType(SiriHelpContent), findsOneWidget);
        expect(find.text('Không gian của bạn'), findsNothing);
        expect(network.wakes, 0);
        expect(agent.commands.where((command) => command != 'status'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }
  testWidgets(
    'Home reloads history and clears manual status after background Siri',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
      });
      SharedPreferences.setMockInitialValues({});
      final store = DeviceStore(await SharedPreferences.getInstance());
      await store.save([
        const Pc(
          id: 'studio',
          name: 'Studio PC',
          mac: 'A4:BB:6D:12:34:56',
          ip: '192.168.1.10',
          favorite: true,
          agentPaired: true,
        ),
      ]);
      final network = HomeSiriNetwork();
      final agent = HomeSiriAgent();
      await tester.pumpWidget(
        WakeApp(store: store, network: network, agentClient: agent),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sleep'), findsOneWidget);
      await tester.tap(find.text('Đánh dấu PC đã tắt'));
      await tester.pumpAndSettle();
      expect(find.text('BẬT PC'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final session = SiriBackgroundSession(
        store: store,
        network: network,
        agent: agent,
      );
      final ticket = await session.shortcuts.handle(
        const MethodCall('prepare', {'action': 'wake'}),
      ) as Map;
      await session.shortcuts.handle(
        MethodCall('execute', {'ticket': ticket['ticket']}),
      );
      expect(find.text('BẬT PC'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Sleep'), findsOneWidget);
      expect(store.history().single, contains('Siri'));
      expect(store.read().single.lastWake, isNotNull);
      expect(network.wakes, 1);
      expect(agent.commands.where((command) => command != 'status'), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
