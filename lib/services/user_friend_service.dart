import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/friend_request_model.dart';
import '../models/user_model.dart';
import 'auth_service.dart';

class UserFriendService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Stream<UserModel?> getUserProfileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        final currentAuthUser = AuthService().currentUser;
        return UserModel(
          uid: uid,
          email: currentAuthUser?.email ?? '',
          displayName: currentAuthUser?.displayName ?? 'Thành viên',
          avatarUrl: '',
          bio: 'Xin chào! Tôi là thành viên mới.',
          friendIds: [],
        );
      }
      return UserModel.fromMap(doc.data()!, doc.id);
    }).handleError((error) {
      debugPrint('Lỗi Firestore getUserProfileStream: $error');
      final currentAuthUser = AuthService().currentUser;
      return UserModel(
        uid: uid,
        email: currentAuthUser?.email ?? '',
        displayName: currentAuthUser?.displayName ??
            (currentAuthUser?.email?.split('@').first ?? 'Thành viên'),
        avatarUrl: '',
        bio: 'Xin chào! Tôi là thành viên mới.',
        friendIds: [],
      );
    }).asBroadcastStream();
  }

  /// Tự động chuyển đổi URL Google Drive thành đường dẫn ảnh trực tiếp
  static String formatDriveImageUrl(String url) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return '';

    if (cleanUrl.contains('drive.google.com')) {
      final RegExp regExp = RegExp(r'(?:file/d/|id=)([\w-]+)');
      final match = regExp.firstMatch(cleanUrl);
      if (match != null && match.groupCount >= 1) {
        final fileId = match.group(1);
        if (fileId != null && fileId.isNotEmpty) {
          return 'https://lh3.googleusercontent.com/d/$fileId';
        }
      }
    }
    return cleanUrl;
  }

  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String bio,
    required String avatarUrl,
  }) async {
    final formattedAvatarUrl = formatDriveImageUrl(avatarUrl);

    // 1. Cập nhật trong collection 'users'
    await _firestore.collection('users').doc(uid).set({
      'displayName': displayName.trim(),
      'bio': bio.trim(),
      'avatarUrl': formattedAvatarUrl,
    }, SetOptions(merge: true));

    // 2. Đồng bộ avatar & tên mới vào tất cả bài viết của tác giả trong 'posts'
    try {
      final postsQuery = await _firestore
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .get();

      if (postsQuery.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in postsQuery.docs) {
          batch.update(doc.reference, {
            'authorName': displayName.trim(),
            'authorAvatar': formattedAvatarUrl,
          });
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Lỗi đồng bộ avatar sang các bài viết: $e');
    }
  }

  Stream<List<UserModel>> getFriendsListStream(List<String> friendIds) {
    if (friendIds.isEmpty) {
      return Stream.value(<UserModel>[]).asBroadcastStream();
    }
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => friendIds.contains(doc.id))
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    }).handleError((error) {
      debugPrint('Lỗi getFriendsListStream: $error');
      return <UserModel>[];
    }).asBroadcastStream();
  }

  Stream<List<FriendRequestModel>> getIncomingRequestsStream(String currentUid) {
    return _firestore
        .collection('friend_requests')
        .where('receiverId', isEqualTo: currentUid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FriendRequestModel.fromMap(doc.data(), doc.id))
            .where((req) => req.status == 'pending')
            .toList())
        .handleError((error) {
      debugPrint('Lỗi getIncomingRequestsStream: $error');
      return <FriendRequestModel>[];
    }).asBroadcastStream();
  }

  Future<List<UserModel>> searchUsers(String currentUid, String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final snapshot = await _firestore.collection('users').get();
      final lowercaseQuery = query.toLowerCase().trim();

      return snapshot.docs
          .where((doc) => doc.id != currentUid)
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .where((u) =>
              u.displayName.toLowerCase().contains(lowercaseQuery) ||
              u.email.toLowerCase().contains(lowercaseQuery))
          .toList();
    } catch (e) {
      debugPrint('Lỗi searchUsers: $e');
      return [];
    }
  }

  Future<void> sendFriendRequest({
    required UserModel sender,
    required String receiverId,
  }) async {
    await _firestore.collection('friend_requests').add({
      'senderId': sender.uid,
      'senderName': sender.displayName,
      'senderAvatar': sender.avatarUrl,
      'receiverId': receiverId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptFriendRequest(FriendRequestModel req) async {
    final batch = _firestore.batch();

    final reqRef = _firestore.collection('friend_requests').doc(req.requestId);
    batch.update(reqRef, {'status': 'accepted'});

    final senderRef = _firestore.collection('users').doc(req.senderId);
    batch.set(senderRef, {
      'friendIds': FieldValue.arrayUnion([req.receiverId])
    }, SetOptions(merge: true));

    final receiverRef = _firestore.collection('users').doc(req.receiverId);
    batch.set(receiverRef, {
      'friendIds': FieldValue.arrayUnion([req.senderId])
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> rejectFriendRequest(String requestId) async {
    await _firestore.collection('friend_requests').doc(requestId).delete();
  }
}
