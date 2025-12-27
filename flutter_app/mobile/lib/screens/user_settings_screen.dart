import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'package:mobile/widgets/primary_button.dart';

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _themeController;
  late TextEditingController _languageController;
  late bool _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    _themeController = TextEditingController(
        text: settingsProvider.userSettings?.theme ?? 'light');
    _languageController = TextEditingController(
        text: settingsProvider.userSettings?.language ?? 'en');
    _notificationsEnabled =
        settingsProvider.userSettings?.notificationsEnabled ?? true;

    // Load settings if not already loaded (defer until after build)
    if (settingsProvider.userSettings == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settingsProvider.loadUserSettings();
      });
    }
  }

  @override
  void dispose() {
    _themeController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Settings'),
        backgroundColor: AppColors.primaryBrand,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          if (settingsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Update controllers when settings load
          if (settingsProvider.userSettings != null) {
            _themeController.text = settingsProvider.userSettings!.theme;
            _languageController.text = settingsProvider.userSettings!.language;
            _notificationsEnabled =
                settingsProvider.userSettings!.notificationsEnabled;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personal Preferences',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Theme Selection (compact, constrained width)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.9,
                      child: DropdownButtonFormField<String>(
                        initialValue: _themeController.text,
                        decoration: const InputDecoration(
                          labelText: 'Theme',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                        ),
                        isDense: true,
                        itemHeight: 48,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 14, color: AppColors.textBody),
                        iconSize: 20,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: const [
                          DropdownMenuItem(
                              value: 'light',
                              child: Text('Light',
                                  style: TextStyle(color: AppColors.textBody))),
                          DropdownMenuItem(
                              value: 'dark',
                              child: Text('Dark',
                                  style: TextStyle(color: AppColors.textBody))),
                          DropdownMenuItem(
                              value: 'system',
                              child: Text('System Default',
                                  style: TextStyle(color: AppColors.textBody))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _themeController.text = value ?? 'light';
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Language Selection (compact, constrained width)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.9,
                      child: DropdownButtonFormField<String>(
                        initialValue: _languageController.text,
                        decoration: const InputDecoration(
                          labelText: 'Language',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                        ),
                        isDense: true,
                        itemHeight: 48,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 14, color: AppColors.textBody),
                        iconSize: 20,
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        items: const [
                          DropdownMenuItem(
                              value: 'en',
                              child: Text('English',
                                  style: TextStyle(color: AppColors.textBody))),
                          DropdownMenuItem(
                              value: 'es',
                              child: Text('Español',
                                  style: TextStyle(color: AppColors.textBody))),
                          DropdownMenuItem(
                              value: 'fr',
                              child: Text('Français',
                                  style: TextStyle(color: AppColors.textBody))),
                          DropdownMenuItem(
                              value: 'de',
                              child: Text('Deutsch',
                                  style: TextStyle(color: AppColors.textBody))),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _languageController.text = value ?? 'en';
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Notifications Toggle
                  SwitchListTile(
                    title: const Text('Enable Notifications'),
                    subtitle: const Text(
                        'Receive notifications for important updates'),
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                      });
                    },
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
                    child: PrimaryButton(
                      onPressed: _saveSettings,
                      child: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final newSettings = settingsProvider.userSettings?.copyWith(
          theme: _themeController.text,
          language: _languageController.text,
          notificationsEnabled: _notificationsEnabled,
        ) ??
        UserSettings(
          theme: _themeController.text,
          language: _languageController.text,
          notificationsEnabled: _notificationsEnabled,
        );

    final success = await settingsProvider.updateUserSettings(newSettings);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }
}
