import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
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
  bool _isCheckingUpdate = false;
  String? _currentDeviceName;
  String _localVersion = 'Đang tải...';

  @override
  void initState() {
    super.initState();
    _loadDeviceData();
    _loadAppVersion();
  }

  Future<void> _loadDeviceData() async {
    try {
      final result = await ApiService().checkRegistered();
      if (mounted) {
        setState(() {
          if (result['registered'] == true) {
            final data = result['data'];
            final deviceName = data['deviceName'];
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

  Future<void> _loadAppVersion() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _localVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localVersion = 'Không rõ';
        });
      }
    }
  }

  bool _isUpdateAvailable(String localStr, String serverStr) {
    if (kDebugMode) return true;

    try {
      final localParts = localStr.split('+');
      final serverParts = serverStr.split('+');

      final localName = localParts[0];
      final serverName = serverParts[0];

      if (localParts.length > 1 && serverParts.length > 1) {
        final localBuild = int.tryParse(localParts[1]);
        final serverBuild = int.tryParse(serverParts[1]);
        if (localBuild != null && serverBuild != null) {
          return serverBuild > localBuild;
        }
      }

      final localSubparts = localName.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final serverSubparts = serverName.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (var i = 0; i < 3; i++) {
        final l = i < localSubparts.length ? localSubparts[i] : 0;
        final s = i < serverSubparts.length ? serverSubparts[i] : 0;
        if (s > l) return true;
        if (l > s) return false;
      }
    } catch (e) {
      debugPrint('Error comparing versions: $e');
    }
    return false;
  }

  Future<void> _checkUpdate() async {
    setState(() => _isCheckingUpdate = true);
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String localVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      final result = await ApiService().getLatestVersion();
      final String serverVersion = result['version'] ?? '';

      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      final hasUpdate = _isUpdateAvailable(localVersion, serverVersion);

      if (hasUpdate) {
        _showUpdateDialog(localVersion, serverVersion);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phiên bản hiện tại ($localVersion) đã là mới nhất!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kiểm tra cập nhật: ${e.toString()}')),
        );
      }
    }
  }

  void _showUpdateDialog(String currentVer, String newVer) {
    double downloadProgress = 0.0;
    bool isDownloading = false;
    String downloadStatus = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext builderContext, StateSetter setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.system_update_alt,
                    color: Theme.of(builderContext).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text('Bản Cập Nhật Mới!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isDownloading) ...[
                    Text(
                      'Đã tìm thấy phiên bản mới của ứng dụng.',
                      style: Theme.of(builderContext).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Phiên bản hiện tại:', style: TextStyle(color: Colors.grey[600])),
                        Text(currentVer, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Phiên bản mới nhất:', style: TextStyle(color: Colors.grey[600])),
                        Text(
                          newVer,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(builderContext).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '(Chế độ Debug: Luôn coi như có cập nhật để test)',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange),
                      ),
                    ],
                  ] else ...[
                    Text(
                      downloadStatus,
                      style: Theme.of(builderContext).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (downloadProgress >= 0) ...[
                      LinearProgressIndicator(
                        value: downloadProgress,
                        backgroundColor: Theme.of(builderContext).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(builderContext).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(downloadProgress * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(builderContext).colorScheme.primary,
                        ),
                      ),
                    ] else ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Đang tải...', textAlign: TextAlign.center),
                    ],
                  ],
                ],
              ),
              actions: [
                if (!isDownloading) ...[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Để sau'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setDialogState(() {
                        isDownloading = true;
                        downloadStatus = 'Đang chuẩn bị tải về...';
                        downloadProgress = 0.0;
                      });

                      try {
                        final tempDir = await getTemporaryDirectory();
                        final String savePath = '${tempDir.path}/app-release.apk';

                        await ApiService().downloadApk(savePath, (progress) {
                          setDialogState(() {
                            downloadProgress = progress;
                            downloadStatus = 'Đang tải bản cập nhật...';
                          });
                        });

                        setDialogState(() {
                          downloadStatus = 'Cài đặt bản cập nhật...';
                        });

                        final openResult = await OpenFilex.open(savePath);
                        
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }

                        if (openResult.type != ResultType.done) {
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Không thể cài đặt APK: ${openResult.message}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Lỗi tải xuống: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Cập nhật ngay'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
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
                      if (!kIsWeb) ...[
                        const SizedBox(height: 32),
                        Card(
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Thông tin phiên bản',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('Phiên bản hiện tại:'),
                                    Text(
                                      _localVersion,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _isCheckingUpdate ? null : _checkUpdate,
                                  icon: _isCheckingUpdate
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh),
                                  label: const Text('Kiểm tra cập nhật'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
