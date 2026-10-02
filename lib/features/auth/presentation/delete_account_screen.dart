import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
  });

  @override
  State<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState
    extends State<DeleteAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تأكيد حذف الحساب'),
            content: const Text(
              'تحذير: سيتم حذف الحساب نهائيًا ولا يمكن التراجع عن هذه العملية.\n\n'
              'سيتم حذف بيانات الحساب الشخصية والعلاقات المرتبطة به. '
              'بعض السجلات التعليمية مثل نتائج الاختبارات قد يتم الاحتفاظ بها.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('نعم، احذف الحساب'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.deleteAccountWithCredentials(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم حذف الحساب نهائيًا بنجاح',
          ),
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('حذف الحساب'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 420,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.delete_forever,
                        size: 80,
                        color: Colors.red,
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'حذف الحساب نهائيًا',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'أدخل البريد الإلكتروني وكلمة المرور الخاصة بالحساب الذي تريد حذفه.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                        ),
                      ),

                      const SizedBox(height: 28),

                      TextFormField(
                        controller: _emailController,
                        keyboardType:
                            TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'البريد الإلكتروني',
                          prefixIcon:
                              Icon(Icons.email_outlined),
                          border:
                              OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.trim().isEmpty) {
                            return 'يرجى إدخال البريد الإلكتروني';
                          }

                          if (!value.contains('@')) {
                            return 'البريد الإلكتروني غير صحيح';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      TextFormField(
                        controller:
                            _passwordController,
                        obscureText:
                            _obscurePassword,
                        decoration:
                            InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon:
                              const Icon(
                            Icons.lock_outline,
                          ),
                          border:
                              const OutlineInputBorder(),
                          suffixIcon:
                              IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword =
                                    !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons
                                      .visibility_outlined
                                  : Icons
                                      .visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null ||
                              value.isEmpty) {
                            return 'يرجى إدخال كلمة المرور';
                          }

                          return null;
                        },
                      ),

                      const SizedBox(height: 28),

                      Container(
                        padding:
                            const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red
                              .withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.red
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'تنبيه: حذف الحساب عملية نهائية ولا يمكن التراجع عنها.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          style:
                              FilledButton.styleFrom(
                            backgroundColor:
                                Colors.red,
                          ),
                          onPressed: _isLoading
                              ? null
                              : _deleteAccount,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'حذف الحساب نهائيًا',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(
                                  context,
                                ).pop();
                              },
                        child:
                            const Text('إلغاء'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
