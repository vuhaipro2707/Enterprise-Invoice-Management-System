import 'package:flutter/material.dart';

class UnitAutocompleteField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSelected;
  final String initialValue;
  final FormFieldValidator<String>? validator;
  final bool isDense;

  const UnitAutocompleteField({
    super.key,
    required this.controller,
    this.labelText = 'Đơn vị tính *',
    this.hintText = 'Cái, Thùng, Lon...',
    this.focusNode,
    this.onSelected,
    this.initialValue = '',
    this.validator,
    this.isDense = false,
  });

  // Common Vietnamese unit suggestions
  static const List<String> _unitSuggestions = [
    'Thùng', 'Túi', 'Hộp', 'Chai', 'Két',
    'Cái', 'Lon', 'Gói', 'Bao', 'Bình',
    'Lít', 'Kg', 'Gram', 'Mét', 'Cuộn',
    'Tấm', 'Đôi', 'Bộ', 'Chiếc', 'Viên',
  ];

  /// Normalize a string: lowercase + strip Vietnamese diacritics.
  static String _unaccent(String s) {
    const map = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
      'ă': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'ấ': 'a', 'ầ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'đ': 'd',
      'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ế': 'e', 'ề': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'ọ': 'o', 'ỏ': 'o',
      'ố': 'o', 'ồ': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ớ': 'o', 'ờ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ứ': 'u', 'ừ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
    };
    return s.toLowerCase().split('').map((c) => map[c] ?? c).join();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      key: ValueKey(initialValue),
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) return const Iterable.empty();
        final query = _unaccent(textEditingValue.text);
        return _unitSuggestions.where(
          (unit) => _unaccent(unit).contains(query),
        );
      },
      onSelected: (String selection) {
        controller.text = selection;
        if (onSelected != null) {
          onSelected!(selection);
        }
      },
      fieldViewBuilder: (context, textController, fieldFocusNode, onFieldSubmitted) {
        // Keep external controller and Autocomplete's internal controller in sync
        if (textController.text != controller.text) {
          textController.text = controller.text;
        }
        
        return TextFormField(
          controller: textController,
          focusNode: focusNode ?? fieldFocusNode,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
            hintText: hintText,
            suffixIcon: const Icon(Icons.expand_more),
            isDense: isDense,
          ),
          onChanged: (value) {
            controller.text = value;
          },
          validator: validator,
          onTap: () {
            // Wait for keyboard animation to fully complete and viewport to resize (500ms)
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                Scrollable.ensureVisible(
                  context,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: 0.05, // Align near the top of the viewport
                );
              }
            });
          },
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.straighten_rounded, size: 18),
                    title: Text(option),
                    onTap: () => onSelectedOption(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
