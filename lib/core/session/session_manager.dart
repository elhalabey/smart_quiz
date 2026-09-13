import 'package:flutter/foundation.dart';

import 'user_session.dart';

class SessionManager extends ChangeNotifier {
  UserSession? _currentSession;

  UserSession? get currentSession => _currentSession;

  bool get isLoggedIn => _currentSession != null;

  void setSession(UserSession session) {
    _currentSession = session;
    notifyListeners();
  }

  void clearSession() {
    _currentSession = null;
    notifyListeners();
  }
}

