import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:8090';
    }
    return Platform.isAndroid ? 'http://10.0.2.2:8090' : 'http://localhost:8090';
  }
  static final ApiService _instance = ApiService._internal();

  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  String? _deviceId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token');
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString('device_id', _deviceId!);
    }
  }

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'X-Device-Holding-ID': _deviceId ?? '',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  Future<void> clearAuth() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  bool get isAuthenticated => _token != null;

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> get(String endpoint) async {
    return await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
    );
  }

  // Auth methods
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await post('/auth/login', {
      'username': username,
      'password': password,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      await setToken(data['token']);
    }
    return data;
  }

  Future<Map<String, dynamic>> checkRegistered() async {
    final response = await get('/auth/checkRegistered');
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> registerDevice(String deviceName) async {
    final response = await post('/auth/signingDevice', {
      'deviceName': deviceName,
    });
    return jsonDecode(response.body);
  }

  // Item methods
  Future<List<dynamic>> getItems({String? typeId, int? limit, int? offset, String? sortBy, String? sortOrder}) async {
    final queryParams = <String, String>{};
    if (typeId != null) queryParams['typeId'] = typeId;
    if (limit != null) queryParams['limit'] = limit.toString();
    if (offset != null) queryParams['offset'] = offset.toString();
    if (sortBy != null) queryParams['sortBy'] = sortBy;
    if (sortOrder != null) queryParams['sortOrder'] = sortOrder;

    final uri = Uri.parse('$baseUrl/item').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception('Failed to load items: ${response.body}');
  }

  Future<List<dynamic>> searchItems(String keyword, {String? typeId, int? limit}) async {
    final queryParams = <String, String>{'keyword': keyword};
    if (typeId != null) queryParams['typeId'] = typeId;
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse('$baseUrl/item/search').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception('Failed to search items: ${response.body}');
  }

  Future<Map<String, dynamic>> createType(String typeName) async {
    final response = await post('/item/type', {
      'typeName': typeName,
    });
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> createItem(String name, List<String> otherNames, String? typeId) async {
    final response = await post('/item', {
      'itemDefaultName': name,
      'itemOtherNames': otherNames,
      'typeId': typeId,
    });
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> createUnit(String itemId, String unitName, int? price) async {
    final response = await post('/item/unit/itemId/$itemId', {
      'unitName': unitName,
      'unitPriceDefault': price,
    });
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> patchItem(String itemId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/item/$itemId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> patchUnit(String unitId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/item/unit/$unitId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> addItemOtherName(String itemId, String nameString) async {
    final response = await post('/item/otherName/itemId/$itemId', {
      'nameString': nameString,
    });
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> removeItemOtherName(String otherNameId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/item/otherName/$otherNameId'),
      headers: _headers,
    );
    return jsonDecode(response.body);
  }

  Future<List<dynamic>> getTypes() async {
    final response = await get('/item/types');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception('Failed to load types: ${response.body}');
  }
}

// TODO: Add pin top items.