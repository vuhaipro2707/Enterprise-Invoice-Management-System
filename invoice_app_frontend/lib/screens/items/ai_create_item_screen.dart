import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/currency_formatter.dart';
import '../../widgets/type_selection_sheet.dart';

class AICreateItemScreen extends StatefulWidget {
  final List<dynamic> types;
  final String? initialKeyword;

  const AICreateItemScreen({super.key, required this.types, this.initialKeyword});

  @override
  State<AICreateItemScreen> createState() => _AICreateItemScreenState();
}

class _AICreateItemScreenState extends State<AICreateItemScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');

  late List<dynamic> _types;
  dynamic _selectedType;
  bool _isSearchingAI = false;
  bool _isSavingBatch = false;
  bool _showTypeWarning = false;
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _aiResponse;
  final Map<int, List<String>> _selectedOptions = {};
  final Map<String, Map<String, TextEditingController>> _priceControllers = {};
  final Map<String, Map<String, TextEditingController>> _ratioControllers = {};
  final Map<String, Map<String, FocusNode>> _priceFocusNodes = {};
  final Map<String, bool> _combinationSelection = {};
  bool _showDraftDetail = false;


  @override
  void initState() {
    super.initState();
    _types = List.from(widget.types);
    if (_types.isNotEmpty) {
      _selectedType = null; // Default to uncategorized, user selects optionally
    }
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      _searchController.text = widget.initialKeyword!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queryGeminiAI();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _disposePriceControllers();
    super.dispose();
  }

  void _disposePriceControllers() {
    for (var innerMap in _priceControllers.values) {
      for (var ctrl in innerMap.values) {
        ctrl.dispose();
      }
    }
    _priceControllers.clear();
    for (var innerMap in _ratioControllers.values) {
      for (var ctrl in innerMap.values) {
        ctrl.dispose();
      }
    }
    _ratioControllers.clear();
    for (var innerMap in _priceFocusNodes.values) {
      for (var node in innerMap.values) {
        node.dispose();
      }
    }
    _priceFocusNodes.clear();
  }

  void _selectType() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => TypeSelectionSheet(
        initialTypes: _types,
        onTypeSelected: (type) {
          setState(() {
            _selectedType = type;
            _showTypeWarning = false;
          });
        },
        onTypeCreated: (newType) {
          setState(() {
            _types.add(newType);
            _selectedType = newType;
            _showTypeWarning = false;
          });
        },
      ),
    );
  }

  Future<void> _queryGeminiAI() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập từ khóa tìm kiếm sản phẩm')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearchingAI = true;
      _aiResponse = null;
      _showDraftDetail = false;
      _disposePriceControllers();
      _selectedOptions.clear();
      _combinationSelection.clear();
    });

    try {
      final suggestions = await _apiService.generateItemAISuggestions(keyword);
      
      if (!mounted) return;

      setState(() {
        _aiResponse = suggestions;
        
        // Parse segments & do not select by default (user will select explicitly)
        final segments = suggestions['nameSegments'] as List<dynamic>? ?? [];
        for (int i = 0; i < segments.length; i++) {
          final seg = segments[i];
          if (seg['type'] == 'options') {
            _selectedOptions[i] = [];
          }
        }

        // Initialize price and ratio controllers for conditional units
        final condUnits = suggestions['conditionalUnits'] as Map<String, dynamic>? ?? {};
        condUnits.forEach((optionName, unitsList) {
          _priceControllers[optionName] = {};
          _ratioControllers[optionName] = {};
          _priceFocusNodes[optionName] = {};
          final list = unitsList as List<dynamic>;
          
          // Find base unit for ratio linkage
          final baseUnit = list.firstWhere((u) => (u['ratio'] as int) == 1, orElse: () => null);
          final baseUnitName = baseUnit != null ? baseUnit['unitName'] as String : '';

          for (var u in list) {
            final uName = u['unitName'] as String;
            final suggestionPrice = u['priceSuggestion'] as int? ?? 0;
            final ratioVal = (u['ratio'] as num).toInt();
            
            final controller = TextEditingController(
              text: _currencyFormatter.format(suggestionPrice),
            );
            final ratioController = TextEditingController(
              text: ratioVal.toString(),
            );
            
            _priceControllers[optionName]![uName] = controller;
            _ratioControllers[optionName]![uName] = ratioController;
            _priceFocusNodes[optionName]![uName] = FocusNode();

            // Listen to ratio changes to update the model and computed price
            if (ratioVal > 1) {
              ratioController.addListener(() {
                final newRatio = int.tryParse(ratioController.text.trim()) ?? 1;
                u['ratio'] = newRatio;

                if (baseUnitName.isNotEmpty) {
                  final baseCtrl = _priceControllers[optionName]![baseUnitName];
                  if (baseCtrl != null && baseCtrl.text.isNotEmpty) {
                    final basePrice = int.tryParse(baseCtrl.text.replaceAll('.', '').trim()) ?? 0;
                    final computedPrice = basePrice * newRatio;
                    controller.text = _currencyFormatter.format(computedPrice);
                  }
                }
              });
            }
          }

          // Link unit price changes as real-time pricing assistance
          for (var u in list) {
            final uName = u['unitName'] as String;
            final ratio = u['ratio'] as int;
            final isBase = ratio == 1;
            final controller = _priceControllers[optionName]![uName];
            final focusNode = _priceFocusNodes[optionName]![uName];

            if (controller != null && focusNode != null) {
              controller.addListener(() {
                // Only propagate changes if the user is actively editing this field
                if (!focusNode.hasFocus) return;

                final rawPrice = controller.text.replaceAll('.', '').trim();
                
                setState(() {
                  if (rawPrice.isEmpty) return;

                  final currentPrice = int.tryParse(rawPrice) ?? 0;

                  if (isBase) {
                    // If base unit is changed, multiply by ratio for all larger units
                    for (var otherUnit in list) {
                      final otherName = otherUnit['unitName'] as String;
                      final otherRatio = otherUnit['ratio'] as int;
                      if (otherRatio > 1) {
                        final targetController = _priceControllers[optionName]![otherName];
                        if (targetController != null) {
                          final computedPrice = currentPrice * otherRatio;
                          targetController.text = _currencyFormatter.format(computedPrice);
                        }
                      }
                    }
                  } else {
                    // If a larger unit is changed, divide by ratio to get base unit price,
                    // and then update all other larger units as well!
                    if (baseUnit != null) {
                      final baseUnitName = baseUnit['unitName'] as String;
                      final baseController = _priceControllers[optionName]![baseUnitName];
                      if (baseController != null) {
                        final computedBasePrice = (currentPrice / ratio).round();
                        baseController.text = _currencyFormatter.format(computedBasePrice);

                        // Also update other larger units based on the new base price
                        for (var otherUnit in list) {
                          final otherName = otherUnit['unitName'] as String;
                          final otherRatio = otherUnit['ratio'] as int;
                          if (otherName != uName && otherRatio > 1) {
                            final targetController = _priceControllers[optionName]![otherName];
                            if (targetController != null) {
                              final computedPrice = computedBasePrice * otherRatio;
                              targetController.text = _currencyFormatter.format(computedPrice);
                            }
                          }
                        }
                      }
                    }
                  }
                });
              });
            }
          }
        });

        // Initialize selections for combinations
        final combinations = _generateCombinations();
        for (var c in combinations) {
          _combinationSelection[c['itemName']] = true;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi AI: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingAI = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _generateCombinations() {
    if (_aiResponse == null) return [];
    final segments = _aiResponse!['nameSegments'] as List<dynamic>? ?? [];

    List<List<String>> segmentVariants = [];
    List<String> segmentQuyCachOptions = [];

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final type = seg['type'];
      if (type == 'text') {
        segmentVariants.add([seg['content'] as String]);
      } else if (type == 'options') {
        final selected = _selectedOptions[i] ?? [];
        if (selected.isEmpty) {
          return [];
        }
        segmentVariants.add(selected);
        if (seg['id'] == 'specification') {
          segmentQuyCachOptions = selected;
        }
      }
    }

    // Generate Cartesian product
    List<List<String>> cp = [[]];
    for (var list in segmentVariants) {
      List<List<String>> temp = [];
      for (var prefix in cp) {
        for (var item in list) {
          temp.add([...prefix, item]);
        }
      }
      cp = temp;
    }

    // Parse valid combinations if provided by AI
    final validCombsRaw = _aiResponse!['validCombinations'] as List<dynamic>?;
    List<List<String>>? validCombinations;
    if (validCombsRaw != null) {
      validCombinations = [];
      for (var entry in validCombsRaw) {
        if (entry is List) {
          validCombinations.add(entry.map((e) => e.toString()).toList());
        }
      }
    }

    List<Map<String, dynamic>> results = [];
    for (var combinationParts in cp) {
      // Filter out combinations not present in validCombinations (if provided)
      if (validCombinations != null && validCombinations.isNotEmpty) {
        bool isValid = false;
        for (var validEntry in validCombinations) {
          bool matchAll = true;
          for (var item in validEntry) {
            if (!combinationParts.contains(item)) {
              matchAll = false;
              break;
            }
          }
          if (matchAll) {
            isValid = true;
            break;
          }
        }
        if (!isValid) {
          continue;
        }
      }

      String name = combinationParts.join(' ');
      if (segments.isNotEmpty && segments[0]['type'] == 'options' && name.isNotEmpty) {
        name = name[0].toUpperCase() + name.substring(1);
      }

      String? matchedQuyCach;
      for (var qc in segmentQuyCachOptions) {
        if (combinationParts.contains(qc)) {
          matchedQuyCach = qc;
          break;
        }
      }

      List<Map<String, dynamic>> unitsPayload = [];
      if (matchedQuyCach != null && _aiResponse!['conditionalUnits'] != null) {
        final rawUnits = _aiResponse!['conditionalUnits'][matchedQuyCach] as List<dynamic>?;
        if (rawUnits != null) {
          for (var ru in rawUnits) {
            final uName = ru['unitName'] as String;
            final uRatio = (ru['ratio'] as num).toInt();
            final isBase = uRatio == 1;

            final controller = _priceControllers[matchedQuyCach]?[uName];
            int? priceVal;
            if (controller != null && controller.text.isNotEmpty) {
              priceVal = int.tryParse(controller.text.replaceAll('.', '').trim());
            }

            unitsPayload.add({
              'unitName': uName,
              'ratio': uRatio,
              'isBaseUnit': isBase,
              'unitPriceDefault': priceVal,
            });
          }
        }
      } else {
        const baseUnitName = 'Cái';
        unitsPayload.add({
          'unitName': baseUnitName,
          'ratio': 1,
          'isBaseUnit': true,
          'unitPriceDefault': null,
        });
      }

      results.add({
        'itemName': name,
        'otherNames': <String>[],
        'units': unitsPayload,
        'quyCachOption': matchedQuyCach,
      });
    }

    return results;
  }

  void _showWarningAndScroll() {
    setState(() {
      _showTypeWarning = true;
    });
    
    // Auto-scroll to the top smoothly to highlight the warning card
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colorScheme.onError),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vui lòng chọn loại mặt hàng trước khi lưu!',
                style: TextStyle(color: colorScheme.onError, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _saveDirectSelectedItems(List<Map<String, dynamic>> selectedItems) async {
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một tổ hợp để lưu')),
      );
      return;
    }

    if (_selectedType == null) {
      final aiSuggestedType = _aiResponse != null ? _aiResponse!['type'] as String? : null;
      if (aiSuggestedType != null && aiSuggestedType.trim().isNotEmpty) {
        final cleanType = aiSuggestedType.trim();
        final matchedType = _types.firstWhere(
          (t) => t['typeName'].toString().toLowerCase() == cleanType.toLowerCase(),
          orElse: () => null,
        );

        if (matchedType != null) {
          final useAiType = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              final colorScheme = Theme.of(dialogContext).colorScheme;
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Gợi ý phân loại'),
                  ],
                ),
                content: RichText(
                  text: TextSpan(
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
                    children: [
                      const TextSpan(text: 'Gemini gợi ý loại sản phẩm này là '),
                      TextSpan(
                        text: '"$cleanType"',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                      const TextSpan(text: '.\n\nBạn có muốn tự động chọn phân loại này và tiếp tục lưu không?'),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(
                      'Hủy',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Đồng ý & Lưu'),
                  ),
                ],
              );
            },
          );

          if (useAiType == true) {
            setState(() {
              _selectedType = matchedType;
              _showTypeWarning = false;
            });
          } else {
            _showWarningAndScroll();
            return;
          }
        } else {
          final createAndUseAiType = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              final colorScheme = Theme.of(dialogContext).colorScheme;
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Gợi ý phân loại mới'),
                  ],
                ),
                content: RichText(
                  text: TextSpan(
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
                    children: [
                      const TextSpan(text: 'Gemini gợi ý loại sản phẩm này là '),
                      TextSpan(
                        text: '"$cleanType"',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                      const TextSpan(text: ', nhưng phân loại này chưa tồn tại.\n\nBạn có muốn tạo mới loại hàng này và tự động thêm sản phẩm vào không?'),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(
                      'Hủy',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Tạo & Lưu'),
                  ),
                ],
              );
            },
          );

          if (createAndUseAiType == true) {
            setState(() => _isSavingBatch = true);
            try {
              final result = await _apiService.createType(cleanType);
              final newType = result['data'];
              if (newType != null) {
                setState(() {
                  _types.add(newType);
                  _selectedType = newType;
                  _showTypeWarning = false;
                });
              }
            } catch (e) {
              setState(() => _isSavingBatch = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi khi tạo phân loại gợi ý: $e'),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
              return;
            } finally {
              if (mounted) {
                setState(() => _isSavingBatch = false);
              }
            }
          } else {
            _showWarningAndScroll();
            return;
          }
        }
      } else {
        _showWarningAndScroll();
        return;
      }
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.save_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Xác nhận lưu'),
            ],
          ),
          content: Text(
            'Bạn có chắc chắn muốn lưu ${selectedItems.length} sản phẩm?',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                'Hủy',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isSavingBatch = true);

    try {
      final typeId = _selectedType != null ? _selectedType['typeId'] as String : null;
      
      final response = await _apiService.batchCreateItems(
        typeId: typeId,
        items: selectedItems,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Đã lưu các mặt hàng thành công!'),
          duration: const Duration(seconds: 2),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi lưu các mặt hàng: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingBatch = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final combinations = _generateCombinations();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tạo mặt hàng bằng AI', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Kết quả được đề xuất bởi Gemini AI', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type selector card
                    _buildTypeSelectorCard(),
                    const SizedBox(height: 16),

                    // AI search bar card
                    _buildAISearchCard(),
                    const SizedBox(height: 20),

                    // AI Loading State
                    if (_isSearchingAI) _buildAILoadingWidget(),

                    // Main options configuration area
                    if (_aiResponse != null) ...[
                      if (_aiResponse!['draft'] != null && _aiResponse!['draft'].toString().trim().isNotEmpty) ...[
                        _buildAIDraftWidget(_aiResponse!['draft'].toString()),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'Thiết lập biến thể & gợi ý giá',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildOptionsConfigurator(),
                      const SizedBox(height: 20),
                      if (combinations.isEmpty) ...[
                        Card(
                          elevation: 0,
                          color: colorScheme.primaryContainer.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: colorScheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Hãy chọn ít nhất một tùy chọn ở mỗi nhóm biến thể bên trên để xem trước tổ hợp sản phẩm và thiết lập giá.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      _buildPriceEditors(),
                      const SizedBox(height: 20),

                      _buildCombinationPreview(combinations),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIDraftWidget(String draft) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _showDraftDetail = !_showDraftDetail;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nháp phân tích từ Gemini AI',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _showDraftDetail
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_showDraftDetail) ...[
            const Divider(height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  draft,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeSelectorCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasWarning = _showTypeWarning && _selectedType == null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: hasWarning ? colorScheme.errorContainer.withValues(alpha: 0.1) : colorScheme.surfaceContainer,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: hasWarning ? colorScheme.error : colorScheme.outlineVariant,
              width: hasWarning ? 2.0 : 1.0,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _selectType,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.category_rounded,
                    color: hasWarning ? colorScheme.error : colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phân loại mặt hàng mới',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasWarning ? colorScheme.error : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _selectedType != null ? _selectedType['typeName'] : 'Chưa chọn phân loại (bắt buộc)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: hasWarning ? colorScheme.error : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: hasWarning ? colorScheme.error : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selectedType == null && _aiResponse != null && _aiResponse!['type'] != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final aiSuggestedType = _aiResponse!['type'].toString().trim();
                      final matchedType = _types.firstWhere(
                        (t) => t['typeName'].toString().toLowerCase() == aiSuggestedType.toLowerCase(),
                        orElse: () => null,
                      );
                      if (matchedType != null) {
                        setState(() {
                          _selectedType = matchedType;
                          _showTypeWarning = false;
                        });
                      } else {
                        final selectedItems = _generateCombinations()
                            .where((c) => _combinationSelection[c['itemName']] == true)
                            .toList();
                        _saveDirectSelectedItems(selectedItems);
                      }
                    },
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        children: [
                          const TextSpan(text: 'AI gợi ý phân loại: '),
                          TextSpan(
                            text: '"${_aiResponse!['type']}"',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const TextSpan(text: ' (Bấm để chọn nhanh)'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (hasWarning) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: colorScheme.error),
                const SizedBox(width: 6),
                Text(
                  'Vui lòng chọn loại mặt hàng trước khi lưu sản phẩm.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAISearchCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tìm kiếm nhanh trên thị trường bằng AI',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Nhập từ khóa (Ví dụ: Mì hảo hảo, Cà phê sữa...)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    onSubmitted: (_) => _queryGeminiAI(),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSearchingAI ? null : _queryGeminiAI,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Tìm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAILoadingWidget() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          CircularProgressIndicator(
            color: colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'AI đang nghiên cứu thị trường...',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Đi tìm nhãn hiệu, đơn vị tính, trọng lượng và đề xuất giá quy đổi chính xác nhất.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsConfigurator() {
    final segments = _aiResponse!['nameSegments'] as List<dynamic>? ?? [];
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: List.generate(segments.length, (segIdx) {
        final seg = segments[segIdx];
        if (seg['type'] == 'text') {
          return Card(
            elevation: 0,
            color: colorScheme.surfaceContainer,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: ListTile(
              leading: const Icon(Icons.bookmark_rounded),
              title: Text(
                'Thương hiệu / Tên gốc',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              subtitle: Text(
                seg['content'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          );
        }

        final title = seg['title'] as String? ?? 'Tùy chọn';
        final isQuyCach = seg['id'] == 'specification';
        final options = List<String>.from(seg['options'] ?? []);
        final selected = _selectedOptions[segIdx] ?? [];

        return Card(
          elevation: 0,
          color: colorScheme.surface,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isQuyCach ? Icons.grid_view_rounded : Icons.palette_rounded,
                      color: colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((opt) {
                    final isChecked = selected.contains(opt);
                    return FilterChip(
                      selected: isChecked,
                      label: Text(opt),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            selected.add(opt);
                          } else {
                            selected.remove(opt);
                          }
                          _selectedOptions[segIdx] = selected;
                          
                          // Refresh combinations selection
                          final newCombs = _generateCombinations();
                          for (var nc in newCombs) {
                            if (!_combinationSelection.containsKey(nc['itemName'])) {
                              _combinationSelection[nc['itemName']] = true;
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPriceEditors() {
    final colorScheme = Theme.of(context).colorScheme;

    // Find the specification segment
    final segments = _aiResponse!['nameSegments'] as List<dynamic>? ?? [];
    int quyCachIdx = -1;
    for (int i = 0; i < segments.length; i++) {
      if (segments[i]['id'] == 'specification') {
        quyCachIdx = i;
        break;
      }
    }

    if (quyCachIdx == -1) return const SizedBox.shrink();

    final selectedQuyCach = _selectedOptions[quyCachIdx] ?? [];
    if (selectedQuyCach.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.monetization_on_rounded, color: colorScheme.secondary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Thiết lập giá động theo Quy cách',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Thay đổi giá đơn vị gốc sẽ tự động nhân lên đơn vị thùng/lốc tương ứng.',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        ...selectedQuyCach.map((qcOption) {
          final controllersMap = _priceControllers[qcOption];
          if (controllersMap == null) return const SizedBox.shrink();

          final condUnits = _aiResponse!['conditionalUnits']?[qcOption] as List<dynamic>? ?? [];

          return Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_rounded, size: 16, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Text(
                        'Quy cách: $qcOption',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...condUnits.map((u) {
                    final uName = u['unitName'] as String;
                    final ratio = u['ratio'] as int;
                    final isBase = ratio == 1;
                    final controller = controllersMap[uName];
                    final focusNode = _priceFocusNodes[qcOption]?[uName];

                    if (controller == null) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              uName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isBase ? FontWeight.bold : FontWeight.normal,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: isBase
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Gốc (x1)',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                : SizedBox(
                                    height: 40,
                                    child: TextField(
                                      controller: _ratioControllers[qcOption]?[uName],
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        prefixText: 'x ',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        labelText: 'Quy đổi',
                                        labelStyle: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                controller: controller,
                                focusNode: focusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: InputDecoration(
                                  suffixText: 'đ',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showAddUnitDialog(context, qcOption),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Thêm đơn vị quy đổi', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showAddUnitDialog(BuildContext parentContext, String qcOption) {
    final colorScheme = Theme.of(parentContext).colorScheme;
    final nameController = TextEditingController();
    final ratioController = TextEditingController();
    final priceController = TextEditingController();

    final list = _aiResponse!['conditionalUnits']?[qcOption] as List<dynamic>? ?? [];
    final baseUnit = list.firstWhere((u) => (u['ratio'] as int) == 1, orElse: () => null);

    int basePrice = 0;
    if (baseUnit != null) {
      final baseUnitName = baseUnit['unitName'] as String;
      final baseCtrl = _priceControllers[qcOption]?[baseUnitName];
      if (baseCtrl != null && baseCtrl.text.isNotEmpty) {
        basePrice = int.tryParse(baseCtrl.text.replaceAll('.', '').trim()) ?? 0;
      }
    }

    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            ratioController.addListener(() {
              final ratioStr = ratioController.text.trim();
              if (ratioStr.isNotEmpty) {
                final ratio = int.tryParse(ratioStr) ?? 0;
                if (ratio > 1 && basePrice > 0) {
                  final computed = basePrice * ratio;
                  priceController.text = _currencyFormatter.format(computed);
                }
              }
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.add_box_rounded, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Thêm đơn vị quy đổi'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên đơn vị tính (ví dụ: Thùng, Lốc)',
                        hintText: 'Nhập tên đơn vị tính',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ratioController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tỷ lệ quy đổi so với đơn vị gốc',
                        hintText: 'Ví dụ: 1 thùng = 24 chai thì nhập 24',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Giá bán đề xuất (đ)',
                        hintText: 'Nhập giá bán',
                        border: OutlineInputBorder(),
                        suffixText: 'đ',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Hủy',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final ratioStr = ratioController.text.trim();
                    final priceStr = priceController.text.replaceAll('.', '').trim();

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập tên đơn vị tính')),
                      );
                      return;
                    }

                    final ratio = int.tryParse(ratioStr) ?? 0;
                    if (ratio <= 1) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(content: Text('Tỷ lệ quy đổi phải lớn hơn 1')),
                      );
                      return;
                    }

                    final exists = list.any((u) => u['unitName'].toString().toLowerCase() == name.toLowerCase());
                    if (exists) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text('Đơn vị "$name" đã tồn tại cho quy cách này')),
                      );
                      return;
                    }

                    final price = int.tryParse(priceStr) ?? 0;

                    Navigator.pop(dialogContext);

                    if (mounted) {
                      setState(() {
                        final newUnitMap = {
                          'unitName': name,
                          'ratio': ratio,
                          'priceSuggestion': price,
                        };
                        _aiResponse!['conditionalUnits']?[qcOption].add(newUnitMap);

                        final ctrl = TextEditingController(text: _currencyFormatter.format(price));
                        final node = FocusNode();
                        _priceControllers[qcOption]![name] = ctrl;
                        _priceFocusNodes[qcOption]![name] = node;

                        final rCtrl = TextEditingController(text: ratio.toString());
                        _ratioControllers[qcOption]![name] = rCtrl;

                        rCtrl.addListener(() {
                          final newRatio = int.tryParse(rCtrl.text.trim()) ?? 1;
                          newUnitMap['ratio'] = newRatio;

                          if (baseUnit != null) {
                            final baseUnitName = baseUnit['unitName'] as String;
                            final baseCtrl = _priceControllers[qcOption]?[baseUnitName];
                            if (baseCtrl != null && baseCtrl.text.isNotEmpty) {
                              final basePrice = int.tryParse(baseCtrl.text.replaceAll('.', '').trim()) ?? 0;
                              final computedPrice = basePrice * newRatio;
                              ctrl.text = _currencyFormatter.format(computedPrice);
                            }
                          }
                        });

                        ctrl.addListener(() {
                          if (!node.hasFocus) return;

                          final rawPrice = ctrl.text.replaceAll('.', '').trim();
                          if (rawPrice.isEmpty) return;

                          final currentPrice = int.tryParse(rawPrice) ?? 0;

                          if (baseUnit != null) {
                            final baseUnitName = baseUnit['unitName'] as String;
                            final baseController = _priceControllers[qcOption]?[baseUnitName];
                            if (baseController != null) {
                              final computedBasePrice = (currentPrice / ratio).round();
                              baseController.text = _currencyFormatter.format(computedBasePrice);

                              for (var otherUnit in _aiResponse!['conditionalUnits']?[qcOption]) {
                                final otherName = otherUnit['unitName'] as String;
                                final otherRatio = otherUnit['ratio'] as int;
                                if (otherName != name && otherRatio > 1) {
                                  final targetController = _priceControllers[qcOption]?[otherName];
                                  if (targetController != null) {
                                    final computedPrice = computedBasePrice * otherRatio;
                                    targetController.text = _currencyFormatter.format(computedPrice);
                                  }
                                }
                              }
                            }
                          }
                        });
                      });
                    }
                  },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCombinationPreview(List<Map<String, dynamic>> combs) {
    if (combs.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Xem trước tổ hợp (${combs.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final allSelected = combs.every((c) => _combinationSelection[c['itemName']] == true);
                    setState(() {
                      for (var c in combs) {
                        _combinationSelection[c['itemName']] = !allSelected;
                      }
                    });
                  },
                  child: Text(
                    combs.every((c) => _combinationSelection[c['itemName']] == true)
                        ? 'Bỏ chọn hết'
                        : 'Chọn tất cả',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: combs.length,
              itemBuilder: (context, idx) {
                final comb = combs[idx];
                final name = comb['itemName'] as String;
                final units = comb['units'] as List<Map<String, dynamic>>;
                final isChecked = _combinationSelection[name] ?? false;

                // Format summary price string
                final priceSummary = units.map((u) {
                  final uName = u['unitName'];
                  final price = u['unitPriceDefault'];
                  final formattedPrice = price != null ? _currencyFormatter.format(price) : 'Chưa nhập';
                  return '$uName: $formattedPriceđ';
                }).join(' / ');

                return CheckboxListTile(
                  title: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    priceSummary,
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  value: isChecked,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (val) {
                    setState(() {
                      _combinationSelection[name] = val ?? false;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingBatch
                    ? null
                    : () {
                        final freshCombs = _generateCombinations();
                        final selectedItems = freshCombs
                            .where((c) => _combinationSelection[c['itemName']] == true)
                            .toList();
                        _saveDirectSelectedItems(selectedItems);
                      },
                icon: _isSavingBatch
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(
                  _isSavingBatch
                      ? 'Đang lưu các mặt hàng...'
                      : 'Lưu ${combs.where((c) => _combinationSelection[c['itemName']] == true).length} mặt hàng đã chọn',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
