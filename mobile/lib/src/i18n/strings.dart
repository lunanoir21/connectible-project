import 'package:flutter/widgets.dart';

/// Lightweight i18n. This file is a LOCALIZATION RESOURCE (the mobile
/// equivalent of desktop/src/i18n/locales/*.json), so the Turkish
/// string *values* intentionally use correct diacritics per the scoped
/// exception documented in RULES.md. All keys and code stay ASCII.

enum AppLocale { en, tr }

const Map<String, String> _en = {
  'nav.home': 'Home',
  'nav.clipboard': 'Clipboard',
  'nav.transfers': 'Transfers',
  'nav.input': 'Remote',
  'nav.settings': 'Settings',
  'status.connected': 'Connected',
  'status.connecting': 'Connecting',
  'status.reconnecting': 'Reconnecting',
  'status.idle': 'Not connected',
  'status.thisDevice': 'This device',
  'common.pair': 'Pair',
  'common.online': 'Online',
  'common.offline': 'Offline',
  'home.connectedToOne': 'Connected to {name}',
  'home.notConnected': 'No device connected',
  'home.notPairedYet': 'No paired devices yet',
  'home.paired': 'Paired',
  'home.statPaired': 'Paired',
  'home.connectByAddress': 'Connect by address',
  // T-X33: `DeviceListModel.lastDiscoveryError` is raw, dynamic mDNS/
  // platform-channel text (not a fixed message set), so only the
  // wrapping label is translatable -- mirrors how the desktop Doctor
  // panel's `detail` field stays daemon-raw for the same reason.
  'home.discoveryError': 'Device discovery: {error}',
  // T-X32: shorthand for this device's own name in the compact
  // "THIS DEVICE / {name}" eyebrow, when no device name is set yet.
  'home.meFallback': 'Me',
  'home.fingerprintChanged':
      "This device's security key changed since pairing. Forget it and pair "
          'again to reconnect.',
  'home.pairingRejected': 'Pairing was rejected',
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
  // T-X32: shown when a peer advertises an empty device_name (mDNS TXT
  // record, pairing request, or paired-roster entry) -- the model/
  // service layer that first sees these has no i18n access, so it
  // stores '' and the widget layer supplies this at render time.
  'devices.unknownName': 'Unknown device',
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
  'clipboard.emptyTitle': 'Nothing copied yet',
  'clipboard.emptyHint': 'Copied text syncs here between your paired devices.',
  'clipboard.send': 'Send clipboard',
  'clipboard.copy': 'Copy',
  'clipboard.history': 'Clipboard history',
  // T-X32: `ClipboardEntry.source` is currently always the raw sentinel
  // 'local'/'remote' (models.dart's own doc comment aspires to a real
  // peer name/id, not implemented yet) -- this is what non-local
  // renders instead of the literal English word "remote".
  'clipboard.remoteSource': 'Remote device',
  'clipboard.oversized': 'Too large to sync ({size})',
  'clipboard.image': 'Image',
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
  // T-X24: history row relative-time label, mirroring desktop's
  // formatRelativeTime (T-X15) granularity but hand-rolled (no `intl`
  // dependency on mobile).
  'transfers.timeJustNow': 'Just now',
  'transfers.timeMinutesAgo': '{n}m ago',
  'transfers.timeHoursAgo': '{n}h ago',
  'transfers.timeDaysAgo': '{n}d ago',
  'input.title': 'Remote control',
  'input.eyebrow': 'Remote input',
  'input.hint':
      'Drag to move the pointer, tap to click, double-tap for a double click. Two fingers scroll.',
  'input.keyboard': 'Keyboard',
  'input.leftClick': 'Left',
  'input.rightClick': 'Right',
  'input.arrowLeft': 'Left arrow key',
  'input.arrowUp': 'Up arrow key',
  'input.arrowDown': 'Down arrow key',
  'input.arrowRight': 'Right arrow key',
  'input.enter': 'Enter',
  'input.backspace': 'Backspace',
  'input.tab': 'Tab',
  'input.shift': 'Shift',
  'input.ctrl': 'Ctrl',
  'input.alt': 'Alt',
  'input.noDevice': 'Pair a computer to control it from here.',
  'settings.title': 'Settings',
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
  'pairing.pairedTitle': 'Paired',
  'pairing.pairedSub': "You're connected and ready to sync.",
  'pairing.landing.title': 'Connect your desktop',
  'pairing.landing.subtitle':
      'Pair with Connectible on your computer to share your clipboard, '
          'send files, and control it from your phone.',
  'pairing.landing.cta': 'Pair Desktop',
  'pairing.landing.howItWorks': 'How it works',
  'pairing.landing.step1Title': 'Open Connectible on your computer',
  'pairing.landing.step1Body':
      'Go to Settings and generate a pairing QR code.',
  'pairing.landing.step2Title': 'Scan the code',
  'pairing.landing.step2Body':
      'Tap the button above to open the scanner and point it at the code '
          'on your screen.',
  'pairing.landing.step3Title': "You're connected",
  'pairing.landing.step3Body':
      'The desktop appears on your Home screen. Your connection is '
          'encrypted and PIN-verified.',
  'pairing.scan.title': 'Scan to pair',
  'pairing.scan.hint':
      'Point your camera at the QR code shown on your computer.',
  'pairing.scan.simulate': 'Simulate scan',
  'pairing.scan.noCamera': 'No camera preview here',
  'pairing.scan.noCameraHint':
      'This device has no camera. Use Simulate scan to test pairing.',
  'pairing.scan.invalidCode': 'Not a Connectible pairing code',
  'pairing.scan.permissionDenied': 'Camera access denied',
  'pairing.scan.permissionDeniedHint':
      'Allow camera access for Connectible in system settings, then try again.',
};

