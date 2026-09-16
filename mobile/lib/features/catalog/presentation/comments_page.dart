import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/cached_media_image.dart';
import '../../../core/network/api_exception.dart';
import '../domain/catalog_models.dart';

final class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.kind,
    required this.publicId,
    required this.title,
  });
  final String kind;
  final String publicId;
  final String title;

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

final class _CommentsPageState extends State<CommentsPage> {
  late Future<List<ContentComment>> _future;
  final _body = TextEditingController();
  bool _loaded = false;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _future = AppScope.of(context)
          .loadContentComments(kind: widget.kind, publicId: widget.publicId);
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _reload() => setState(
    () =>
        _future = AppScope.of(context)
            .loadContentComments(kind: widget.kind, publicId: widget.publicId),
  );

  Future<void> _add() async {
    if (_body.text.trim().isEmpty) return;
    if (AppScope.of(context).session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سجّل الدخول لإضافة تعليق.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await AppScope.of(context).addContentComment(
        kind: widget.kind,
        publicId: widget.publicId,
        body: _body.text,
      );
      _body.clear();
      _reload();
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ContentComment comment) async {
    final own =
        AppScope.of(context).session?.user['public_id'] ==
        comment.authorPublicId;
    final admin = AppScope.of(context).session?.roles.contains('admin') == true;
    if (!own && !admin) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف التعليق؟'),
        content: const Text('سيختفي التعليق من العرض العام.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AppScope.of(context).deleteContentComment(comment.publicId);
      _reload();
    } on ApiException catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('تعليقات ${widget.title}')),
    body: Column(
      children: [
        Expanded(
          child: FutureBuilder<List<ContentComment>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError)
                return Center(
                  child: FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                );
              final comments = snapshot.data ?? const [];
              if (comments.isEmpty)
                return const Center(
                  child: Text('لا توجد تعليقات بعد. كن أول من يعلّق.'),
                );
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                itemCount: comments.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final comment = comments[index];
                  final mayDelete =
                      AppScope.of(context).session?.user['public_id'] ==
                          comment.authorPublicId ||
                      AppScope.of(context).session?.roles.contains('admin') ==
                          true;
                  return Card(
                    child: ListTile(
                      leading: _CommentAvatar(
                        name: comment.authorName,
                        mediaPublicId: comment.authorAvatarMediaPublicId,
                        isAdmin: comment.authorIsAdmin,
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              comment.authorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (comment.authorIsAdmin)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: 6),
                              child: Chip(
                                label: Text('مدير'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(comment.body),
                      ),
                      trailing: mayDelete
                          ? IconButton(
                              tooltip: 'حذف',
                              onPressed: () => _delete(comment),
                              icon: const Icon(Icons.delete_outline_rounded),
                            )
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _body,
                    maxLength: 1500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'اكتب تعليقاً محترماً…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _add,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


final class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.name, required this.mediaPublicId, required this.isAdmin});
  final String name;
  final String? mediaPublicId;
  final bool isAdmin;

  String get _initial {
    final clean = name.trim();
    return clean.isEmpty ? 'م' : clean.substring(0, 1);
  }

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: 23,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.primary,
        child: ClipOval(
          child: SizedBox.square(
            dimension: 46,
            child: mediaPublicId?.trim().isNotEmpty == true
                ? CachedMediaImage(mediaPublicId: mediaPublicId!)
                : Center(
                    child: Text(
                      _initial,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
          ),
        ),
      );
}
