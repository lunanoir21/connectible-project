import 'package:flutter/widgets.dart';

/// Lightweight i18n. This file is a LOCALIZATION RESOURCE (the mobile
/// equivalent of desktop/src/i18n/locales/*.json), so the Turkish
/// string *values* intentionally use correct diacritics per the scoped
/// exception documented in RULES.md. All keys and code stay ASCII.

enum AppLocale { en, tr }

const Map<String, String> _en = {
  'nav.home': 'Home',
  'nav.devices': 'Devices',
  'nav.clipboard': 'Clipboard',
  'nav.transfers': 'Transfers',
  'nav.input': 'Remote',
  'nav.settings': 'Settings',
  'status.connected': 'Connected',
  'status.connecting': 'Connecting',
  'status.reconnecting': 'Reconnecting',
  'status.thisDevice': 'This device',
  'common.pair': 'Pair',
  'common.pairing': 'Pairing...',
  'common.cancel': 'Cancel',
  'common.close': 'Close',
  'common.online': 'Online',
  'common.offline': 'Offline',
  'common.retry': 'Retry',
  'common.actions': 'Actions',
  'home.connectedToOne': 'Connected to {name}',
  'home.notConnected': 'No device connected',
  'home.notPairedYet': 'No paired devices yet',
  'home.notPairedHint': 'Open Connectible on another device nearby to pair.',
  'home.paired': 'Paired',
  'home.statPaired': 'Paired',
  'home.tapToPair': 'Tap to pair',
  'home.connectByAddress': 'Connect by address',
  'home.receivingTitle': 'Discoverable',
  'home.receivingOnHint': 'Other devices can find this phone and send it files.',
  'home.receivingOffHint': 'Turn on to let other devices pair and send files.',
  'manual.title': 'Connect by address',
  'manual.subtitle':
      'No auto-discovery needed. Type the address shown on the other device.',
  'manual.addressLabel': 'IP address',
  'manual.portLabel': 'Port',
  'manual.connect': 'Connect',
  'manual.invalid': 'Enter a valid IP address and port (1-65535).',
  'manual.yourAddress': "This device's address",
  'manual.yourAddressUnknown': 'Not on a network',
  'devices.nearby': 'Nearby',
  'devices.emptyTitle': 'No devices yet',
  'devices.emptyHint':
      'Make sure a computer on this network is running Connectible.',
  'devices.onlineNow': 'Online now',
  'menu.connect': 'Connect',
  'menu.refresh': 'Refresh',
  'menu.info': 'Device info',
  'menu.disconnect': 'Disconnect',
  'menu.forget': 'Forget device',
  'info.title': 'Device info',
  'info.name': 'Name',
  'info.status': 'Status',
  'info.platform': 'Platform',
  'info.address': 'Address',
  'info.deviceId': 'Device ID',
  'info.done': 'Done',
  'clipboard.title': 'Clipboard',
  'clipboard.emptyTitle': 'Nothing copied yet',
  'clipboard.emptyHint': 'Copied text syncs here between your paired devices.',
  'clipboard.send': 'Send clipboard',
  'clipboard.copy': 'Copy',
  'clipboard.copied': 'Copied',
  'clipboard.history': 'Clipboard history',
  'transfers.title': 'Transfers',
  'transfers.emptyTitle': 'No transfers yet',
  'transfers.emptyHint': 'Send a file to a paired device or receive one.',
  'transfers.sendFile': 'Send file',
  'transfers.sending': 'Sending',
  'transfers.receiving': 'Receiving',
  'transfers.completed': 'Completed',
  'transfers.failed': 'Failed',
  'transfers.canceled': 'Canceled',
  'transfers.cancel': 'Cancel transfer',
  'transfers.saveTo': 'Save to...',
  'transfers.saved': 'File saved',
  'transfers.saveFailed': "Couldn't save the file",
  'transfers.saveUnavailable': 'File is no longer available',
  'transfers.sectionActive': 'In progress',
  'transfers.sectionHistory': 'History',
  'transfers.sendHint': 'Choose a file to send to {name}.',
  'transfers.notConnectedHint': 'Connect to a paired device first to send files.',
  'transfers.aDevice': 'the paired device',
  'input.title': 'Remote control',
  'input.eyebrow': 'Remote input',
  'input.waitingHint':
      "Use the paired computer's mouse and keyboard from here.",
  'input.hint':
      'Drag to move the pointer, tap to click, double-tap for a double click. Two fingers scroll.',
  'input.keyboard': 'Keyboard',
  'input.leftClick': 'Left',
  'input.rightClick': 'Right',
  'input.enter': 'Enter',
  'input.backspace': 'Backspace',
  'input.tab': 'Tab',
  'input.shift': 'Shift',
  'input.ctrl': 'Ctrl',
  'input.alt': 'Alt',
  'input.noDevice': 'Pair a computer to control it from here.',
  'settings.title': 'Settings',
  'settings.subtitle': 'Appearance, language, and connection details',
  'settings.appearance': 'Appearance',
  'settings.appearanceHint': 'Pick a monochrome theme. All themes are dark.',
  'settings.themeCharcoal': 'Charcoal',
  'settings.themeOnyx': 'Onyx',
  'settings.themeGraphite': 'Graphite',
  'settings.language': 'Language',
  'settings.about': 'About',
  'settings.version': 'Version',
  'settings.security': 'Security',
  // T-407: "TLS 1.3" is now accurate (T-401 enforces a real minimum
  // version floor on this device's server). "end to end" was dropped
  // -- it overstated the model, conflating transport encryption with
  // application-layer E2E encryption, and glossed over the accept-any
  // -self-signed-cert trust model (security comes from the PIN
  // exchange, not certificate identity; pinning is deferred to v1.0,
  // see README's known-limitations section).
  'settings.securityValue': 'TLS 1.3, PIN-verified pairing',
  'settings.discoverable': 'Discoverable',
  'settings.discoverableHint':
      'Allow other devices to pair into this phone. Turning this off stops '
          'this phone from advertising itself and closes its pairing server.',
  'settings.discoverableOn': 'On',
  'settings.discoverableOff': 'Off',
  'settings.notifications': 'Notification mirroring',
  'settings.notificationsHint':
      'Forward this phone\'s notifications to your paired desktop. Requires '
          'system Notification access.',
  'settings.notificationsGranted': 'Access granted',
  'settings.notificationsDenied': 'Access not granted',
  'settings.notificationsGrant': 'Grant access',
  'settings.notificationsManage': 'Manage',
  'settings.clipboard': 'Clipboard sync',
  'settings.clipboardHint':
      'Keep the clipboard in sync with your paired desktop while the app is '
          'open.',
  'settings.clipboardAutoMonitor': 'Auto-send copies from this phone',
  'settings.clipboardAutoApply': 'Auto-apply incoming to clipboard',
  'settings.diagnostics': 'System Doctor',
  'settings.diagnosticsHint':
      'Run health and permission checks for this phone.',
  'settings.diagnosticsOpen': 'Open',
  'doctor.title': 'System Doctor',
  'doctor.runAll': 'Run all checks',
  'doctor.running': 'Running...',
  'doctor.rerun': 'Re-run',
  'doctor.copyReport': 'Copy report',
  'doctor.copied': 'Copied',
  'doctor.catConnectivity': 'Connectivity',
  'doctor.catPermissions': 'Permissions',
  'doctor.catStorage': 'Storage',
  'pairing.title': 'Enter pairing code',
  'pairing.subtitle': 'Type the 6-digit code shown on {name}.',
  'pairing.incomingTitle': 'Pairing request',
  'pairing.incomingSub': '{name} wants to connect.',
  'pairing.enterOnOther': 'Enter this code on {name} to pair.',
  'pairing.expiresIn': 'Expires in {n}s',
  'pairing.timedOut': 'Timed out. Start again to retry.',
  'pairing.incorrectPin': 'Incorrect PIN. Try again.',
  'pairing.verifying': 'Verifying...',
  'pairing.pairedTitle': 'Paired',
  'pairing.pairedSub': "You're connected and ready to sync.",
};

