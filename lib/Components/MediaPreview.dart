import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'UserPrefs.dart';

/// Что лежит по ссылке.
enum MediaKind { image, video, page, none }

class ResolvedMedia {
  final MediaKind kind;

  /// Прямая ссылка на картинку/видео (для image/video).
  final String? media;

  /// Превью-картинка (для video/page).
  final String? thumb;
  final String? title;
  final String? site;

  /// Страница с видео (YouTube и т.п.) — рисуем значок ▶ на превью.
  final bool playable;

  const ResolvedMedia(this.kind, {this.media, this.thumb, this.title, this.site, this.playable = false});

  static const none = ResolvedMedia(MediaKind.none);
}

/// Определяет тип ссылки. Результаты кэшируются на всё время работы приложения.
class MediaResolver {
  static final Map<String, Future<ResolvedMedia>> _cache = {};

  static const _imageExt = ['png', 'jpg', 'jpeg', 'apng', 'gif', 'webp', 'avif', 'bmp'];
  static const _videoExt = ['mp4', 'webm', 'mov', 'm4v'];
  static const _ua = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  static Future<ResolvedMedia> resolve(String url) => _cache.putIfAbsent(
        url,
        () => _resolve(url).timeout(const Duration(seconds: 10)).catchError((_) => ResolvedMedia.none),
      );

  static String _ext(Uri u) {
    final p = u.path.toLowerCase();
    final slash = p.lastIndexOf('/');
    final dot = p.lastIndexOf('.');
    return dot > slash ? p.substring(dot + 1) : '';
  }

  static String? _youtubeId(Uri u) {
    final host = u.host.replaceFirst('www.', '').replaceFirst('m.', '');
    if (host == 'youtu.be') return u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
    if (host == 'youtube.com' || host == 'music.youtube.com') {
      if (u.queryParameters['v'] != null) return u.queryParameters['v'];
      final seg = u.pathSegments;
      if (seg.length >= 2 && (seg[0] == 'shorts' || seg[0] == 'live' || seg[0] == 'embed')) return seg[1];
    }
    return null;
  }

