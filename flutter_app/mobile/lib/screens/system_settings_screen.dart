import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final List<String> _commonSettings = [
    'maintenance_mode',
    'max_login_attempts',
    'session_timeout_minutes',
    'backup_frequency_hours',
    'log_retention_days',
    'default_currency',
    'timezone',
  ];

  // Zimbabwe-specific settings options
  final List<String> _currencies = [
    'ZWL', // Zimbabwe Dollar (primary)
    'USD', // US Dollar (commonly used)
    'EUR', // Euro
    'GBP', // British Pound
    'ZAR', // South African Rand
    'BWP', // Botswana Pula
    'MWK', // Malawian Kwacha
    'MZN', // Mozambican Metical
    'SZL', // Swazi Lilangeni
    'LSL', // Lesotho Loti
  ];

  final List<String> _timezones = [
    'Africa/Harare', // Zimbabwe (primary)
    'Africa/Johannesburg', // South Africa
    'Africa/Lusaka', // Zambia
    'Africa/Maputo', // Mozambique
    'Africa/Gaborone', // Botswana
    'Africa/Lilongwe', // Malawi
    'UTC',
  ];

  final List<String> _booleanOptions = ['true', 'false'];

  @override
  void initState() {
    super.initState();
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    // Initialize controllers for common settings
    for (final key in _commonSettings) {
      _controllers[key] = TextEditingController();
    }

    // Load settings if not already loaded (defer until after build)
    if (settingsProvider.systemSettings == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settingsProvider.loadSystemSettings();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Settings'),
        backgroundColor: AppColors.primaryBrand,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAllSettings,
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          if (settingsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Update controllers when settings load
          if (settingsProvider.systemSettings != null) {
            for (final entry
                in settingsProvider.systemSettings!.settings.entries) {
              if (_controllers.containsKey(entry.key)) {
                _controllers[entry.key]!.text = entry.value ?? '';
              }
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'System Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'These settings affect the entire system. Changes take effect immediately.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),

                // Maintenance Mode
                _buildBooleanDropdownField(
                  'Maintenance Mode',
                  'maintenance_mode',
                  'Enable/disable maintenance mode',
                ),

                const SizedBox(height: 16),

                // Max Login Attempts
                _buildSettingField(
                  'Max Login Attempts',
                  'max_login_attempts',
                  'Maximum failed login attempts before lockout',
                  TextInputType.number,
                ),

                const SizedBox(height: 16),

                // Session Timeout
                _buildSettingField(
                  'Session Timeout (minutes)',
                  'session_timeout_minutes',
                  'User session timeout in minutes',
                  TextInputType.number,
                ),

                const SizedBox(height: 16),

                // Backup Frequency
                _buildSettingField(
                  'Backup Frequency (hours)',
                  'backup_frequency_hours',
                  'How often to perform automatic backups',
                  TextInputType.number,
                ),

                const SizedBox(height: 16),

                // Log Retention
                _buildSettingField(
                  'Log Retention (days)',
                  'log_retention_days',
                  'How long to keep system logs',
                  TextInputType.number,
                ),

                const SizedBox(height: 16),

                // Default Currency
                _buildCurrencyDropdownField(
                  'Default Currency',
                  'default_currency',
                  'Default currency for the system',
                ),

                const SizedBox(height: 16),

                // Timezone
                _buildTimezoneDropdownField(
                  'Timezone',
                  'timezone',
                  'System timezone',
                ),

                const SizedBox(height: 24),

                // Error message
                if (settingsProvider.error != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      settingsProvider.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                const SizedBox(height: 16),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveAllSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save System Settings'),
                  ),
                ),

                const SizedBox(height: 16),

                // Warning
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Warning: System settings changes affect all users and stores. Make sure you understand the impact before saving.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/system_settings'),
    );
  }

  Widget _buildSettingField(
    String label,
    String key,
    String hint,
    TextInputType keyboardType,
  ) {
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        hintText: hint,
      ),
      keyboardType: keyboardType,
    );
  }

  Widget _buildBooleanDropdownField(
    String label,
    String key,
    String hint,
  ) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final currentValue =
            settingsProvider.systemSettings?.settings[key] ?? 'false';
        final validValue =
            _booleanOptions.contains(currentValue) ? currentValue : 'false';

        return DropdownButtonFormField<String>(
          initialValue: validValue,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            hintText: hint,
          ),
          items: _booleanOptions.map((option) {
            return DropdownMenuItem<String>(
              value: option,
              child: Text(option == 'true' ? 'Enabled' : 'Disabled'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _controllers[key]?.text = value;
            }
          },
        );
      },
    );
  }

  Widget _buildCurrencyDropdownField(
    String label,
    String key,
    String hint,
  ) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final currentValue =
            settingsProvider.systemSettings?.settings[key] ?? 'ZWL';
        final validValue =
            _currencies.contains(currentValue) ? currentValue : 'ZWL';
        return DropdownButtonFormField<String>(
          initialValue: validValue,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            hintText: hint,
          ),
          items: _currencies.map((currency) {
            return DropdownMenuItem<String>(
              value: currency,
              child: Text(_getCurrencyDisplayName(currency)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _controllers[key]?.text = value;
            }
          },
        );
      },
    );
  }

  Widget _buildTimezoneDropdownField(
    String label,
    String key,
    String hint,
  ) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final currentValue =
            settingsProvider.systemSettings?.settings[key] ?? 'Africa/Harare';
        final validValue =
            _timezones.contains(currentValue) ? currentValue : 'Africa/Harare';
        return DropdownButtonFormField<String>(
          initialValue: validValue,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            hintText: hint,
          ),
          items: _timezones.map((timezone) {
            return DropdownMenuItem<String>(
              value: timezone,
              child: Text(_getTimezoneDisplayName(timezone)),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              _controllers[key]?.text = value;
            }
          },
        );
      },
    );
  }

  String _getCurrencyDisplayName(String currencyCode) {
    const currencyNames = {
      'ZWL': 'ZWL - Zimbabwe Dollar',
      'USD': 'USD - US Dollar',
      'EUR': 'EUR - Euro',
      'GBP': 'GBP - British Pound',
      'ZAR': 'ZAR - South African Rand',
      'BWP': 'BWP - Botswana Pula',
      'MWK': 'MWK - Malawian Kwacha',
      'MZN': 'MZN - Mozambican Metical',
      'SZL': 'SZL - Swazi Lilangeni',
      'LSL': 'LSL - Lesotho Loti',
    };
    return currencyNames[currencyCode] ?? currencyCode;
  }

  String _getTimezoneDisplayName(String timezone) {
    const timezoneNames = {
      'Africa/Harare': 'Harare, Zimbabwe (CAT)',
      'Africa/Johannesburg': 'Johannesburg, South Africa (SAST)',
      'Africa/Lusaka': 'Lusaka, Zambia (CAT)',
      'Africa/Maputo': 'Maputo, Mozambique (CAT)',
      'Africa/Gaborone': 'Gaborone, Botswana (CAT)',
      'Africa/Lilongwe': 'Lilongwe, Malawi (CAT)',
      'UTC': 'UTC (Coordinated Universal Time)',
    };
    return timezoneNames[timezone] ?? timezone;
  }

  void _saveAllSettings() async {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    bool allSuccess = true;

    for (final entry in _controllers.entries) {
      final key = entry.key;
      final value = entry.value.text.trim();
      final success = await settingsProvider.updateSystemSetting(
        key,
        value.isEmpty ? null : value,
      );
      if (!success) {
        allSuccess = false;
        break;
      }
    }

    if (allSuccess && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System settings saved successfully')),
      );
    }
  }
}
