import 'dart:convert';

import '../../core/network/network_client.dart';
import '../e2ee/openmls_client.dart';
import 'dto/api_envelope.dart';

class MlsApi {
  const MlsApi({required NetworkClient networkClient})
      : _networkClient = networkClient;

  final NetworkClient _networkClient;

  Future<void> publishKeyPackages(List<OpenMlsKeyPackage> packages) async {
    final response = await _networkClient.post(
      '/v1/mls/key-packages',
      data: {
        'key_packages': [
          for (final package in packages)
            {
              'ciphersuite': package.ciphersuite,
              'key_package': _rawBase64(package.keyPackage),
              'signature': _rawBase64(package.signature),
              'expires_at': package.expiresAt.toUtc().toIso8601String(),
            },
        ],
      },
    );
    ApiEnvelope<void>.fromJson(
      requireJsonMap(response, 'publish key packages response'),
      (_) {},
    );
  }

  Future<List<MlsClaimedKeyPackage>> claimKeyPackages(
    String accountId, {
    int limit = 1,
  }) async {
    _requireCanonicalIdentifier(accountId, 'accountId');
    if (limit < 1 || limit > 20) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 20');
    }
    final response = await _networkClient.post(
      '/v1/accounts/$accountId/mls/key-packages:claim?limit=$limit',
    );
    return ApiEnvelope<List<MlsClaimedKeyPackage>>.fromJson(
      requireJsonMap(response, 'claim key packages response'),
      (data) => requireJsonList(data, 'key package data')
          .map(_claimedKeyPackageFromJson)
          .toList(growable: false),
    ).data;
  }

  Future<List<OpenMlsWelcome>> claimWelcomes() async {
    final response = await _networkClient.post('/v1/mls/welcomes:claim');
    return ApiEnvelope<List<OpenMlsWelcome>>.fromJson(
      requireJsonMap(response, 'claim welcomes response'),
      (data) => requireJsonList(data, 'welcome data')
          .map(_welcomeFromJson)
          .toList(growable: false),
    ).data;
  }

  Future<OpenMlsGroupState> getGroupState(String conversationId) async {
    final response = await _networkClient.get(
      '/v1/conversations/$conversationId/mls/state',
    );
    return ApiEnvelope<OpenMlsGroupState>.fromJson(
      requireJsonMap(response, 'MLS group state response'),
      _groupStateFromJson,
    ).data;
  }

  Future<OpenMlsProposal> publishProposal(OpenMlsProposal proposal) async {
    final response = await _networkClient.post(
      '/v1/conversations/${proposal.conversationId}/mls/proposals',
      data: {
        'base_epoch': proposal.baseEpoch,
        'proposal': _rawBase64(proposal.data),
      },
    );
    return ApiEnvelope<OpenMlsProposal>.fromJson(
      requireJsonMap(response, 'publish proposal response'),
      _proposalFromJson,
    ).data;
  }

  Future<List<OpenMlsProposal>> listProposals(String conversationId) async {
    final response = await _networkClient.get(
      '/v1/conversations/$conversationId/mls/proposals',
    );
    return ApiEnvelope<List<OpenMlsProposal>>.fromJson(
      requireJsonMap(response, 'MLS proposals response'),
      (data) => requireJsonList(data, 'proposal data')
          .map(_proposalFromJson)
          .toList(growable: false),
    ).data;
  }

  Future<OpenMlsGroupState> commit(OpenMlsCommit commit) async {
    final welcomes = [
      for (final welcome in commit.welcomes)
        if (welcome.target == null)
          throw ArgumentError.value(
            welcome,
            'commit.welcomes',
            'Each welcome needs a target account and device.',
          )
        else
          {
            'target_account_id': welcome.target!.accountId,
            'target_device_id': welcome.target!.deviceId,
            'welcome': _rawBase64(welcome.data),
          },
    ];
    final response = await _networkClient.put(
      '/v1/conversations/${commit.conversationId}/mls/state',
      data: {
        'epoch': commit.epoch,
        'group_info': commit.groupInfo == null
            ? null
            : _nonEmptyRawBase64(commit.groupInfo!, 'group_info'),
        'commit': _rawBase64(commit.commit),
        'welcomes': welcomes,
        'removed_device_ids': commit.removedDeviceIds,
        'proposal_ids': commit.proposalIds,
      },
    );
    return ApiEnvelope<OpenMlsGroupState>.fromJson(
      requireJsonMap(response, 'commit MLS state response'),
      _groupStateFromJson,
    ).data;
  }

  static MlsClaimedKeyPackage _claimedKeyPackageFromJson(Object? value) {
    final json = requireJsonMap(value, 'claimed key package');
    return MlsClaimedKeyPackage(
      id: _requiredString(json['id'], 'id'),
      deviceId: _requiredString(json['device_id'], 'device_id'),
      ciphersuite: _requiredString(json['ciphersuite'], 'ciphersuite'),
      keyPackage: _rawBase64Decode(json['key_package'], 'key_package'),
      signature: _rawBase64Decode(json['signature'], 'signature'),
      expiresAt: _requiredDateTime(json['expires_at'], 'expires_at'),
    );
  }

  static OpenMlsWelcome _welcomeFromJson(Object? value) {
    final json = requireJsonMap(value, 'welcome');
    return OpenMlsWelcome(
      conversationId:
          _requiredString(json['conversation_id'], 'conversation_id'),
      epoch: _requiredInt(json['epoch'], 'epoch'),
      data: _rawBase64Decode(json['welcome'], 'welcome'),
    );
  }

  static OpenMlsGroupState _groupStateFromJson(Object? value) {
    final json = requireJsonMap(value, 'group state');
    return OpenMlsGroupState(
      conversationId:
          _requiredString(json['conversation_id'], 'conversation_id'),
      epoch: _requiredInt(json['epoch'], 'epoch'),
      groupInfo: _optionalRawBase64Decode(json['group_info'], 'group_info'),
      commit: _rawBase64Decode(json['commit'], 'commit'),
    );
  }

  static OpenMlsProposal _proposalFromJson(Object? value) {
    final json = requireJsonMap(value, 'proposal');
    return OpenMlsProposal(
      id: _requiredString(json['id'], 'id'),
      conversationId:
          _requiredString(json['conversation_id'], 'conversation_id'),
      baseEpoch: _requiredInt(json['base_epoch'], 'base_epoch'),
      data: _rawBase64Decode(json['proposal'], 'proposal'),
    );
  }

  static String _rawBase64(List<int> value) =>
      base64Encode(value).replaceAll('=', '');

  static String _nonEmptyRawBase64(List<int> value, String field) {
    if (value.isEmpty) {
      throw ArgumentError.value(
          value, field, '$field must be non-empty or null');
    }
    return _rawBase64(value);
  }

  static List<int>? _optionalRawBase64Decode(Object? value, String field) {
    if (value == null) return null;
    return _rawBase64Decode(value, field);
  }

  static List<int> _rawBase64Decode(Object? value, String field) {
    final encoded = _requiredString(value, field);
    if (encoded.contains('=')) {
      throw FormatException('$field must be unpadded base64');
    }
    try {
      return base64Decode(base64.normalize(encoded));
    } on FormatException {
      throw FormatException('$field must be base64');
    }
  }

  static String _requiredString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field must be a non-empty string');
    }
    return value;
  }

  static int _requiredInt(Object? value, String field) {
    if (value is! int || value < 0) {
      throw FormatException('$field must be a non-negative integer');
    }
    return value;
  }

  static DateTime _requiredDateTime(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field must be an ISO-8601 datetime');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$field must be an ISO-8601 datetime');
    }
    return parsed.toUtc();
  }

  static void _requireCanonicalIdentifier(String value, String field) {
    if (value.isEmpty || value.trim() != value) {
      throw ArgumentError.value(
        value,
        field,
        'must be non-empty and have no surrounding whitespace',
      );
    }
  }
}

class MlsClaimedKeyPackage {
  MlsClaimedKeyPackage({
    required this.id,
    required this.deviceId,
    required this.ciphersuite,
    required List<int> keyPackage,
    required List<int> signature,
    required this.expiresAt,
  })  : keyPackage = List.unmodifiable(keyPackage),
        signature = List.unmodifiable(signature);

  final String id;
  final String deviceId;
  final String ciphersuite;
  final List<int> keyPackage;
  final List<int> signature;
  final DateTime expiresAt;
}