  static Future<ResolvedMedia> _resolve(String url) async {
    final u = Uri.parse(url);
    final ext = _ext(u);

    if (_imageExt.contains(ext)) return ResolvedMedia(MediaKind.image, media: url);
    if (ext == 'gifv') return ResolvedMedia(MediaKind.video, media: url.replaceFirst(RegExp(r'\.gifv', caseSensitive: false), '.mp4'));
    if (_videoExt.contains(ext)) return ResolvedMedia(MediaKind.video, media: url);

    // DearKing mod: сайты-SPA без og-тегов (страница пустая без JavaScript) — прямые правила
    final known = await _knownSite(u);
    if (known != null) return known;

    final yt = _youtubeId(u);
    if (yt != null) {
      String? title;
      try {
        final r = await http.get(Uri.parse('https://www.youtube.com/oembed?format=json&url=${Uri.encodeComponent(url)}'));
        if (r.statusCode == 200) title = jsonDecode(utf8.decode(r.bodyBytes))['title'];
      } catch (_) {}
      return ResolvedMedia(MediaKind.page, thumb: 'https://i.ytimg.com/vi/$yt/hqdefault.jpg', title: title, site: 'YouTube', playable: true);
    }

    // Ссылка без расширения (kappa.lol/AbCd, i.nuuls.com/xyz, страницы) — смотрим, что отдаёт сервер.
    final client = http.Client();
    try {
      final req = http.Request('GET', u)..headers['User-Agent'] = _ua;
      final res = await client.send(req);
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.startsWith('image/')) return ResolvedMedia(MediaKind.image, media: url);
      if (ct.startsWith('video/')) return ResolvedMedia(MediaKind.video, media: url);
      if (!ct.contains('html')) return ResolvedMedia.none;

      // читаем только начало страницы — мета-теги в <head>
      final bytes = <int>[];
      await for (final chunk in res.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 256 * 1024) break;
      }
      final html = utf8.decode(bytes, allowMalformed: true);
      String? meta(String name) {
        final a = RegExp('<meta[^>]+(?:property|name)=["\']$name["\'][^>]*content=["\']([^"\']+)', caseSensitive: false).firstMatch(html);
        final b = RegExp('<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']$name["\']', caseSensitive: false).firstMatch(html);
        final v = (a ?? b)?.group(1);
        return v == null ? null : _unescape(v);
      }

      String? abs(String? v) => v == null ? null : u.resolve(v).toString();
      final image = abs(meta('og:image') ?? meta('twitter:image') ?? meta('og:image:url'));
      final video = abs(meta('og:video:secure_url') ?? meta('og:video:url') ?? meta('og:video'));
      final title = meta('og:title') ?? meta('twitter:title') ?? RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim();
      final site = meta('og:site_name') ?? u.host.replaceFirst('www.', '');

      if (video != null && _videoExt.contains(_ext(Uri.parse(video)))) {
        return ResolvedMedia(MediaKind.video, media: video, thumb: image, title: title, site: site);
      }
      if (image == null && title == null) return ResolvedMedia.none;
      return ResolvedMedia(MediaKind.page, thumb: image, title: title == null ? null : _unescape(title), site: site, playable: video != null);
    } finally {
      client.close();
    }
  }

  static Future<ResolvedMedia?> _knownSite(Uri u) async {
    final host = u.host.toLowerCase().replaceFirst('www.', '');
    final seg = u.pathSegments.where((x) => x.isNotEmpty).toList();

    // 7tv.app/emotes/<id> → сама картинка эмоута (анимированный WebP)
    if ((host == '7tv.app' || host == 'old.7tv.app') && seg.length >= 2 && seg[0] == 'emotes') {
      return ResolvedMedia(MediaKind.image, media: 'https://cdn.7tv.app/emote/${seg[1]}/4x.webp');
    }
    // betterttv.com/emotes/<id>
    if (host == 'betterttv.com' && seg.length >= 2 && seg[0] == 'emotes') {
      return ResolvedMedia(MediaKind.image, media: 'https://cdn.betterttv.net/emote/${seg[1]}/3x');
    }
    // frankerfacez.com/emoticon/<id>-<name>
    if (host == 'frankerfacez.com' && seg.length >= 2 && seg[0] == 'emoticon') {
      final id = seg[1].split('-').first;
      if (int.tryParse(id) != null) return ResolvedMedia(MediaKind.image, media: 'https://cdn.frankerfacez.com/emote/$id/4');
    }
    // imgur.com/<id> (без расширения) → i.imgur.com/<id>.jpg (imgur сам отдаёт нужный формат)
    if (host == 'imgur.com' && seg.length == 1 && RegExp(r'^[A-Za-z0-9]{5,8}$').hasMatch(seg[0])) {
      return ResolvedMedia(MediaKind.image, media: 'https://i.imgur.com/${seg[0]}.jpg');
    }
    // x.com / twitter.com — через публичный API fxtwitter (картинки, GIF, видео)
    if ((host == 'x.com' || host == 'twitter.com' || host == 'mobile.twitter.com') && seg.length >= 3 && seg[1] == 'status') {
      try {
        final r = await http.get(Uri.parse('https://api.fxtwitter.com/${seg[0]}/status/${seg[2]}'));
        final t = jsonDecode(utf8.decode(r.bodyBytes))['tweet'];
        final media = t?['media'];
        final text = '${t?['author']?['name'] ?? seg[0]}: ${t?['text'] ?? ''}';
        final videos = media?['videos'] as List?;
        if (videos != null && videos.isNotEmpty) {
          return ResolvedMedia(MediaKind.video, media: videos.first['url'], thumb: videos.first['thumbnail_url'], title: text, site: 'X');
        }
        final photos = media?['photos'] as List?;
        if (photos != null && photos.isNotEmpty) return ResolvedMedia(MediaKind.image, media: photos.first['url']);
        return ResolvedMedia(MediaKind.page, title: text, site: 'X');
      } catch (_) {
        return null;
      }
    }
    // kick.com/<канал>/clips/... и прочее — пойдёт общим путём (og-теги)
    return null;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

/// Картинка с уменьшенным декодированием: меньше памяти и лагов (GIF анимируются как обычно).
ImageProvider _thumbProvider(String url, {int height = 360}) => ResizeImage(
      CachedNetworkImageProvider(url),
      height: height,
      allowUpscaling: false,
      policy: ResizeImagePolicy.fit,
    );

/// Превью под сообщением: картинка/GIF, видео (кадр + ▶) или карточка страницы.
class MediaPreview extends StatelessWidget {
  final String url;

  const MediaPreview({Key? key, required this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) => FutureBuilder<ResolvedMedia>(
        future: MediaResolver.resolve(url),
        builder: (context, snap) {
          final m = snap.data;
          if (m == null || m.kind == MediaKind.none) return const SizedBox.shrink();
          switch (m.kind) {
            case MediaKind.image:
              return _frame(
                context,
                onTap: () => MediaViewer.open(context, url: url, media: m),
                child: Image(
                  image: _thumbProvider(m.media!),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              );
            case MediaKind.video:
              return _frame(
                context,
                onTap: () => MediaViewer.open(context, url: url, media: m),
                child: _VideoThumb(media: m),
              );
            case MediaKind.page:
              return _PageCard(url: url, media: m);
            case MediaKind.none:
              return const SizedBox.shrink();
          }
        },
      );

  Widget _frame(BuildContext context, {required Widget child, required VoidCallback onTap}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180, maxWidth: 300, minHeight: 40, minWidth: 40),
              child: child,
            ),
          ),
        ),
      );
}

