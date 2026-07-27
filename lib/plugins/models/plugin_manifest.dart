import '../permissions/plugin_permission.dart';

class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.entry,
    required this.permissions,
    required this.checksum,
  });

  final String id;
  final String name;
  final String version;
  final String entry;
  final Set<PluginPermission> permissions;
  final String checksum;
}
