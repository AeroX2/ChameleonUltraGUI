import 'package:chameleonultragui/helpers/lf_tuning.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LfTuningMenu extends StatefulWidget {
  const LfTuningMenu({super.key});

  @override
  State<LfTuningMenu> createState() => _LfTuningMenuState();
}

class _LfTuningMenuState extends State<LfTuningMenu> {
  LfTuneStatus? _status;
  LfTuneSweep? _sweep;
  int? _selectedKHz;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await _run(() async {
      final communicator = context.read<ChameleonGUIState>().communicator!;
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      final status = await communicator.getLfTune();
      if (mounted) {
        setState(() {
          _status = status;
          _selectedKHz = status.frequencyKHz;
        });
      }
    });
  }

  Future<void> _scan() async {
    await _run(() async {
      final result = await context
          .read<ChameleonGUIState>()
          .communicator!
          .sweepLfTune();
      if (mounted) {
        setState(() {
          _sweep = result;
          _selectedKHz = result.strongest?.frequencyKHz;
        });
      }
    });
  }

  Future<void> _apply(bool persist) async {
    final frequency = _selectedKHz;
    if (frequency == null) return;
    await _run(() async {
      final status = await context
          .read<ChameleonGUIState>()
          .communicator!
          .setLfTune(frequency, persist: persist);
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted)
      setState(() {
        _busy = true;
        _error = null;
      });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strongest = _sweep?.strongest;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.multiline_chart),
          SizedBox(width: 10),
          Text('LF antenna tuning'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _status == null
                    ? 'Reading carrier setting…'
                    : 'Current carrier: ${_status!.frequencyKHz} kHz '
                          '(actual ${(_status!.actualFrequencyHz / 1000).toStringAsFixed(3)} kHz)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan without a tag first. The strongest envelope is a starting point; '
                'place the tag normally and confirm reliable reads before saving.',
              ),
              const SizedBox(height: 20),
              if (_sweep != null) ...[
                _ResonanceTrace(
                  sweep: _sweep!,
                  selectedKHz: _selectedKHz,
                  onSelected: (value) => setState(() => _selectedKHz = value),
                ),
                const SizedBox(height: 10),
                Text(
                  strongest == null
                      ? 'No samples captured'
                      : 'Peak envelope: ${strongest.frequencyKHz} kHz · mean ${strongest.mean}',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.radar),
          label: const Text('Scan antenna'),
        ),
        TextButton(
          onPressed: _busy || _selectedKHz == null ? null : () => _apply(false),
          child: const Text('Apply'),
        ),
        FilledButton(
          onPressed: _busy || _selectedKHz == null ? null : () => _apply(true),
          child: const Text('Apply & save'),
        ),
      ],
    );
  }
}

class _ResonanceTrace extends StatelessWidget {
  final LfTuneSweep sweep;
  final int? selectedKHz;
  final ValueChanged<int> onSelected;

  const _ResonanceTrace({
    required this.sweep,
    required this.selectedKHz,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final maxMean = sweep.points.fold<int>(
      1,
      (value, point) => point.mean > value ? point.mean : value,
    );
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: sweep.points.map((point) {
          final selected = point.frequencyKHz == selectedKHz;
          return Expanded(
            child: InkWell(
              onTap: () => onSelected(point.frequencyKHz),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 118 * point.mean / maxMean,
                        width: selected ? 14 : 9,
                        decoration: BoxDecoration(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.tertiary.withValues(alpha: 0.65),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  point.frequencyKHz % 5 == 0
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${point.frequencyKHz}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        )
                      : const SizedBox(height: 21),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
