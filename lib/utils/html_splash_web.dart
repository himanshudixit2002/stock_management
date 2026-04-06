import 'package:web/web.dart' as web;

/// Dismisses the inline splash in [web/index.html] (idempotent).
void hideHtmlLoadingSplash() {
  web.window.dispatchEvent(web.Event('stockmgmt-hide-html-splash'));
}
