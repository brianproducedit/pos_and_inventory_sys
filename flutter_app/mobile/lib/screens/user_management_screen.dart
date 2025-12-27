import 'package:flutter/material.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/user_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/widgets/management_list_item.dart';
import 'package:mobile/widgets/primary_text_field.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/widgets/primary_dialog.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  void _showInviteDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Invite User'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: nameCtrl,
                label: 'Name',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              PrimaryTextField(
                controller: emailCtrl,
                label: 'Email',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!value.contains('@')) return 'Please enter a valid email';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          PrimaryButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final provider = context.read<UserProvider>();
                final id = DateTime.now().millisecondsSinceEpoch;
                await provider.createUser({
                  'id': id,
                  'name': nameCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'is_active': true
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User invited')));
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, Map<String, dynamic> user) {
    final nameCtrl = TextEditingController(text: user['name'] ?? '');
    final emailCtrl = TextEditingController(text: user['email'] ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Edit User'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PrimaryTextField(
                controller: nameCtrl,
                label: 'Name',
                autofocus: true,
                semanticLabel: 'Edit user name',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              PrimaryTextField(
                controller: emailCtrl,
                label: 'Email',
                semanticLabel: 'Edit user email',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an email';
                  }
                  if (!value.contains('@')) return 'Please enter a valid email';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          PrimaryButton(
            onPressed: () async {
              // Validate; do not attempt to manipulate focus nodes here (avoids lifecycle issues in tests)
              final valid = formKey.currentState!.validate();
              if (!valid) return;

              final provider = context.read<UserProvider>();
              await provider.updateUser(user['id'] as int, {
                'name': nameCtrl.text.trim(),
                'email': emailCtrl.text.trim()
              });
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User updated')));
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const PrimaryDialogTitle(title: 'Delete User'),
        content: Text('Are you sure you want to delete ${user['name']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await context.read<UserProvider>().deleteUser(user['id'] as int);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('User deleted')));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.role != 'superadmin' && auth.role != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('User Management')),
        body: const Center(child: Text('Access denied')),
      );
    }

    final users = Provider.of<UserProvider>(context).users;

    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: users.isEmpty
          ? const Center(child: Text('No users yet'))
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final u = users[index];
                return ManagementListItem(
                  title: u['name'] ?? 'Unnamed',
                  subtitle: u['email'],
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showEditUserDialog(context, u),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _confirmDelete(context, u),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInviteDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Invite'),
        backgroundColor: AppColors.primaryBrand,
      ),
    );
  }
}
