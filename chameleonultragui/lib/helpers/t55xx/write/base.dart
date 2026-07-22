import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/services.dart';

class BaseT55XXCardHelper extends AbstractWriteHelper {
  LFCardInfo? lfInfo;

  @override
  bool get autoDetect => true;

  @override
  String get name => "t55xx";

  static String get staticName => "t55xx";
  TextEditingController newKeyController = TextEditingController();
  TextEditingController currentKeyController = TextEditingController();
  String currentKey = "";
  String newKey = "";

  BaseT55XXCardHelper(super.communicator);

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      BaseT55XXCardHelper(communicator),
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [BaseT55XXCardHelper(communicator)];
  }

  @override
  Widget getWriteWidget(BuildContext context, setState) {
    var localizations = AppLocalizations.of(context)!;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Row(children: [
      Expanded(
          child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  TextFormField(
                    controller: currentKeyController,
                    decoration: InputDecoration(
                        labelText: localizations.key,
                        hintMaxLines: 4,
                        hintText: localizations
                            .enter_something(localizations.t55xx_key_prompt)),
                    inputFormatters: hexFormatter,
                    validator: (value) => validateHex(value, localizations,
                        exactBytes: 4, fieldName: localizations.key),
                  ),
                  TextFormField(
                    controller: newKeyController,
                    decoration: InputDecoration(
                        labelText: localizations.new_key,
                        hintMaxLines: 4,
                        hintText: localizations.enter_something(
                            localizations.t55xx_new_key_prompt)),
                    inputFormatters: hexFormatter,
                    validator: (value) => validateHex(value, localizations,
                        exactBytes: 4, fieldName: localizations.key),
                  )
                ],
              ))),
      TextButton(
        onPressed: () => {
          if (newKeyController.text.isNotEmpty)
            {
              if (currentKeyController.text.isNotEmpty)
                {
                  setState(() {
                    currentKey = currentKeyController.text;
                    newKey = newKeyController.text;
                  })
                }
              else
                {
                  setState(() {
                    currentKey = "20206666";
                    newKey = "20206666";
                  })
                }
            }
          else
            {
              if (currentKeyController.text.isNotEmpty)
                {
                  setState(() {
                    currentKey = currentKeyController.text;
                    newKey = currentKeyController.text;
                  })
                }
              else
                {
                  setState(() {
                    currentKey = "20206666";
                    newKey = "20206666";
                  })
                }
            }
        },
        child: Text(localizations.next),
      )
    ]);
  }

  @override
  Future<bool> isCompatible(CardSave card) async {
    return true;
  }

  @override
  Future<bool> isMagic(data) async {
    return false;
  }

  @override
  bool isReady() {
    return currentKey.length == 8 && newKey.length == 8;
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }

  @override
  Future<void> reset() async {
    currentKey = "";
    newKey = "";
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    if (isEM410X(card.tag)) {
      return _writeAndVerify(card.uid, update,
          () => communicator.writeEM410XtoT55XX(hexToBytes(card.uid),
              hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]),
          () => communicator.readEM410X());
    } else if (card.tag == TagType.hidProx) {
      return _writeAndVerify(card.uid, update,
          () => communicator.writeHIDProxToT55XX(hexToBytes(card.uid),
              hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]),
          () => communicator.readHIDProx());
    } else if (card.tag == TagType.viking) {
      return _writeAndVerify(card.uid, update,
          () => communicator.writeVikingToT55XX(hexToBytes(card.uid),
              hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]),
          () => communicator.readViking());
    } else if (card.tag == TagType.pac) {
      return _writeAndVerify(card.uid, update,
          () => communicator.writePacToT55XX(hexToBytes(card.uid),
              hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]),
          () => communicator.readPac());
    } else if (card.tag == TagType.ioProx) {
      return _writeAndVerify(card.uid, update,
          () => communicator.writeIoProxToT55XX(hexToBytes(card.uid),
              hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]),
          () => communicator.readIoProx());
    } else if (card.tag == TagType.idteck) {
      await communicator.writeIdteckToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), [hexToBytes(currentKey), Uint8List(4)]);
      // IDTECK read is not implemented, so this write cannot be verified.
      return false;
    }

    return false;
  }

  Future<bool> _writeAndVerify(
      String expected,
      Function(int writeProgress) update,
      Future<void> Function() write,
      Future<Object?> Function() read) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await write();
        await Future.delayed(const Duration(milliseconds: 500));
        final actual = await read();
        if (actual?.toString().toUpperCase() == expected.toUpperCase()) {
          update(100);
          return true;
        }
      } catch (_) {
        // A missed read is retried as a complete write/read attempt.
      }
      update(attempt * 100 ~/ 3);
    }
    return false;
  }
}
