import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chatsen_irc/Twitch.dart' as twitch;
import 'package:http/http.dart' as http;

import '/Components/ChatInputBox.dart';
import '/Components/UserPrefs.dart';

/// Хостинг для загрузки картинок/GIF/видео.
class UploadHost {
  final String id;
  final String name;
  final Future<_UploadResult> Function(PlatformFile file) upload;

  const UploadHost(this.id, this.name, this.upload);
}

class _UploadResult {
  final String link;
  final String? deleteLink;
  const _UploadResult(this.link, {this.deleteLink});
}

/// DearKing mod: загрузка файла с телефона на kappa.lol / i.nuuls.com / catbox.moe.
/// Готовая ссылка вставляется в поле ввода (можно дописать текст и отправить).
class UploadModal extends StatefulWidget {
  static const imageExtensions = <String>['jpg', 'jpeg', 'png', 'gif', 'apng', 'webp', 'bmp'];

  static final hosts = <UploadHost>[
    UploadHost('kappa', 'kappa.lol', _kappa),
    UploadHost('nuuls', 'i.nuuls.com', _nuuls),
    UploadHost('catbox', 'catbox.moe', _catbox),
  ];

  final PlatformFile file;
  final twitch.Channel channel;

  const UploadModal({Key? key, required this.file, required this.channel}) : super(key: key);

  // Форматы ответов — как в настройках загрузчика Chatterino (wiki.chatterino.com/Image Uploader).
  static Future<_UploadResult> _kappa(PlatformFile f) async {
    final req = http.MultipartRequest('POST', Uri.parse('https://kappa.lol/api/upload'))..files.add(http.MultipartFile.fromBytes('file', f.bytes!, filename: f.name));
    final res = await req.send();
    final body = await res.stream.bytesToString();
    if (res.statusCode != 200) throw 'kappa.lol: HTTP ${res.statusCode} $body';
    final j = jsonDecode(body);
    final link = '${j['link']}';
    final ext = '${j['ext'] ?? ''}';
    return _UploadResult(link.endsWith(ext) ? link : '$link$ext', deleteLink: j['delete']?.toString());
  }

  static Future<_UploadResult> _nuuls(PlatformFile f) async {
    final req = http.MultipartRequest('POST', Uri.parse('https://i.nuuls.com/upload'))..files.add(http.MultipartFile.fromBytes('attachment', f.bytes!, filename: f.name));
    final res = await req.send();
    final body = (await res.stream.bytesToString()).trim();
    if (res.statusCode != 200 || !body.startsWith('http')) throw 'i.nuuls.com: HTTP ${res.statusCode} $body';
    return _UploadResult(body);
  }

  static Future<_UploadResult> _catbox(PlatformFile f) async {
    final req = http.MultipartRequest('POST', Uri.parse('https://catbox.moe/user/api.php'))
      ..fields['reqtype'] = 'fileupload'
      ..files.add(http.MultipartFile.fromBytes('fileToUpload', f.bytes!, filename: f.name));
    final res = await req.send();
    final body = (await res.stream.bytesToString()).trim();
    if (res.statusCode != 200 || !body.startsWith('http')) throw 'catbox.moe: HTTP ${res.statusCode} $body';
    return _UploadResult(body);
  }

  static Future<void> show(BuildContext context, {required twitch.Channel channel}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: Platform.isIOS ? FileType.image : FileType.media, // картинки, GIF и видео из галереи
        withData: true,
      );
      if (result == null || result.files.isEmpty || !context.mounted) return;
      await showChatsenSheet(context, (_) => UploadModal(file: result.files.first, channel: channel));
    } catch (e) {
      debugPrint('$e');
    }
  }

  @override
  State<UploadModal> createState() => _UploadModalState();
}

class _UploadModalState extends State<UploadModal> {
  late String hostId = UserPrefs.instance.uploadHost;
  bool uploading = false;
  String? error;

  String get ext {
    final n = widget.file.name.toLowerCase();
    return n.contains('.') ? n.split('.').last : '';
  }

  String get sizeText {
    final b = widget.file.size;
    if (b > 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _upload() async {
    final host = UploadModal.hosts.firstWhere((h) => h.id == hostId, orElse: () => UploadModal.hosts.first);
    await UserPrefs.instance.setUploadHost(host.id);
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      final r = await host.upload(widget.file);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final input = ChatInputBoxState.of(widget.channel);
      Navigator.of(context).pop();
      if (input != null) {
        input.insertText(r.link);
      } else {
        widget.channel.send(r.link);
      }
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(input != null ? tr('Uploaded — link added to the message', 'Загружено — ссылка добавлена в сообщение') : tr('Uploaded and sent', 'Загружено и отправлено')),
        action: r.deleteLink == null
            ? null
            : SnackBarAction(
                label: tr('Copy delete link', 'Ссылка на удаление'),
                onPressed: () => Clipboard.setData(ClipboardData(text: r.deleteLink!)),
              ),
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          uploading = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = UploadModal.imageExtensions.contains(ext) && widget.file.bytes != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: Image.memory(widget.file.bytes!, fit: BoxFit.contain),
              ),
            )
          else
            ListTile(leading: const Icon(Icons.movie_outlined), title: Text(widget.file.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 8),
          Text('${widget.file.name} · $sizeText', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Text(tr('Upload to', 'Куда загрузить'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final h in UploadModal.hosts)
                ChoiceChip(
                  label: Text(h.name),
                  selected: hostId == h.id,
                  onSelected: uploading ? null : (_) => setState(() => hostId = h.id),
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: uploading ? null : _upload,
            icon: uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
            label: Text(uploading ? tr('Uploading…', 'Загрузка…') : tr('Upload', 'Загрузить')),
          ),
        ],
      ),
    );
  }
}
