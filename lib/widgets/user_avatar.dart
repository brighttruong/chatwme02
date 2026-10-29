import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/user_friend_service.dart';

class UserAvatar extends StatelessWidget {
  final String avatarUrl;
  final String? name;
  final double radius;

  const UserAvatar({
    super.key,
    required this.avatarUrl,
    this.name,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final formattedUrl = UserFriendService.formatDriveImageUrl(avatarUrl);

    if (formattedUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(formattedUrl),
        onBackgroundImageError: (_, __) {},
      );
    }

    final initial = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : null;

    return CircleAvatar(
      radius: radius,
      child: initial != null
          ? Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.9,
              ),
            )
          : Icon(Icons.person, size: radius * 1.1),
    );
  }
}

class RealtimeUserAvatar extends StatelessWidget {
  final String uid;
  final String fallbackAvatarUrl;
  final String? fallbackName;
  final double radius;

  const RealtimeUserAvatar({
    super.key,
    required this.uid,
    this.fallbackAvatarUrl = '',
    this.fallbackName,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return UserAvatar(
        avatarUrl: fallbackAvatarUrl,
        name: fallbackName,
        radius: radius,
      );
    }

    return StreamBuilder<UserModel?>(
      stream: UserFriendService().getUserProfileStream(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final avatarUrl = (user != null && user.avatarUrl.isNotEmpty)
            ? user.avatarUrl
            : fallbackAvatarUrl;
        final name = (user != null && user.displayName.isNotEmpty)
            ? user.displayName
            : fallbackName;

        return UserAvatar(
          avatarUrl: avatarUrl,
          name: name,
          radius: radius,
        );
      },
    );
  }
}
