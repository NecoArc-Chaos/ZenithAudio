// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

JSObject _j(Object? v) {
  if (v == null) throw ArgumentError('JS interop object is null');
  return JSObject.fromInteropObject(v);
}

class AudioCache {
  static const _dbName = 'zenith_audio_cache';
  static const _storeName = 'audio_files';
  static const _maxBytes = 200 * 1024 * 1024;

  static final AudioCache _instance = AudioCache._();
  factory AudioCache() => _instance;
  AudioCache._();

  JSObject? _db;

  Future<void> init() async {
    if (_db != null) return;
    final factory = html.window.indexedDB;
    if (factory == null) throw Exception('浏览器不支持 IndexedDB');

    final completer = Completer<JSObject>();
    final openReq = _j(factory).callMethod<JSObject>('open'.toJS, _dbName.toJS, 1.toJS);

    openReq['onupgradeneeded'] = ((JSAny? e) {
      final evt = _j(e!);
      final target = _j(evt['target']!);
      final db = _j(target['result']!);
      final names = _j(db['objectStoreNames']!);
      final has = names.callMethod('contains'.toJS, _storeName.toJS).dartify() as bool;
      if (!has) {
        db.callMethod('createObjectStore'.toJS, _storeName.toJS);
      }
    }).toJS;

    openReq['onsuccess'] = ((JSAny? e) {
      final evt = _j(e!);
      final target = _j(evt['target']!);
      completer.complete(_j(target['result']!));
    }).toJS;

    openReq['onerror'] = ((JSAny? e) {
      if (!completer.isCompleted) completer.completeError('IndexedDB 打开失败');
    }).toJS;

    _db = await completer.future;
  }

  JSObject _store(String mode) {
    final tx = _db!.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, mode.toJS);
    return tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
  }

  Future<void> put(String key, Uint8List bytes) async {
    await init();
    final store = _store('readwrite');
    store.callMethod('put'.toJS, bytes.toJS, key.toJS);
    await _waitForTx(store);
  }

  Future<Uint8List?> get(String key) async {
    await init();
    final store = _store('readonly');
    final completer = Completer<Uint8List?>();
    final req = store.callMethod<JSObject>('get'.toJS, key.toJS);
    req['onsuccess'] = ((JSAny? e) {
      final evt = _j(e!);
      final target = _j(evt['target']!);
      final val = target['result'];
      completer.complete(val != null ? _toBytes(val.dartify()) : null);
    }).toJS;
    req['onerror'] = ((JSAny? _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;
    return completer.future;
  }

  Future<void> remove(String key) async {
    await init();
    final store = _store('readwrite');
    store.callMethod('delete'.toJS, key.toJS);
    await _waitForTx(store);
  }

  Future<Map<String, Uint8List>> getAll() async {
    await init();
    final store = _store('readonly');
    final completer = Completer<Map<String, Uint8List>>();
    final result = <String, Uint8List>{};
    final cursor = store.callMethod<JSObject>('openCursor'.toJS);
    cursor['onsuccess'] = ((JSAny? e) {
      final evt = _j(e!);
      final target = _j(evt['target']!);
      final curRaw = target['result'];
      if (curRaw == null) return;
      final cur = _j(curRaw);
      final key = cur['key'];
      final value = cur['value'];
      if (key != null && value != null) {
        result[key.dartify() as String] = _toBytes(value.dartify());
      }
      cur.callMethod('continue'.toJS);
    }).toJS;
    final tx = _j(store['transaction']!);
    tx['oncomplete'] = ((JSAny? _) {
      completer.complete(result);
    }).toJS;
    return completer.future;
  }

  Uint8List _toBytes(Object? val) {
    if (val is Uint8List) return val;
    if (val is List<int>) return Uint8List.fromList(val);
    throw Exception('无法转换音频数据');
  }

  Future<void> _waitForTx(JSObject store) async {
    final tx = _j(store['transaction']!);
    final completer = Completer<void>();
    tx['oncomplete'] = ((JSAny? _) {
      completer.complete();
    }).toJS;
    tx['onerror'] = ((JSAny? e) {
      if (!completer.isCompleted) completer.completeError('事务失败');
    }).toJS;
    return completer.future;
  }

  Future<int> getStorageUsed() async {
    final all = await getAll();
    int total = 0;
    for (final bytes in all.values) {
      total += bytes.lengthInBytes;
    }
    return total;
  }

  Future<bool> hasStorageLimit() async {
    final used = await getStorageUsed();
    return used >= _maxBytes;
  }

  Future<String> storeAndCreateUrl(String name, Uint8List bytes) async {
    if (await hasStorageLimit()) {
      throw Exception('音频缓存已满 (${_maxBytes ~/ 1048576}MB 上限)');
    }
    await put(name, bytes);
    final blob = html.Blob([bytes]);
    return html.Url.createObjectUrl(blob);
  }
}
