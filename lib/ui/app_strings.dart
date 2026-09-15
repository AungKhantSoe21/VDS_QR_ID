import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-global language toggle: Burmese (default) or English.
class LanguageController extends ValueNotifier<String> {
  LanguageController() : super('my');

  static const prefsKey = 'app_language';
  static final LanguageController instance = LanguageController();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString(prefsKey) ?? 'my';
    } catch (_) {}
  }

  Future<void> setLang(String lang) async {
    value = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, lang);
    } catch (_) {}
  }

  bool get isMy => value == 'my';
}

/// Convenience: resolve a Burmese/English pair against the current language.
String _t(String my, String en) =>
    LanguageController.instance.isMy ? my : en;

/// UI strings — single getters resolved at build time via [LanguageController].
class S {
  // App
  static String get appName => _t('eID စစ်ဆေးခြင်း', 'eID Verify');
  static String get appNameFull => _t('eID စစ်ဆေးခြင်း', 'eID Verify');
  static String get offlineNote =>
      _t('အင်တာနက်မလို · အော့ဖ်လိုင်းအလုပ်လုပ်သည်',
          'Fully offline · No network needed');

  // Steps
  static String get stepScan => _t('စကင်ဖတ်', 'Scan');
  static String get stepFace => _t('မျက်နှာ', 'Face');
  static String get stepCard => _t('ကတ်', 'Card');

  // Scanner
  static String get scannerTitle => _t('QR စကင်ဖတ်ပါ', 'Scan QR');
  static String get scannerHint =>
      _t('ကင်မရာကို QR ကုဒ်ဘက်သို့ ချိန်ပါ',
          'Point the camera at the code');
  static String get scannerWaiting => _t('QR ကို စောင့်နေသည်…', 'Waiting for QR…');
  static String get torch => _t('ဖလက်ရှ်', 'Flash');
  static String get switchCamera => _t('ကင်မရာပြောင်းပါ', 'Switch camera');
  static String get settings => _t('ဆက်တင်များ', 'Settings');

  // Face check
  static String get faceTitle => _t('မျက်နှာစစ်ဆေးခြင်း', 'Face check');
  static String get captureSelfie => _t('မျက်နှာဓာတ်ပုံရိုက်ပါ', 'Capture live selfie');
  static String get retakeSelfie => _t('ပြန်ရိုက်ပါ', 'Retake selfie');
  static String get matchTitle => _t('လူတူညီမှု ရှိသည်', 'SAME PERSON — face match');
  static String get mismatchTitle => _t('လူမတူညီပါ', 'NOT THE SAME — face mismatch');
  static String get noFaceTitle =>
      _t('မျက်နှာမတွေ့ပါ — ပြန်ရိုက်ပါ', 'NO FACE — retake the selfie');
  static String get score => _t('ရမှတ်', 'Score');
  static String get threshold => _t('သတ်မှတ်ချက်', 'Threshold');
  static String get showCard => _t('ကတ်ပြသပါ', 'Show ID card');
  static String get visualHint =>
      _t('ဤ QR တွင် ဓာတ်ပုံသာပါပြီး မျက်နှာပုံစံမပါပါ — နှစ်ပုံယှဉ်ကြည့်ပြီး အတည်ပြုပါ။',
          'This QR carries a photo but no face pattern — compare both pictures, then confirm.');
  static String get visualConfirm =>
      _t('မျက်မြင်အတည်ပြုပြီး — ကတ်ပြသပါ',
          'Visually confirmed — show ID card');
  static String get qrPhoto => _t('QR ဓာတ်ပုံ', 'QR photo');
  static String get liveSelfie => _t('ဓာတ်ပုံအရှင်', 'Live selfie');

  // Card screen
  static String get cardTitle => _t('မှတ်ပုံတင်ကတ်', 'Identity card');
  static String get flipCard => _t('ကတ်လှန်ပါ', 'Flip card');
  static String get scanNext => _t('နောက်တစ်ခုစကင်ဖတ်ပါ', 'Scan next');
  static String get fingerprint => _t('လက်ဗွေ', 'Fingerprint');
  static String get fingerOptional =>
      _t('လက်ဗွေ (ပြင်ပစက်၊ မဖြစ်မနေမဟုတ်)',
          'Fingerprint (external reader, optional)');
  static String get verifiedOffline =>
      _t('အော့ဖ်လိုင်းဖြင့် အတည်ပြုပြီးဖြစ်သည်။',
          'Verified fully offline. No network was used.');

  // Settings
  static String get faceMatchSection => _t('မျက်နှာတိုက်ဆိုင်မှု', 'Face match');
  static String get modelsSection =>
      _t('မျက်နှာမော်ဒယ်များ (ဖုန်းတွင်း)', 'Face models (on-device)');
  static String get aboutSection => _t('အကြောင်း', 'About');
  static String get appearanceSection => _t('အပြင်အဆင်', 'Appearance');
  static String get languageSection => _t('ဘာသာစကား', 'Language');
  static String get themeSystem => _t('စနစ်အတိုင်း', 'System');
  static String get themeLight => _t('အလင်း', 'Light');
  static String get themeDark => _t('အမှောင်', 'Dark');
  static String get setUp => _t('ပြင်ဆင်ပါ', 'Set up');
  static String get clearCache => _t('ကက်ချ်ရှင်းပါ', 'Clear cache');
  static String get langMy => 'မြန်မာ';
  static String get langEn => 'English';

  // Common actions
  static String get retry => _t('ပြန်လုပ်ပါ', 'Retry');
  static String get close => _t('ပိတ်ပါ', 'Close');
  static String get working => _t('လုပ်ဆောင်နေသည်…', 'Working…');
}
