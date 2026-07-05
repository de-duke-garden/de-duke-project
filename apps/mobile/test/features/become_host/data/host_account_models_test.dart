import 'package:flutter_test/flutter_test.dart';

import 'package:de_duke_mobile/features/become_host/data/host_account_models.dart';

void main() {
  group('HostType', () {
    test('apiValue matches backend enum values exactly', () {
      expect(HostType.owner.apiValue, 'owner');
      expect(HostType.agent.apiValue, 'agent');
      expect(HostType.company.apiValue, 'company');
      expect(HostType.lawyer.apiValue, 'lawyer');
      expect(HostType.architect.apiValue, 'architect');
      expect(HostType.surveyor.apiValue, 'surveyor');
    });

    test('every type has a non-empty label and description', () {
      for (final type in HostType.values) {
        expect(type.label, isNotEmpty);
        expect(type.description, isNotEmpty);
      }
    });

    test('hostTypeFromApiValue parses every valid value round-trip', () {
      for (final type in HostType.values) {
        expect(hostTypeFromApiValue(type.apiValue), type);
      }
    });

    test('hostTypeFromApiValue falls back to owner for an unknown value', () {
      expect(hostTypeFromApiValue('not_a_real_type'), HostType.owner);
    });
  });

  group('HostAccountStatus.fromJson', () {
    test('parses a full in_review submission', () {
      final status = HostAccountStatus.fromJson({
        'id': 'ha-1',
        'host_type': 'lawyer',
        'status': 'in_review',
        'status_reason': null,
        'host_photo_url': 'https://example.com/photo.jpg',
        'bio': 'Practicing lawyer',
      });

      expect(status.id, 'ha-1');
      expect(status.hostType, 'lawyer');
      expect(status.status, 'in_review');
      expect(status.statusReason, isNull);
      expect(status.hostPhotoUrl, 'https://example.com/photo.jpg');
      expect(status.bio, 'Practicing lawyer');
    });

    test('parses a rejected submission with a reason', () {
      final status = HostAccountStatus.fromJson({
        'id': 'ha-2',
        'host_type': 'agent',
        'status': 'rejected',
        'status_reason': 'CAC certificate image unclear',
        'host_photo_url': 'https://example.com/photo.jpg',
        'bio': 'Agent bio',
      });

      expect(status.status, 'rejected');
      expect(status.statusReason, 'CAC certificate image unclear');
    });
  });

  group('PendingDocument', () {
    test('toMetaJson emits only field and temp_key', () {
      final doc = PendingDocument(
        field: 'cac_cert_doc_url',
        tempKey: 'cac_cert_doc_url',
        localPath: 'picked://cac_cert_doc_url_0',
      );
      expect(doc.toMetaJson(),
          {'field': 'cac_cert_doc_url', 'temp_key': 'cac_cert_doc_url'});
    });
  });
}
