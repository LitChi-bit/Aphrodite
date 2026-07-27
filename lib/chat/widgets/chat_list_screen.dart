import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../models/conversation.dart';
import '../providers/conversations_provider.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _isSearchVisible = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'Aphrodite',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _toggleSearch(),
          ),
        ],
      ),
      drawer: _AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(conversationsProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 搜索栏（可折叠）
            if (_isSearchVisible)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SearchBar(
                    hintText: '搜索会话',
                    leading: const Icon(Icons.search),
                    trailing: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _closeSearch,
                      ),
                    ],
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),

            // 会话列表或状态
            conversations.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                child: _ErrorState(
                  onRetry: () => ref.invalidate(conversationsProvider),
                ),
              ),
              data: (items) {
                final filtered = _query.trim().isEmpty
                    ? items
                    : items
                        .where((item) => item.title
                            .toLowerCase()
                            .contains(_query.trim().toLowerCase()))
                        .toList();

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 56, color: scheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            _query.trim().isEmpty ? '暂无会话' : '没有找到会话',
                            style: TextStyle(color: scheme.outline),
                          ),
                          if (_query.trim().isEmpty) ...[
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                // TODO: 新建会话
                              },
                              icon: const Icon(Icons.edit),
                              label: const Text('新建会话'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }
                return SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 84,
                  ),
                  itemBuilder: (context, index) =>
                      _ConversationTile(conversation: filtered[index]),
                );
              },
            ),
          ],
        ),
      ),

      // 浮动新建按钮
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: 新建会话
        },
        child: const Icon(Icons.edit),
      ),
    );
  }

  void _toggleSearch() {
    if (_isSearchVisible) {
      _closeSearch();
      return;
    }
    setState(() => _isSearchVisible = true);
  }

  void _closeSearch() {
    setState(() {
      _isSearchVisible = false;
      _query = '';
    });
  }
}

// ──────────────────── 侧边抽屉 ────────────────────

class _AppDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // 用户信息区
            DrawerHeader(
              decoration: BoxDecoration(color: scheme.primaryContainer),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: scheme.primary,
                    child:
                        Icon(Icons.person, size: 32, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text('未登录',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      )),
                  Text('点击登录你的账号',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onPrimaryContainer)),
                ],
              ),
            ),

            // 菜单项
            _DrawerItem(
              icon: Icons.group_outlined,
              label: '联系人',
              onTap: () {
                Navigator.pop(context);
                // TODO: 跳转联系人页
              },
            ),
            _DrawerItem(
              icon: Icons.call_outlined,
              label: '通话记录',
              onTap: () {
                Navigator.pop(context);
                // TODO: 跳转通话记录页
              },
            ),
            _DrawerItem(
              icon: Icons.bookmark_outline,
              label: '收藏的消息',
              onTap: () {
                Navigator.pop(context);
                // TODO: 跳转收藏页
              },
            ),
            const Divider(),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: '设置',
              onTap: () {
                Navigator.pop(context);
                // TODO: 跳转设置页
              },
            ),
            _DrawerItem(
              icon: Icons.help_outline,
              label: '帮助与反馈',
              onTap: () {
                Navigator.pop(context);
                // TODO: 跳转帮助页
              },
            ),

            const Spacer(),
            // 底部版本信息
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aphrodite v1.0.0',
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}

// ──────────────────── 会话列表项 ────────────────────

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 76,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 27,
        backgroundColor: scheme.primaryContainer,
        child: Text(
          conversation.title.characters.isEmpty
              ? '?'
              : conversation.title.characters.first,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            _timeLabel(conversation.lastMessageAt),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (conversation.encryptionState == ConversationEncryptionState.ready)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.lock, size: 13, color: scheme.primary),
            ),
          Expanded(
            child: Text(
              conversation.lastMessagePreview ?? '暂无消息',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conversation.isMuted)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.notifications_off_outlined, size: 16),
            ),
          if (conversation.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: TextStyle(color: scheme.onPrimary, fontSize: 11),
              ),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).pushNamed(
        AppRouter.chatRoom,
        arguments: conversation,
      ),
    );
  }

  String _timeLabel(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    if (now.difference(time).inDays > 0) return '昨天';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ──────────────────── 错误状态 ────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            const Text('会话加载失败'),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}