const Map<String, String> _tr = {
  'nav.home': 'Ana ekran',
  'nav.devices': 'Cihazlar',
  'nav.clipboard': 'Pano',
  'nav.transfers': 'Aktarımlar',
  'nav.input': 'Uzaktan',
  'nav.settings': 'Ayarlar',
  'status.connected': 'Bağlı',
  'status.connecting': 'Bağlanıyor',
  'status.reconnecting': 'Yeniden bağlanıyor',
  'status.thisDevice': 'Bu cihaz',
  'common.pair': 'Eşleştir',
  'common.pairing': 'Eşleştiriliyor...',
  'common.cancel': 'İptal',
  'common.close': 'Kapat',
  'common.online': 'Çevrimiçi',
  'common.offline': 'Çevrimdışı',
  'common.retry': 'Tekrar dene',
  'common.actions': 'Eylemler',
  'home.connectedToOne': '{name} ile bağlı',
  'home.notConnected': 'Bağlı cihaz yok',
  'home.notPairedYet': 'Henüz eşleşmiş cihaz yok',
  'home.notPairedHint': 'Eşleştirmek için yakındaki başka bir cihazda Connectible\'ı aç.',
  'home.paired': 'Eşleşti',
  'home.statPaired': 'Eşleşmiş',
  'home.tapToPair': 'Eşleştirmek için dokun',
  'home.connectByAddress': 'Adresle bağlan',
  'home.receivingTitle': 'Keşfedilebilir',
  'home.receivingOnHint': 'Diğer cihazlar bu telefonu bulup dosya gönderebilir.',
  'home.receivingOffHint': 'Diğer cihazların eşleşip dosya göndermesi için aç.',
  'manual.title': 'Adresle bağlan',
  'manual.subtitle':
      'Otomatik keşif gerekmez. Diğer cihazda görünen adresi yaz.',
  'manual.addressLabel': 'IP adresi',
  'manual.portLabel': 'Port',
  'manual.connect': 'Bağlan',
  'manual.invalid': 'Geçerli bir IP adresi ve port gir (1-65535).',
  'manual.yourAddress': 'Bu cihazın adresi',
  'manual.yourAddressUnknown': 'Bir ağa bağlı değil',
  'devices.nearby': 'Yakında',
  'devices.emptyTitle': 'Henüz cihaz yok',
  'devices.emptyHint':
      'Bu ağdaki bir bilgisayarda Connectible çalıştığından emin ol.',
  'devices.onlineNow': 'Şu an çevrimiçi',
  'menu.connect': 'Bağlan',
  'menu.refresh': 'Yenile',
  'menu.info': 'Cihaz bilgileri',
  'menu.disconnect': 'Bağlantıyı kes',
  'menu.forget': 'Cihazı unut',
  'info.title': 'Cihaz bilgileri',
  'info.name': 'Ad',
  'info.status': 'Durum',
  'info.platform': 'Platform',
  'info.address': 'Adres',
  'info.deviceId': 'Cihaz kimliği',
  'info.done': 'Tamam',
  'clipboard.title': 'Pano',
  'clipboard.emptyTitle': 'Henüz kopyalanmadı',
  'clipboard.emptyHint':
      'Kopyalanan metin eşleşmiş cihazların arasında burada senkronlanır.',
  'clipboard.send': 'Panoyu gönder',
  'clipboard.copy': 'Kopyala',
  'clipboard.copied': 'Kopyalandı',
  'clipboard.history': 'Pano geçmişi',
  'transfers.title': 'Aktarımlar',
  'transfers.emptyTitle': 'Henüz aktarım yok',
  'transfers.emptyHint': 'Eşleşmiş bir cihaza dosya gönder ya da al.',
  'transfers.sendFile': 'Dosya gönder',
  'transfers.sending': 'Gönderiliyor',
  'transfers.receiving': 'Alınıyor',
  'transfers.completed': 'Tamamlandı',
  'transfers.failed': 'Başarısız',
  'transfers.canceled': 'İptal edildi',
  'transfers.cancel': 'Aktarımı iptal et',
  'transfers.saveTo': 'Şuraya kaydet...',
  'transfers.saved': 'Dosya kaydedildi',
  'transfers.saveFailed': 'Dosya kaydedilemedi',
  'transfers.saveUnavailable': 'Dosya artık mevcut değil',
  'transfers.sectionActive': 'Sürüyor',
  'transfers.sectionHistory': 'Geçmiş',
  'transfers.sendHint': '{name} cihazına göndermek için bir dosya seç.',
  'transfers.notConnectedHint': 'Dosya göndermek için önce eşleşmiş bir cihaza bağlan.',
  'transfers.aDevice': 'eşleşmiş cihaz',
  'input.title': 'Uzaktan kontrol',
  'input.eyebrow': 'Uzaktan giriş',
  'input.waitingHint':
      'Eşleşmiş bilgisayarın fare ve klavyesini buradan kullan.',
  'input.hint':
      'İmleci hareket ettirmek için sürükle, tıklamak için dokun, çift tık için iki kez dokun. İki parmakla kaydır.',
  'input.keyboard': 'Klavye',
  'input.leftClick': 'Sol',
  'input.rightClick': 'Sağ',
  'input.enter': 'Enter',
  'input.backspace': 'Sil',
  'input.tab': 'Tab',
  'input.shift': 'Shift',
  'input.ctrl': 'Ctrl',
  'input.alt': 'Alt',
  'input.noDevice': 'Buradan kontrol etmek için bir bilgisayar eşleştir.',
  'settings.title': 'Ayarlar',
  'settings.subtitle': 'Görünüm, dil ve bağlantı bilgileri',
  'settings.appearance': 'Görünüm',
  'settings.appearanceHint': 'Bir monokrom tema seç. Tüm temalar koyudur.',
  'settings.themeCharcoal': 'Kömür',
  'settings.themeOnyx': 'Oniks',
  'settings.themeGraphite': 'Grafit',
  'settings.language': 'Dil',
  'settings.about': 'Hakkında',
  'settings.version': 'Sürüm',
  'settings.security': 'Güvenlik',
  'settings.securityValue': 'TLS 1.3, PIN ile doğrulanmış eşleşme',
  'settings.discoverable': 'Eşleştirmeye açık',
  'settings.discoverableHint':
      'Diğer cihazların bu telefonla eşleşmesine izin ver. Kapatmak bu '
          'telefonun kendini duyurmasını durdurur ve eşleştirme sunucusunu '
          'kapatır.',
  'settings.discoverableOn': 'Açık',
  'settings.discoverableOff': 'Kapalı',
  'settings.notifications': 'Bildirim yansıtma',
  'settings.notificationsHint':
      'Bu telefonun bildirimlerini eşleşmiş masaüstüne ilet. Sistem '
          'Bildirim erişimi gerektirir.',
  'settings.notificationsGranted': 'Erişim verildi',
  'settings.notificationsDenied': 'Erişim verilmedi',
  'settings.notificationsGrant': 'Erişim ver',
  'settings.notificationsManage': 'Yönet',
  'settings.clipboard': 'Pano eşitleme',
  'settings.clipboardHint':
      'Uygulama açıkken panoyu eşleşmiş masaüstünle eşit tut.',
  'settings.clipboardAutoMonitor': 'Bu telefondaki kopyaları otomatik gönder',
  'settings.clipboardAutoApply': 'Geleni panoya otomatik uygula',
  'settings.diagnostics': 'Sistem Doktoru',
  'settings.diagnosticsHint':
      'Bu telefon için sağlık ve izin kontrollerini çalıştır.',
  'settings.diagnosticsOpen': 'Aç',
  'doctor.title': 'Sistem Doktoru',
  'doctor.runAll': 'Tüm kontrolleri çalıştır',
  'doctor.running': 'Çalışıyor...',
  'doctor.rerun': 'Yeniden çalıştır',
  'doctor.copyReport': 'Raporu kopyala',
  'doctor.copied': 'Kopyalandı',
  'doctor.catConnectivity': 'Bağlantı',
  'doctor.catPermissions': 'İzinler',
  'doctor.catStorage': 'Depolama',
  'pairing.title': 'Eşleştirme kodunu gir',
  'pairing.subtitle': '{name} cihazında görünen 6 haneli kodu gir.',
  'pairing.incomingTitle': 'Eşleşme isteği',
  'pairing.incomingSub': '{name} bağlanmak istiyor.',
  'pairing.enterOnOther': 'Eşleşmek için bu kodu {name} cihazına gir.',
  'pairing.expiresIn': 'Kalan süre {n}s',
  'pairing.timedOut': 'Zaman aşımı. Tekrar denemek için yeniden başla.',
  'pairing.incorrectPin': 'Yanlış PIN. Tekrar dene.',
  'pairing.verifying': 'Doğrulanıyor...',
  'pairing.pairedTitle': 'Eşleşti',
  'pairing.pairedSub': 'Bağlandın, eşitlemeye hazırsın.',
};

class AppStrings {
  const AppStrings(this.locale);
  final AppLocale locale;

  Map<String, String> get _dict => locale == AppLocale.tr ? _tr : _en;

  String t(String key, [Map<String, Object>? params]) {
    var value = _dict[key] ?? _en[key] ?? key;
    if (params != null) {
      params.forEach((name, val) {
        value = value.replaceAll('{$name}', '$val');
      });
    }
    return value;
  }
}

/// Inherited access: `context.strings.t('nav.home')`.
class AppStringsScope extends InheritedWidget {
  const AppStringsScope(
      {super.key, required this.strings, required super.child});

  final AppStrings strings;

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    assert(scope != null, 'AppStringsScope missing from the widget tree');
    return scope!.strings;
  }

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      strings.locale != oldWidget.strings.locale;
}

extension StringsContext on BuildContext {
  AppStrings get strings => AppStringsScope.of(this);
}