const Map<String, String> _tr = {
  'nav.home': 'Ana ekran',
  'nav.clipboard': 'Pano',
  'nav.transfers': 'Aktarımlar',
  'nav.input': 'Uzaktan',
  'nav.settings': 'Ayarlar',
  'status.connected': 'Bağlı',
  'status.connecting': 'Bağlanıyor',
  'status.reconnecting': 'Yeniden bağlanıyor',
  'status.idle': 'Bağlı değil',
  'status.thisDevice': 'Bu cihaz',
  'common.pair': 'Eşleştir',
  'common.online': 'Çevrimiçi',
  'common.offline': 'Çevrimdışı',
  'home.connectedToOne': '{name} ile bağlı',
  'home.notConnected': 'Bağlı cihaz yok',
  'home.notPairedYet': 'Henüz eşleşmiş cihaz yok',
  'home.paired': 'Eşleşti',
  'home.statPaired': 'Eşleşmiş',
  'home.connectByAddress': 'Adresle bağlan',
  'home.discoveryError': 'Cihaz keşfi: {error}',
  'home.meFallback': 'Ben',
  'home.fingerprintChanged':
      'Bu cihazın güvenlik anahtarı eşleşmeden sonra değişti. Yeniden '
          'bağlanmak için cihazı unutup tekrar eşleştir.',
  'home.pairingRejected': 'Eşleştirme reddedildi',
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
  'devices.unknownName': 'Bilinmeyen cihaz',
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
  'clipboard.emptyTitle': 'Henüz kopyalanmadı',
  'clipboard.emptyHint':
      'Kopyalanan metin eşleşmiş cihazların arasında burada senkronlanır.',
  'clipboard.send': 'Panoyu gönder',
  'clipboard.copy': 'Kopyala',
  'clipboard.history': 'Pano geçmişi',
  'clipboard.remoteSource': 'Uzak cihaz',
  'clipboard.oversized': 'Senkronize edilemeyecek kadar büyük ({size})',
  'clipboard.image': 'Görsel',
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
  'transfers.timeJustNow': 'Az önce',
  'transfers.timeMinutesAgo': '{n} dk önce',
  'transfers.timeHoursAgo': '{n} sa önce',
  'transfers.timeDaysAgo': '{n} g önce',
  'input.title': 'Uzaktan kontrol',
  'input.eyebrow': 'Uzaktan giriş',
  'input.hint':
      'İmleci hareket ettirmek için sürükle, tıklamak için dokun, çift tık için iki kez dokun. İki parmakla kaydır.',
  'input.keyboard': 'Klavye',
  'input.leftClick': 'Sol',
  'input.rightClick': 'Sağ',
  'input.arrowLeft': 'Sol ok tuşu',
  'input.arrowUp': 'Yukarı ok tuşu',
  'input.arrowDown': 'Aşağı ok tuşu',
  'input.arrowRight': 'Sağ ok tuşu',
  'input.enter': 'Enter',
  'input.backspace': 'Sil',
  'input.tab': 'Tab',
  'input.shift': 'Shift',
  'input.ctrl': 'Ctrl',
  'input.alt': 'Alt',
  'input.noDevice': 'Buradan kontrol etmek için bir bilgisayar eşleştir.',
  'settings.title': 'Ayarlar',
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
  'pairing.pairedTitle': 'Eşleşti',
  'pairing.pairedSub': 'Bağlandın, eşitlemeye hazırsın.',
  'pairing.landing.title': 'Bilgisayarını eşleştir',
  'pairing.landing.subtitle':
      'Panonu paylaşmak, dosya göndermek ve bilgisayarını telefonundan '
          'kontrol etmek için Connectible ile eşleştir.',
  'pairing.landing.cta': 'Masaüstünü Eşleştir',
  'pairing.landing.howItWorks': 'Nasıl çalışır',
  'pairing.landing.step1Title': "Bilgisayarında Connectible'ı aç",
  'pairing.landing.step1Body':
      "Ayarlar'a git ve bir eşleştirme QR kodu oluştur.",
  'pairing.landing.step2Title': 'Kodu tara',
  'pairing.landing.step2Body':
      'Tarayıcıyı açmak için yukarıdaki düğmeye dokun ve ekrandaki koda '
          'doğrult.',
  'pairing.landing.step3Title': 'Bağlandın',
  'pairing.landing.step3Body':
      'Bilgisayar artık Ana ekranında görünür. Bağlantın şifreli ve PIN '
          'ile doğrulanmış.',
  'pairing.scan.title': 'Eşleştirmek için tara',
  'pairing.scan.hint':
      'Kamerayı bilgisayarında görünen QR koduna doğrult.',
  'pairing.scan.simulate': 'Taramayı simüle et',
  'pairing.scan.noCamera': 'Burada kamera önizlemesi yok',
  'pairing.scan.noCameraHint':
      'Bu cihazda kamera yok. Eşleşmeyi test etmek için taramayı simüle et.',
  'pairing.scan.invalidCode': 'Bu bir Connectible eşleştirme kodu değil',
  'pairing.scan.permissionDenied': 'Kamera erişimi reddedildi',
  'pairing.scan.permissionDeniedHint':
      "Sistem ayarlarından Connectible'a kamera erişimi ver ve tekrar dene.",
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
