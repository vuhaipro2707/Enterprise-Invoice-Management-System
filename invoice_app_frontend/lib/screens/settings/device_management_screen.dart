import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _currentDeviceName;

  @override
  void initState() {
    super.initState();
    _loadDeviceData();
  }

  Future<void> _loadDeviceData() async {
    try {
      final result = await ApiService().checkRegistered();
      if (mounted) {
        setState(() {
          if (result['registered'] == true) {
            final data = result['data'];
            final deviceName = data['device_name'];
            if (deviceName is Map) {
              _currentDeviceName = deviceName['String'];
            } else {
              _currentDeviceName = deviceName;
            }
            _nameController.text = _currentDeviceName ?? '';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi tải thông tin thiết bị')),
        );
      }
    }
  }

  Future<void> _updateName() async {
    if (_nameController.text.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await ApiService().registerDevice(_nameController.text);
      if (mounted) {
        setState(() {
          _currentDeviceName = _nameController.text;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật tên thiết bị thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi cập nhật tên thiết bị')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Thiết bị'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Icon(Icons.devices, size: 64, color: Colors.blue),
                              const SizedBox(height: 16),
                              Text(
                                'Thiết bị hiện tại',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                _currentDeviceName ?? 'Chưa đăng ký',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Đổi tên thiết bị',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.edit),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _updateName,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator()
                            : const Text('Lưu thay đổi'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
