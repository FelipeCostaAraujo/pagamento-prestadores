import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ds_widgets.dart';

/// Username/password sign-in.
///
/// There is no "create account" link on purpose: accounts are created on the
/// server with `api user add`, so the published API has no signup surface.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A session that ended on its own explains itself here.
    _error = widget.auth.notice;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Preencha usuário e senha.');
      return;
    }

    setState(() => _error = null);
    widget.auth.clearNotice();

    final failure = await widget.auth.login(username, password);
    if (!mounted) return;
    if (failure != null) {
      setState(() => _error = failure);
      // Keep the username, clear the password — the usual retry is a typo in
      // the password.
      _password.clear();
      _passwordFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DsColors.bgPage,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: DsGradients.hero),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: DsSpace.s5,
                vertical: DsSpace.s6,
              ),
              child: ConstrainedBox(
                // Keeps the form a readable column on a tablet or desktop
                // window instead of stretching edge to edge.
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'DIÁRIAS',
                      textAlign: TextAlign.center,
                      style: DsText.caps(
                        size: 12,
                        color: Colors.white.withValues(alpha: 0.62),
                        tracking: 0.2,
                      ),
                    ),
                    const SizedBox(height: DsSpace.s3),
                    Text(
                      'Controle e fechamento',
                      textAlign: TextAlign.center,
                      style: DsText.display(
                        size: 26,
                        height: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: DsSpace.s7),
                    DsCard(
                      padding: const EdgeInsets.all(DsSpace.s5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Entrar', style: DsText.display(size: 20)),
                          const SizedBox(height: DsSpace.s5),
                          _FieldLabel('Usuário'),
                          const SizedBox(height: DsSpace.s2),
                          _LoginField(
                            controller: _username,
                            hint: 'seu.usuario',
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                          ),
                          const SizedBox(height: DsSpace.s4),
                          _FieldLabel('Senha'),
                          const SizedBox(height: DsSpace.s2),
                          _LoginField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            hint: '••••••••',
                            obscure: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                                color: DsColors.textMuted,
                              ),
                              tooltip: _obscure
                                  ? 'Mostrar senha'
                                  : 'Esconder senha',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: DsSpace.s4),
                            _ErrorBanner(message: _error!),
                          ],
                          const SizedBox(height: DsSpace.s5),
                          ListenableBuilder(
                            listenable: widget.auth,
                            builder: (context, _) => DsButton(
                              label: widget.auth.busy ? 'Entrando…' : 'Entrar',
                              size: DsButtonSize.lg,
                              block: true,
                              onPressed: widget.auth.busy ? null : _submit,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: DsSpace.s5),
                    Text(
                      'As contas são criadas pelo administrador no servidor.',
                      textAlign: TextAlign.center,
                      style: DsText.body(
                        size: 12,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DsText.body(
      size: 13,
      weight: DsWeight.bold,
      height: 1.2,
      color: DsColors.textBody,
    ),
  );
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.obscure = false,
    this.suffix,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final bool obscure;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(DsRadius.md),
      borderSide: const BorderSide(color: DsColors.borderStrong, width: 1.5),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: !obscure,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: DsText.body(
        size: 16,
        weight: DsWeight.bold,
        height: 1.2,
        color: DsColors.textStrong,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: DsText.body(size: 16, height: 1.2, color: DsColors.slate300),
        filled: true,
        fillColor: DsColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DsSpace.s3,
          vertical: DsSpace.s3,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: DsColors.borderFocus, width: 2),
        ),
        suffixIcon: suffix,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.s3,
        vertical: DsSpace.s3,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        border: Border.all(color: const Color(0xFFF3C2BF)),
        borderRadius: BorderRadius.circular(DsRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: DsColors.danger),
          const SizedBox(width: DsSpace.s2),
          Expanded(
            child: Text(
              message,
              style: DsText.body(
                size: 13,
                height: 1.4,
                color: DsColors.slate800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
