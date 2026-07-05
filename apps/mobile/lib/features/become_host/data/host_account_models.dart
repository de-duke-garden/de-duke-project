/// Data models for the Become a Host feature (FEAT-002), mirroring
/// apps/backend/app/schemas/host_account.py.
library;

enum HostType { owner, agent, company, lawyer, architect, surveyor }

HostType hostTypeFromApiValue(String value) => HostType.values
    .firstWhere((t) => t.name == value, orElse: () => HostType.owner);

extension HostTypeX on HostType {
  String get apiValue => name;

  String get label => switch (this) {
        HostType.owner => 'Owner',
        HostType.agent => 'Agent',
        HostType.company => 'Company',
        HostType.lawyer => 'Lawyer',
        HostType.architect => 'Architect',
        HostType.surveyor => 'Surveyor',
      };

  String get description => switch (this) {
        HostType.owner =>
          'I am the legal owner of the properties and authorized to list them.',
        HostType.agent =>
          'I am a licensed real estate agent listing on behalf of owners.',
        HostType.company =>
          'I represent a CAC-registered company listing properties.',
        HostType.lawyer =>
          'I am a practicing lawyer handling property transactions.',
        HostType.architect =>
          'I am a registered architect involved in property development.',
        HostType.surveyor =>
          'I am a registered surveyor involved in property transactions.',
      };
}

/// One declared document sub-record -- structured multi-file upload
/// contract (architecture.md): `field` is the backend column it fills,
/// `tempKey` is also used as the uploaded file's filename so the backend
/// can match it without index-encoded field names.
class PendingDocument {
  PendingDocument(
      {required this.field, required this.tempKey, required this.localPath});

  final String field;
  final String tempKey;
  final String localPath;

  Map<String, dynamic> toMetaJson() => {'field': field, 'temp_key': tempKey};
}

class HostAccountStatus {
  const HostAccountStatus({
    required this.id,
    required this.hostType,
    required this.status,
    required this.statusReason,
    required this.hostPhotoUrl,
    required this.bio,
  });

  final String id;
  final String hostType;
  // in_review | verified | rejected
  final String status;
  final String? statusReason;
  final String hostPhotoUrl;
  final String bio;

  factory HostAccountStatus.fromJson(Map<String, dynamic> json) =>
      HostAccountStatus(
        id: json['id'] as String,
        hostType: json['host_type'] as String,
        status: json['status'] as String,
        statusReason: json['status_reason'] as String?,
        hostPhotoUrl: json['host_photo_url'] as String,
        bio: json['bio'] as String,
      );
}
