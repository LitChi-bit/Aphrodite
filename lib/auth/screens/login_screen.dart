import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../models/auth_state.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.lock_outline,
                          size: 34,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 20),
                    Text('欢迎回来',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('登录后继续你的对话',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _loginController,
                      autofillHints: const [AutofillHints.username],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                          labelText: '账号',
                          prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.key_outlined),
                        suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: state.status == AuthStatus.authenticating
                          ? null
                          : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: state.status == AuthStatus.authenticating
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('登录'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('演示阶段可输入任意非空账号和密码',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final ok = await ref.read(authProvider.notifier).signIn(
        login: _loginController.text, password: _passwordController.text);
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).pushReplacementNamed(AppRouter.home);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入账号和密码')));
    }
  }
}
