import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';

class ChatService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String _getChatRoomId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '${uid1}_$uid2' : '${uid2}_$uid1';
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    final roomId = _getChatRoomId(senderId, receiverId);
    await _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<MessageModel>> getMessagesStream(
    String currentUid,
    String friendUid,
  ) {
    final roomId = _getChatRoomId(currentUid, friendUid);
    return _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
      messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return messages;
    }).handleError((error) {
      debugPrint('Lỗi Firestore getMessagesStream: $error');
      return <MessageModel>[];
    }).asBroadcastStream();
  }
}
