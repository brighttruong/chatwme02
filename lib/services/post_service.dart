import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/comment_model.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';

class PostService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> createPost({
    required UserModel author,
    required String content,
    required String visibility,
  }) async {
    try {
      final docRef = _firestore.collection('posts').doc();
      await docRef.set({
        'postId': docRef.id,
        'authorId': author.uid,
        'authorName': author.displayName,
        'authorAvatar': author.avatarUrl,
        'content': content.trim(),
        'visibility': visibility,
        'likes': <String>[],
        'commentCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(
            'Kết nối tới máy chủ Firestore bị quá thời gian (Timeout). Vui lòng kiểm tra lại mạng Internet hoặc cấu hình Firebase.',
          );
        },
      );
      debugPrint('>>> [PostService] Tạo bài viết thành công ID: ${docRef.id}');
    } on FirebaseException catch (e) {
      debugPrint('>>> [PostService Error] Lỗi tạo bài viết: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        throw Exception(
          'Chưa có quyền ghi dữ liệu (permission-denied). Hãy đổi Rules trên Console thành allow read, write: if true;',
        );
      } else if (e.code == 'unavailable') {
        throw Exception(
          'Dịch vụ Firestore hiện không khả dụng (unavailable). Hãy kiểm tra mạng Internet.',
        );
      }
      throw Exception('Lỗi Firestore (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('>>> [PostService Error] Lỗi tạo bài viết: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Xóa bài viết khỏi Firestore
  Future<void> deletePost(String postId) async {
    try {
      await _firestore.collection('posts').doc(postId).delete().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Thao tác xóa bài viết quá thời gian (Timeout). Vui lòng kiểm tra kết nối mạng.');
        },
      );
      debugPrint('>>> [PostService] Đã xóa bài viết ID: $postId');
    } on FirebaseException catch (e) {
      debugPrint('>>> [PostService Error] Lỗi xóa bài viết: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        throw Exception('Không có quyền xóa bài viết (permission-denied). Kiểm tra Rules trên Console.');
      }
      throw Exception('Lỗi Firestore (${e.code}): ${e.message}');
    } catch (e) {
      debugPrint('>>> [PostService Error] Lỗi xóa bài viết: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Stream<List<PostModel>> getHomeFeedStream({
    required String currentUserId,
    required List<String> currentUserFriendIds,
  }) {
    return _firestore.collection('posts').snapshots().map((snapshot) {
      final posts = snapshot.docs
          .map((doc) => PostModel.fromMap(doc.data(), doc.id))
          .toList();

      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return posts.where((post) {
        if (post.authorId == currentUserId) return true;
        if (post.visibility == 'public') return true;
        if (post.visibility == 'friends' &&
            currentUserFriendIds.contains(post.authorId)) {
          return true;
        }
        return false;
      }).toList();
    }).handleError((error) {
      debugPrint('Lỗi Firestore getHomeFeedStream: $error');
      return <PostModel>[];
    }).asBroadcastStream();
  }

  Stream<List<PostModel>> getUserPostsStream(String uid) {
    return _firestore
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final posts = snapshot.docs
          .map((doc) => PostModel.fromMap(doc.data(), doc.id))
          .toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    }).handleError((error) {
      debugPrint('Lỗi Firestore getUserPostsStream: $error');
      return <PostModel>[];
    }).asBroadcastStream();
  }

  Future<void> toggleLike({
    required String postId,
    required String currentUserId,
    required bool isCurrentlyLiked,
  }) async {
    try {
      final docRef = _firestore.collection('posts').doc(postId);
      if (isCurrentlyLiked) {
        await docRef.update({
          'likes': FieldValue.arrayRemove([currentUserId])
        });
      } else {
        await docRef.update({
          'likes': FieldValue.arrayUnion([currentUserId])
        });
      }
    } catch (e) {
      debugPrint('Lỗi toggleLike: $e');
    }
  }

  Stream<List<CommentModel>> getCommentsStream(String postId) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .snapshots()
        .map((snapshot) {
      final comments = snapshot.docs
          .map((doc) => CommentModel.fromMap(doc.data(), doc.id))
          .toList();
      comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return comments;
    }).handleError((error) {
      debugPrint('Lỗi Firestore getCommentsStream: $error');
      return <CommentModel>[];
    }).asBroadcastStream();
  }

  Future<void> addComment({
    required String postId,
    required UserModel author,
    required String text,
  }) async {
    try {
      final batch = _firestore.batch();
      final commentRef = _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .doc();

      batch.set(commentRef, {
        'commentId': commentRef.id,
        'authorId': author.uid,
        'authorName': author.displayName,
        'authorAvatar': author.avatarUrl,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final postRef = _firestore.collection('posts').doc(postId);
      batch.update(postRef, {
        'commentCount': FieldValue.increment(1),
      });

      await batch.commit().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Gửi bình luận quá thời gian (Timeout).');
            },
          );
    } catch (e) {
      debugPrint('Lỗi addComment: $e');
      rethrow;
    }
  }
}
