import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/comment_model.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/post_service.dart';
import '../../services/user_friend_service.dart';
import '../../widgets/user_avatar.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  void _showCreatePostDialog(BuildContext context, UserModel currentUser) {
    final contentController = TextEditingController();
    String selectedVisibility = 'public';
    bool isPosting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Đăng bài viết mới'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    enabled: !isPosting,
                    decoration: const InputDecoration(
                      hintText: 'Bạn đang nghĩ gì thế?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quyền hiển thị bài viết:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'public',
                        icon: Icon(Icons.public, size: 18),
                        label: Text('Công khai'),
                      ),
                      ButtonSegment(
                        value: 'friends',
                        icon: Icon(Icons.group, size: 18),
                        label: Text('Bạn bè'),
                      ),
                    ],
                    selected: {selectedVisibility},
                    onSelectionChanged: isPosting
                        ? null
                        : (newSelection) {
                            setDialogState(() {
                              selectedVisibility = newSelection.first;
                            });
                          },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isPosting ? null : () => Navigator.pop(ctx),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: isPosting
                      ? null
                      : () async {
                          if (contentController.text.trim().isEmpty) return;

                          setDialogState(() => isPosting = true);

                          try {
                            await PostService().createPost(
                              author: currentUser,
                              content: contentController.text,
                              visibility: selectedVisibility,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            setDialogState(() => isPosting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().replaceAll('Exception: ', ''),
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                          }
                        },
                  child: isPosting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Đăng bài'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAuthUser = AuthService().currentUser;
    if (currentAuthUser == null) return const SizedBox.shrink();
    final currentUid = currentAuthUser.uid;

    final userService = UserFriendService();
    final postService = PostService();

    return StreamBuilder<UserModel?>(
      stream: userService.getUserProfileStream(currentUid),
      builder: (context, userSnapshot) {
        final currentUser = userSnapshot.data ??
            UserModel(
              uid: currentUid,
              email: currentAuthUser.email ?? '',
              displayName: currentAuthUser.displayName ??
                  (currentAuthUser.email?.split('@').first ?? 'Thành viên'),
            );

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'ChatWMe Feed',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCreatePostDialog(context, currentUser),
            icon: const Icon(Icons.edit_note),
            label: const Text('Đăng bài'),
          ),
          body: StreamBuilder<List<PostModel>>(
            stream: postService.getHomeFeedStream(
              currentUserId: currentUser.uid,
              currentUserFriendIds: currentUser.friendIds,
            ),
            builder: (context, postSnapshot) {
              if (postSnapshot.connectionState == ConnectionState.waiting &&
                  !postSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final posts = postSnapshot.data ?? [];
              if (posts.isEmpty) {
                return const Center(
                  child: Text(
                    'Chưa có bài viết nào.\nHãy đăng bài đầu tiên hoặc kết bạn thêm!',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  return PostCardWidget(
                    post: posts[index],
                    currentUser: currentUser,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class PostCardWidget extends StatelessWidget {
  final PostModel post;
  final UserModel currentUser;

  const PostCardWidget({
    super.key,
    required this.post,
    required this.currentUser,
  });

  void _openCommentSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CommentBottomSheet(
        postId: post.postId,
        currentUser: currentUser,
      ),
    );
  }

  void _confirmDeletePost(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Xác nhận xóa bài viết'),
          content: const Text(
            'Bạn có chắc chắn muốn xóa bài viết này không? Hành động này không thể hoàn tác.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await PostService().deletePost(post.postId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã xóa bài viết thành công!'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Không thể xóa bài viết: ${e.toString().replaceAll('Exception: ', '')}',
                        ),
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  }
                }
              },
              child: const Text('Xóa bài'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLiked = post.isLikedBy(currentUser.uid);
    final isMyPost = post.authorId == currentUser.uid;
    final timeStr = DateFormat('dd/MM/yyyy HH:mm').format(post.createdAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RealtimeUserAvatar(
                  uid: post.authorId,
                  fallbackAvatarUrl: post.authorAvatar,
                  fallbackName: post.authorName,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            post.visibility == 'public'
                                ? Icons.public
                                : Icons.group,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            post.visibility == 'public'
                                ? 'Công khai'
                                : 'Bạn bè',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isMyPost)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'delete') {
                        _confirmDeletePost(context);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Xóa bài viết',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.content,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const Divider(height: 24),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    PostService().toggleLike(
                      postId: post.postId,
                      currentUserId: currentUser.uid,
                      isCurrentlyLiked: isLiked,
                    );
                  },
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : null,
                  ),
                  label: Text('${post.likes.length} Thích'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: () => _openCommentSheet(context),
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('${post.commentCount} Bình luận'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CommentBottomSheet extends StatefulWidget {
  final String postId;
  final UserModel currentUser;

  const CommentBottomSheet({
    super.key,
    required this.postId,
    required this.currentUser,
  });

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet> {
  final _commentController = TextEditingController();
  final _postService = PostService();
  bool _isSending = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      await _postService.addComment(
        postId: widget.postId,
        author: widget.currentUser,
        text: text,
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể gửi bình luận: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(14.0),
              child: Text(
                'Bình luận bài viết',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<CommentModel>>(
                stream: _postService.getCommentsStream(widget.postId),
                builder: (context, snapshot) {
                  final comments = snapshot.data ?? [];
                  if (comments.isEmpty) {
                    return const Center(
                      child: Text('Chưa có bình luận nào. Hãy viết bình luận đầu tiên!'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final c = comments[index];
                      return ListTile(
                        leading: RealtimeUserAvatar(
                          uid: c.authorId,
                          fallbackAvatarUrl: c.authorAvatar,
                          fallbackName: c.authorName,
                          radius: 16,
                        ),
                        title: Text(
                          c.authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(c.text),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      enabled: !_isSending,
                      decoration: const InputDecoration(
                        hintText: 'Viết bình luận...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _isSending ? null : _sendComment,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