class _VideoThumb extends StatelessWidget {
  final ResolvedMedia media;
  const _VideoThumb({required this.media});

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          if (media.thumb != null)
            Image(image: _thumbProvider(media.thumb!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 240, height: 135, color: Colors.black))
          else
            Container(width: 240, height: 135, color: Colors.black),
          Container(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
          ),
        ],
      );
}

class _PageCard extends StatelessWidget {
  final String url;
  final ResolvedMedia media;
  const _PageCard({required this.url, required this.media});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Material(
          color: theme.colorScheme.onSurface.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (media.thumb != null)
                  SizedBox(
                    width: 112,
                    height: 63,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image(image: _thumbProvider(media.thumb!, height: 160), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                        if (media.playable) const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28)),
                      ],
                    ),
                  ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (media.site != null) Text(media.site!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                        if (media.title != null) Text(media.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Полноэкранный просмотр: картинка с зумом или видеоплеер.
class MediaViewer extends StatelessWidget {
  final String url;
  final ResolvedMedia media;

  const MediaViewer({Key? key, required this.url, required this.media}) : super(key: key);

  static Future<void> open(BuildContext context, {required String url, required ResolvedMedia media}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MediaViewer(url: url, media: media)));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: tr('Copy link', 'Копировать ссылку'),
              icon: const Icon(Icons.link),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(tr('Link copied', 'Ссылка скопирована'))));
                }
              },
            ),
            IconButton(
              tooltip: tr('Open in browser', 'Открыть в браузере'),
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        body: Center(
          child: media.kind == MediaKind.video
              ? _VideoView(url: media.media!)
              : InteractiveViewer(
                  maxScale: 6,
                  child: Image(
                    image: CachedNetworkImageProvider(media.media!),
                    fit: BoxFit.contain,
                    loadingBuilder: (c, child, p) => p == null ? child : const CircularProgressIndicator(),
                    errorBuilder: (_, __, ___) => Text(tr('Failed to load', 'Не удалось загрузить'), style: const TextStyle(color: Colors.white)),
                  ),
                ),
        ),
      );
}

class _VideoView extends StatefulWidget {
  final String url;
  const _VideoView({required this.url});

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool failed = false;

  @override
  void initState() {
    super.initState();
    c.setLooping(true);
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      c.play();
    }).catchError((_) {
      if (mounted) setState(() => failed = true);
    });
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (failed) return Text(tr('Failed to play video', 'Не удалось воспроизвести видео'), style: const TextStyle(color: Colors.white));
    if (!c.value.isInitialized) return const CircularProgressIndicator();
    return GestureDetector(
      onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(c),
                if (!c.value.isPlaying) const Icon(Icons.play_arrow, color: Colors.white70, size: 64),
              ],
            ),
          ),
          VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 12)),
        ],
      ),
    );
  }
}
