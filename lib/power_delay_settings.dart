import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'power_delay.dart';
import 'services.dart';

class PowerDelaySettings extends StatefulWidget {
  final DeviceStore store;
  const PowerDelaySettings({super.key, required this.store});

  @override
  State<PowerDelaySettings> createState() => _PowerDelaySettingsState();
}

class _PowerDelaySettingsState extends State<PowerDelaySettings> {
  final form = GlobalKey<FormState>();
  late final seconds = TextEditingController(
    text: '${widget.store.powerDelaySeconds}',
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    seconds.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.savePowerDelay(int.parse(seconds.text));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => error = 'Chưa lưu được. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thời gian chờ tắt / Sleep',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'Dùng chung cho Shutdown và Sleep trên các PC. Mỗi lần xác nhận lệnh, máy sẽ chờ khoảng thời gian này rồi tự thực hiện.',
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: seconds,
                enabled: !saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Thời gian chờ (giây)',
                  helperText: 'Từ 1 giây đến 86400 giây (24 giờ)',
                ),
                validator: (value) {
                  final number = int.tryParse(value ?? '');
                  return number != null && validPowerDelay(number)
                      ? null
                      : 'Nhập số từ 1 đến 86400.';
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in [10, 30, 60, 300])
                    ActionChip(
                      label: Text(powerDelayLabel(value)),
                      onPressed: saving ? null : () => seconds.text = '$value',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Áp dụng từ lần bấm tiếp theo; lệnh đang chờ giữ thời gian cũ. PC cần chạy Windows Agent bản hỗ trợ thời gian chờ tùy chỉnh.',
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Đang lưu…' : 'Lưu thời gian chờ'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
