import 'package:flutter/material.dart';

const accent = Color(0xFF2563EB);
const navy = Color(0xFF101B2D);
const mint = Color(0xFF67E8F9);
const muted = Color(0xFF63758B);
const soft = Color(0xFFE8F0FF);
const uiFont = 'BeVietnamPro';
const panelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF182D47), Color(0xFF0C1729)],
);

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color, background;
  final double size;
  const IconTile(
    this.icon, {
    super.key,
    this.color = accent,
    this.background = soft,
    this.size = 48,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, color: color, size: size * .48),
  );
}

class PcIllustration extends StatelessWidget {
  const PcIllustration({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 164,
    child: Center(
      child: SizedBox(
        width: 250,
        height: 164,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 158,
              height: 158,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .08),
                  width: 1,
                ),
              ),
            ),
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .13),
              ),
            ),
            Positioned(
              top: 28,
              child: Transform.rotate(
                angle: -.065,
                child: Container(
                  width: 156,
                  height: 100,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF20354D),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFF587895)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 25,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF286BB4), Color(0xFF142D46)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        color: mint,
                        size: 42,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 21,
              child: Container(
                width: 8,
                height: 17,
                color: const Color(0xFF587895),
              ),
            ),
            Positioned(
              bottom: 18,
              child: Container(
                width: 62,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF587895),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Positioned(
              right: 14,
              top: 12,
              child: IconTile(
                Icons.bolt_rounded,
                background: mint,
                color: navy,
                size: 38,
              ),
            ),
            const Positioned(
              left: 13,
              bottom: 27,
              child: IconTile(
                Icons.wifi_rounded,
                background: Color(0xFF20354D),
                color: Color(0xFF7DD3FC),
                size: 34,
              ),
            ),
            const Positioned(
              left: 36,
              top: 23,
              child: Icon(Icons.add, color: Color(0xFF508EBE), size: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title, subtitle;
  const SectionTitle(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(color: muted, height: 1.5)),
      const SizedBox(height: 24),
    ],
  );
}

class SetupStepper extends StatelessWidget {
  final int step;
  const SetupStepper({super.key, required this.step});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            'BƯỚC ${step + 1} / 5',
            style: const TextStyle(
              color: accent,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            ['Kết nối', 'Chuẩn bị', 'Tìm máy', 'Thông tin', 'Hoàn tất'][step],
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: List.generate(
          5,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 4 ? 0 : 7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 5,
                decoration: BoxDecoration(
                  color: i <= step ? accent : const Color(0xFFDCE5EF),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 26),
    ],
  );
}

class WakeOrb extends StatelessWidget {
  final bool success, busy;
  const WakeOrb({super.key, required this.success, required this.busy});
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 204,
      height: 204,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 202,
            height: 202,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFDCE5EF)),
            ),
          ),
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: soft.withValues(alpha: .65),
            ),
          ),
          if (busy)
            const SizedBox(
              width: 168,
              height: 168,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent,
                strokeCap: StrokeCap.round,
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: success ? const Color(0xFF138268) : navy,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x222563EB),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Icon(
              success ? Icons.check_rounded : Icons.power_settings_new_rounded,
              color: mint,
              size: 58,
            ),
          ),
        ],
      ),
    ),
  );
}
