import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String? get deviceId => _deviceId;

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

  Future<http.Response> patch(String endpoint, Map<String, dynamic> body) async {
    return await http.patch(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
      body: jsonEncode(body),
    );
  }

  Future<http.Response> delete(String endpoint) async {
    return await http.delete(
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

  Future<Map<String, dynamic>> updateType(String typeId, String typeName) async {
    final response = await patch('/item/type/id/$typeId', {
      'typeName': typeName,
    });
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> deleteType(String typeId) async {
    final response = await delete('/item/type/id/$typeId');
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

  Future<Map<String, dynamic>> createUnit(
    String itemId,
    String unitName,
    int? price, {
    int ratio = 1,
    bool isBaseUnit = false,
  }) async {
    final response = await post('/item/unit/itemId/$itemId', {
      'unitName': unitName,
      'unitPriceDefault': price,
      'ratio': ratio,
      'isBaseUnit': isBaseUnit,
    });
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> patchItem(String itemId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/item/id/$itemId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> patchUnit(String unitId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/item/unit/id/$unitId'),
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
    final response = await delete('/item/otherName/id/$otherNameId');
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> deleteUnit(String unitId) async {
    final response = await delete('/item/unit/id/$unitId');
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

  Future<Map<String, dynamic>> generateItemAISuggestions(String keyword) async {
    final response = await post('/item/ai-generate', {
      'keyword': keyword,
    });
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return decoded;
    }
    throw Exception(decoded['error'] ?? 'Failed to generate AI suggestions');
  }

  Future<Map<String, dynamic>> batchCreateItems({
    required String? typeId,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await post('/item/ai-batch-create', {
      'typeId': typeId ?? '',
      'items': items,
    });
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return decoded;
    }
    throw Exception(decoded['error'] ?? 'Failed to batch create items');
  }

  // Buyer methods
  Future<String> getNextBuyerCode() async {
    final response = await get('/invoice/buyer/next-code');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['nextCode'] ?? 'KH-001';
    }
    return 'KH-001';
  }

  Future<List<dynamic>> getBuyers({int? limit, int? offset}) async {
    final queryParams = <String, String>{};
    if (limit != null) queryParams['limit'] = limit.toString();
    if (offset != null) queryParams['offset'] = offset.toString();

    final uri = Uri.parse('$baseUrl/invoice/buyer').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed to load buyers: ${response.body}');
  }

  Future<List<dynamic>> searchBuyers(String keyword, {int? limit}) async {
    final queryParams = <String, String>{'keyword': keyword};
    if (limit != null) queryParams['limit'] = limit.toString();

    final uri = Uri.parse('$baseUrl/invoice/buyer/search').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception('Failed to search buyers: ${response.body}');
  }

  Future<Map<String, dynamic>> getBuyerByCode(String code) async {
    final response = await get('/invoice/buyer/by-code?code=$code');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Buyer not found');
  }

  // Invoice methods
  Future<String> getNextInvoiceCode() async {
    final response = await get('/invoice/next-code');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['nextCode'] ?? '';
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to get next invoice code');
  }


  Future<Map<String, dynamic>> takeTurn(String invoiceId) async {
    final response = await post('/invoice/takeTurn/invoiceId/$invoiceId', {});
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to take turn');
  }

  Future<Map<String, dynamic>> createInvoice({
    String? buyerId,
    required String invoiceCode,
    bool editStatus = true,
    String? buyerNameSnapshot,
    String? addressSnapshot,
    String? phoneNumberSnapshot,
    String? taxIdSnapshot,
    double? latSnapshot,
    double? lngSnapshot,
    String? idCardNumberSnapshot,
    String? emailSnapshot,
  }) async {
    final response = await post('/invoice', {
      'buyerId': buyerId,
      'invoiceCode': invoiceCode,
      'editStatus': editStatus,
      'buyerNameSnapshot': buyerNameSnapshot,
      'addressSnapshot': addressSnapshot,
      'phoneNumberSnapshot': phoneNumberSnapshot,
      'taxIdSnapshot': taxIdSnapshot,
      'latSnapshot': latSnapshot,
      'lngSnapshot': lngSnapshot,
      'idCardNumberSnapshot': idCardNumberSnapshot,
      'emailSnapshot': emailSnapshot,
    });
    
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to create invoice');
  }

  Future<Map<String, dynamic>> getInvoice(String invoiceId) async {
    final response = await get('/invoice/id/$invoiceId');
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to get invoice');
  }

  Future<Map<String, dynamic>> updateInvoice(String invoiceId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/invoice/id/$invoiceId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to update invoice');
  }

  Future<Map<String, dynamic>> createLineItem(String invoiceId, Map<String, dynamic> body) async {
    final response = await post('/invoice/lineItem/invoiceId/$invoiceId', body);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to create line item');
  }

  Future<Map<String, dynamic>> patchLineItem(String lineItemId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/invoice/lineItem/id/$lineItemId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to update line item');
  }

  Future<Map<String, dynamic>> changeLineItemOrder(String invoiceId, String lineItemId, String? prevId, String? nextId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/invoice/lineItem/changeOrder/$invoiceId'),
      headers: _headers,
      body: jsonEncode({
        'line_item_id': lineItemId,
        'prev_line_item_id': prevId,
        'next_line_item_id': nextId,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to change order');
  }

  Future<Map<String, dynamic>> deleteLineItem(String lineItemId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/invoice/lineItem/id/$lineItemId'),
      headers: _headers,
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return {'success': true};
      }
    }
    final data = jsonDecode(response.body);
    throw Exception(data['error'] ?? 'Failed to delete line item');
  }

  Future<Map<String, dynamic>> createBuyer(Map<String, dynamic> body) async {
    final response = await post('/invoice/buyer', body);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(data['error'] ?? 'Failed to create buyer');
    }
    return data;
  }

  Future<Map<String, dynamic>> patchBuyer(String buyerId, Map<String, dynamic> body) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/invoice/buyer/id/$buyerId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to update buyer');
    }
    return data;
  }
  Future<void> launchURL(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }
  // Google Maps Proxy methods
  Future<List<dynamic>> googleAutocomplete(String keyword, {String? sessionToken}) async {
    final queryParams = {'keyword': keyword};
    if (sessionToken != null) queryParams['sessiontoken'] = sessionToken;

    final uri = Uri.parse('$baseUrl/invoice/google/autocomplete').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['predictions'] ?? [];
    }
    return [];
  }

  Future<Map<String, dynamic>?> googlePlaceDetails(String placeId, {String? sessionToken}) async {
    final queryParams = {'placeId': placeId};
    if (sessionToken != null) queryParams['sessiontoken'] = sessionToken;

    final uri = Uri.parse('$baseUrl/invoice/google/details').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['result'];
    }
    return null;
  }

  Future<String?> googleReverseGeocode(double lat, double lng) async {
    final queryParams = {'lat': lat.toString(), 'lng': lng.toString()};
    final uri = Uri.parse('$baseUrl/invoice/google/reverse-geocode').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['address'];
    }
    return null;
  }

  Future<Map<String, dynamic>?> googleGeocode(String address) async {
    final queryParams = {'address': address};
    final uri = Uri.parse('$baseUrl/invoice/google/geocode').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'lat': data['lat'],
        'lng': data['lng'],
      };
    }
    return null;
  }

  Future<Map<String, dynamic>?> fetchVietQRBusiness(String taxId) async {
    final response = await http.get(Uri.parse('https://api.vietqr.io/v2/business/$taxId'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['code'] == '00' && decoded['data'] != null) {
        return decoded['data'] as Map<String, dynamic>;
      }
    }
    return null;
  }

  Future<List<dynamic>> getInvoices({
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
    bool? showDraft,
    bool? showSaved,
    bool? showLocked,
    String? buyerId,
    String? itemId,
    String? invoiceCode,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (limit != null) queryParams['limit'] = limit.toString();
    if (offset != null) queryParams['offset'] = offset.toString();
    if (sortBy != null) queryParams['sortBy'] = sortBy;
    if (sortOrder != null) queryParams['sortOrder'] = sortOrder;
    if (showDraft != null) queryParams['showDraft'] = showDraft.toString();
    if (showSaved != null) queryParams['showSaved'] = showSaved.toString();
    if (showLocked != null) queryParams['showLocked'] = showLocked.toString();
    if (buyerId != null) queryParams['buyerId'] = buyerId;
    if (itemId != null) queryParams['itemId'] = itemId;
    if (invoiceCode != null && invoiceCode.isNotEmpty) queryParams['invoiceCode'] = invoiceCode;
    if (startDate != null) {
      queryParams['startDate'] = startDate.toUtc().toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toUtc().toIso8601String();
    }

    final uri = Uri.parse('$baseUrl/invoice').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception('Failed to load invoices: ${response.body}');
  }

  Future<void> lockInvoice(String invoiceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/invoice/lock/invoiceId/$invoiceId'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to lock invoice');
    }
  }

  // Customer Price List methods
  Future<List<dynamic>> getCustomerPriceLists({
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
    String? buyerName,
    String? buyerId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final queryParams = <String, String>{};
    if (limit != null) queryParams['limit'] = limit.toString();
    if (offset != null) queryParams['offset'] = offset.toString();
    if (sortBy != null) queryParams['sortBy'] = sortBy;
    if (sortOrder != null) queryParams['sortOrder'] = sortOrder;
    if (buyerName != null && buyerName.isNotEmpty) queryParams['buyerName'] = buyerName;
    if (buyerId != null && buyerId.isNotEmpty) queryParams['buyerId'] = buyerId;
    if (startDate != null) {
      queryParams['startDate'] = startDate.toUtc().toIso8601String();
    }
    if (endDate != null) {
      queryParams['endDate'] = endDate.toUtc().toIso8601String();
    }

    final uri = Uri.parse('$baseUrl/pricelist').replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception('Failed to load customer price lists: ${response.body}');
  }

  Future<Map<String, dynamic>> getCustomerPriceList(String id) async {
    final response = await get('/pricelist/id/$id');
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to get customer price list');
  }

  Future<Map<String, dynamic>> createCustomerPriceList({
    required String description,
    String? buyerId,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await post('/pricelist', {
      'description': description,
      'buyerId': buyerId,
      'items': items,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to create customer price list');
  }

  Future<Map<String, dynamic>> updateCustomerPriceList(
    String id, {
    required String description,
    String? buyerId,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await patch('/pricelist/id/$id', {
      'description': description,
      'buyerId': buyerId,
      'items': items,
    });
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to update customer price list');
  }

  Future<Map<String, dynamic>> deleteCustomerPriceList(String id) async {
    final response = await delete('/pricelist/id/$id');
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to delete customer price list');
  }

  // Soft delete & restore for Item
  Future<Map<String, dynamic>> deleteItem(String id) async {
    final response = await delete('/item/id/$id');
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to delete item');
  }

  Future<Map<String, dynamic>> restoreItem(String id) async {
    final response = await post('/item/id/$id/restore', {});
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to restore item');
  }

  Future<List<dynamic>> getDeletedItems() async {
    final response = await get('/item/deleted');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to load deleted items');
  }

  // Soft delete & restore for Buyer
  Future<Map<String, dynamic>> deleteBuyer(String id) async {
    final response = await delete('/invoice/buyer/id/$id');
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to delete buyer');
  }

  Future<Map<String, dynamic>> restoreBuyer(String id) async {
    final response = await post('/invoice/buyer/id/$id/restore', {});
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to restore buyer');
  }

  Future<List<dynamic>> getDeletedBuyers() async {
    final response = await get('/invoice/buyer/deleted');
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to load deleted buyers');
  }

  // Soft delete & restore for Invoice
  Future<Map<String, dynamic>> deleteInvoice(String id) async {
    final response = await delete('/invoice/id/$id');
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to delete invoice');
  }

  Future<Map<String, dynamic>> restoreInvoice(String id) async {
    final response = await post('/invoice/id/$id/restore', {});
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to restore invoice');
  }

  Future<List<dynamic>> getDeletedInvoices() async {
    final response = await get('/invoice/deleted');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to load deleted invoices');
  }

  // Soft delete & restore for PriceList
  Future<Map<String, dynamic>> restoreCustomerPriceList(String id) async {
    final response = await post('/pricelist/id/$id/restore', {});
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to restore customer price list');
  }

  Future<List<dynamic>> getDeletedCustomerPriceLists() async {
    final response = await get('/pricelist/deleted');
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return decoded['data'] ?? [];
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to load deleted customer price lists');
  }

  Future<Map<String, dynamic>> changePriceItemOrder(String pricelistId, String customerItemPriceId, String? prevId, String? nextId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/pricelist/changeOrder/$pricelistId'),
      headers: _headers,
      body: jsonEncode({
        'customer_item_price_id': customerItemPriceId,
        'prev_customer_item_price_id': prevId,
        'next_customer_item_price_id': nextId,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Failed to change order');
  }
}

// TODO: Add pin top items.