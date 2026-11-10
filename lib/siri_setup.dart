import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The native Apple button opens the app's preconfigured actions in Shortcuts.
/// It does not run any of them or silently create personal voice shortcuts.
class SiriSetupCard extends StatelessWidget {
  static const viewType = 'wake_my_pc/siri_setup_button';
  final VoidCallback showHelp;

  const SiriSetupCard({super.key, required this.showHelp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Thiết lập Siri',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Mở 4 hành động có sẵn của Wake My PC trong Shortcuts.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: UiKitView(
              key: ValueKey(dark),
              viewType: viewType,
              creationParams: {'dark': dark},
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
          TextButton(
            onPressed: showHelp,
            child: const Text('Câu lệnh & quyền truy cập'),
          ),
        ],
      ),
    );
  }
}
