import 'package:flutter/material.dart';
import '../../models/friend_request_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/user_friend_service.dart';
import '../../widgets/user_avatar.dart';
import '../chat/chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _userService = UserFriendService();
  final _searchController = TextEditingController();
  List<UserModel> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String currentUid) async {
    setState(() => _isSearching = true);
    final results = await _userService.searchUsers(
      currentUid,
      _searchController.text,
    );
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAuthUser = AuthService().currentUser;
    if (currentAuthUser == null) return const SizedBox.shrink();
    final currentUid = currentAuthUser.uid;

    return StreamBuilder<UserModel?>(
      stream: _userService.getUserProfileStream(currentUid),
      builder: (context, userSnap) {
        final currentUser = userSnap.data ??
            UserModel(
              uid: currentUid,
              email: currentAuthUser.email ?? '',
              displayName: currentAuthUser.displayName ??
                  (currentAuthUser.email?.split('@').first ?? 'Thành viên'),
            );

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Danh bạ Bạn bè'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Bạn bè'),
                  Tab(text: 'Lời mời'),
                  Tab(text: 'Tìm bạn'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                StreamBuilder<List<UserModel>>(
                  stream: _userService.getFriendsListStream(currentUser.friendIds),
                  builder: (context, friendSnap) {
                    final friends = friendSnap.data ?? [];
                    if (friends.isEmpty) {
                      return const Center(
                        child: Text('Bạn chưa có người bạn nào trong danh bạ.'),
                      );
                    }
                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return ListTile(
                          leading: RealtimeUserAvatar(
                            uid: friend.uid,
                            fallbackAvatarUrl: friend.avatarUrl,
                            fallbackName: friend.displayName,
                            radius: 20,
                          ),
                          title: Text(friend.displayName),
                          subtitle: Text(friend.email),
                          trailing: FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    currentUser: currentUser,
                                    friendUser: friend,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 18),
                            label: const Text('Nhắn tin'),
                          ),
                        );
                      },
                    );
                  },
                ),
                StreamBuilder<List<FriendRequestModel>>(
                  stream: _userService.getIncomingRequestsStream(currentUser.uid),
                  builder: (context, reqSnap) {
                    final requests = reqSnap.data ?? [];
                    if (requests.isEmpty) {
                      return const Center(
                        child: Text('Không có lời mời kết bạn mới.'),
                      );
                    }
                    return ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final req = requests[index];
                        return ListTile(
                          leading: RealtimeUserAvatar(
                            uid: req.senderId,
                            fallbackAvatarUrl: req.senderAvatar,
                            fallbackName: req.senderName,
                            radius: 20,
                          ),
                          title: Text(req.senderName),
                          subtitle: const Text('Đã gửi lời mời kết bạn'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filled(
                                onPressed: () async {
                                  try {
                                    await _userService.acceptFriendRequest(req);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Đã chấp nhận lời mời kết bạn!'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Chấp nhận thất bại: $e'),
                                          backgroundColor: Colors.red.shade700,
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.check),
                                tooltip: 'Chấp nhận',
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                onPressed: () async {
                                  try {
                                    await _userService.rejectFriendRequest(req.requestId);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Đã từ chối lời mời kết bạn.'),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Từ chối thất bại: $e'),
                                          backgroundColor: Colors.red.shade700,
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.close),
                                tooltip: 'Từ chối',
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onSubmitted: (_) => _performSearch(currentUser.uid),
                              decoration: const InputDecoration(
                                hintText: 'Nhập tên hoặc email để tìm...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _performSearch(currentUser.uid),
                            child: const Text('Tìm'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _isSearching
                          ? const Center(child: CircularProgressIndicator())
                          : _searchResults.isEmpty
                              ? const Center(
                                  child: Text('Không tìm thấy người dùng nào.'),
                                )
                              : ListView.builder(
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final user = _searchResults[index];
                                    final isAlreadyFriend =
                                        currentUser.friendIds.contains(user.uid);

                                    return ListTile(
                                      leading: RealtimeUserAvatar(
                                        uid: user.uid,
                                        fallbackAvatarUrl: user.avatarUrl,
                                        fallbackName: user.displayName,
                                        radius: 20,
                                      ),
                                      title: Text(user.displayName),
                                      subtitle: Text(user.email),
                                      trailing: isAlreadyFriend
                                          ? const Chip(label: Text('Đã là bạn bè'))
                                          : OutlinedButton.icon(
                                              onPressed: () async {
                                                try {
                                                  await _userService.sendFriendRequest(
                                                    sender: currentUser,
                                                    receiverId: user.uid,
                                                  );
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Đã gửi lời mời kết bạn tới ${user.displayName}',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Gửi lời mời thất bại: $e',
                                                        ),
                                                        backgroundColor:
                                                            Colors.red.shade700,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                              icon: const Icon(
                                                  Icons.person_add_alt_1,
                                                  size: 18),
                                              label: const Text('Kết bạn'),
                                            ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
