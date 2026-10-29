import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Stream lắng nghe thay đổi trạng thái đăng nhập
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Lấy thông tin user hiện tại từ Firebase Auth
  User? get currentUser => _auth.currentUser;

  /// Kiểm tra xem email / tài khoản đã tồn tại chưa
  Future<bool> checkAccountExists(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) return false;

    try {
      // 1. Kiểm tra trong Cloud Firestore collection 'users'
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .get();

      if (userQuery.docs.isNotEmpty) {
        return true;
      }

      // 2. Kiểm tra trong Firebase Auth
      // final methods = await _auth.fetchSignInMethodsForEmail(cleanEmail);
      // if (methods.isNotEmpty) {
      //   return true;
      // }
    } catch (e) {
      debugPrint('>>> [checkAccountExists] Lỗi khi kiểm tra tài khoản: $e');
    }

    return false;
  }

  /// Đăng ký tài khoản mới bằng Email/Password
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      // Kiểm tra tài khoản đã tồn tại chưa
      final exists = await checkAccountExists(email);
      if (exists) {
        throw Exception('Địa chỉ email này đã được sử dụng bởi một tài khoản khác.');
      }

      // 1. Tạo tài khoản trong Firebase Authentication
      final credential = await _auth
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Đăng ký quá thời gian. Kiểm tra lại mạng Internet.'),
          );

      final user = credential.user;
      if (user != null) {
        // 2. Cập nhật tên hiển thị trong Firebase Auth Profile
        await user.updateDisplayName(displayName.trim());

        // 3. Lưu thông tin hồ sơ người dùng vào Cloud Firestore ('users' collection)
        try {
          await _firestore.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'email': email.trim(),
            'displayName': displayName.trim(),
            'avatarUrl': '',
            'bio': 'Xin chào! Tôi là thành viên mới.',
            'friendIds': <String>[],
            'createdAt': FieldValue.serverTimestamp(),
          }).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('>>> [Firestore Timeout] Đã hết thời gian lưu user doc');
            },
          );
          debugPrint('>>> [Firestore Success] Đã ghi thành công user ${user.uid} vào collection "users"');
        } on FirebaseException catch (e) {
          debugPrint('>>> [Firestore Error] Lỗi ghi user vào Firestore: ${e.code} - ${e.message}');
          throw Exception(_handleFirestoreException(e));
        }
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } on FirebaseException catch (e) {
      throw Exception(_handleFirestoreException(e));
    } catch (e) {
      throw Exception('Đã xảy ra lỗi khi đăng ký: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  /// Đăng nhập tài khoản bằng Email/Password
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth
          .signInWithEmailAndPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Đăng nhập quá thời gian. Kiểm tra lại mạng Internet.'),
          );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } on FirebaseException catch (e) {
      throw Exception(_handleFirestoreException(e));
    } catch (e) {
      throw Exception('Đã xảy ra lỗi khi đăng nhập: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  /// Đăng xuất tài khoản
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Gửi email đặt lại mật khẩu
  Future<void> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw Exception('Vui lòng nhập địa chỉ email của bạn.');
    }
    try {
      await _auth.sendPasswordResetEmail(email: cleanEmail).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Thao tác gửi email quá thời gian. Kiểm tra lại mạng Internet.'),
          );
    } on FirebaseAuthException catch (e) {
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception('Lỗi gửi email đặt lại mật khẩu: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  /// Xóa vĩnh viễn tài khoản người dùng khỏi Firebase
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;

    final uid = user.uid;

    try {
      // 1. Xóa thông tin người dùng trong collection 'users'
      try {
        await _firestore.collection('users').doc(uid).delete().timeout(
          const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('>>> [deleteAccount] Lỗi khi xóa user doc: $e');
      }

      // 2. Xóa các bài viết của người dùng này trong collection 'posts'
      try {
        final postsQuery = await _firestore
            .collection('posts')
            .where('authorId', isEqualTo: uid)
            .get();
        if (postsQuery.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in postsQuery.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('>>> [deleteAccount] Lỗi khi xóa bài viết của user: $e');
      }

      // 3. Xóa các lời mời kết bạn liên quan trong 'friend_requests'
      try {
        final reqSent = await _firestore
            .collection('friend_requests')
            .where('senderId', isEqualTo: uid)
            .get();
        final reqReceived = await _firestore
            .collection('friend_requests')
            .where('receiverId', isEqualTo: uid)
            .get();

        if (reqSent.docs.isNotEmpty || reqReceived.docs.isNotEmpty) {
          final batchReq = _firestore.batch();
          for (final doc in reqSent.docs) {
            batchReq.delete(doc.reference);
          }
          for (final doc in reqReceived.docs) {
            batchReq.delete(doc.reference);
          }
          await batchReq.commit();
        }
      } catch (e) {
        debugPrint('>>> [deleteAccount] Lỗi khi xóa friend requests: $e');
      }

      // 4. Xóa tài khoản khỏi Firebase Authentication
      await user.delete().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Thao tác xóa tài khoản quá thời gian.'),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception(
          'Vì lý do bảo mật, bạn cần đăng xuất và đăng nhập lại gần đây trước khi thực hiện xóa tài khoản.',
        );
      }
      throw Exception(_handleAuthException(e));
    } catch (e) {
      throw Exception(
        'Không thể xóa tài khoản: ${e.toString().replaceAll('Exception: ', '')}',
      );
    }
  }

  String _handleFirestoreException(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Lỗi Firestore (permission-denied): Chưa được cấp quyền ghi dữ liệu. Hãy chỉnh Rules thành allow read, write: if true;';
      case 'not-found':
        return 'Lỗi Firestore (not-found): Database Firestore chưa được khởi tạo trên Firebase Console.';
      case 'unavailable':
        return 'Lỗi Firestore (unavailable): Dịch vụ Firestore hiện không khả dụng. Vui lòng kiểm tra kết nối mạng.';
      default:
        return 'Lỗi dữ liệu Firestore (${e.code}): ${e.message}';
    }
  }

  /// Xử lý các mã lỗi Firebase Auth thành thông báo tiếng Việt dễ hiểu
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Định dạng email không hợp lệ.';
      case 'user-disabled':
        return 'Tài khoản này đã bị vô hiệu hóa.';
      case 'user-not-found':
        return 'Không tìm thấy tài khoản tương ứng với email này.';
      case 'wrong-password':
        return 'Mật khẩu không chính xác.';
      case 'email-already-in-use':
        return 'Địa chỉ email này đã được sử dụng bởi một tài khoản khác.';
      case 'weak-password':
        return 'Mật khẩu quá yếu. Vui lòng sử dụng mật khẩu có ít nhất 6 ký tự.';
      case 'invalid-credential':
        return 'Thông tin đăng nhập không chính xác (mật khẩu sai hoặc email chưa đúng).';
      case 'too-many-requests':
        return 'Quá nhiều lần thử đăng nhập thất bại. Vui lòng thử lại sau.';
      case 'operation-not-allowed':
        return 'Chưa bật Email/Password trên Firebase Console (Authentication > Sign-in method).';
      case 'network-request-failed':
        return 'Lỗi kết nối mạng. Vui lòng kiểm tra lại kết nối Internet.';
      default:
        return e.message ?? 'Lỗi xác thực Firebase (${e.code}).';
    }
  }
}
