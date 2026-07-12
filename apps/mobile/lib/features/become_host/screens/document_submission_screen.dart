/// screens.md Screen 3b: Become a Host -- Document Submission.
/// Renders bio + profile photo (all types) plus type-specific text fields
/// and document pickers, matching apps/backend/app/schemas/host_account.py's
/// REQUIRED_DOCUMENT_FIELDS / REQUIRED_TEXT_FIELDS exactly.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/image_source_picker.dart';
import '../data/host_account_models.dart';
import '../data/host_account_repository.dart';

class _DocSpec {
  const _DocSpec(this.field, this.label);
  final String field;
  final String label;
}

/// Mirrors REQUIRED_DOCUMENT_FIELDS in host_account.py, plus the one
/// optional document (Agent's industry license).
const Map<HostType, List<_DocSpec>> _documentSpecs = {
  HostType.owner: [],
  HostType.agent: [
    _DocSpec('cac_cert_doc_url', 'CAC Certificate'),
    _DocSpec('industry_license_url', 'Industry License (optional)'),
    _DocSpec('proof_of_address_url', 'Proof of Address'),
    _DocSpec('rep_id_url', 'Representative ID'),
  ],
  HostType.company: [
    _DocSpec('cac_reg_doc_url', 'CAC Registration Document'),
    _DocSpec('proof_of_address_url', 'Proof of Address'),
    _DocSpec('rep_id_url', 'Director/Representative ID'),
  ],
  HostType.lawyer: [
    _DocSpec('valid_practicing_cert_url', 'Valid Practicing Certificate'),
    _DocSpec('govt_issued_id_url', 'Government-Issued ID'),
    _DocSpec('proof_of_address_url', 'Proof of Address'),
  ],
  HostType.architect: [
    _DocSpec('practice_license_url', 'Practice License'),
    _DocSpec('govt_issued_id_url', 'Government-Issued ID'),
  ],
  HostType.surveyor: [
    _DocSpec('practice_license_url', 'Practice License'),
    _DocSpec('govt_issued_id_url', 'Government-Issued ID'),
  ],
};

/// Fields required (always present, never optional) per host type, so the
/// UI can mark the Agent's industry license as the sole optional document.
const Map<HostType, List<String>> _requiredDocumentFields = {
  HostType.owner: [],
  HostType.agent: ['cac_cert_doc_url', 'proof_of_address_url', 'rep_id_url'],
  HostType.company: ['cac_reg_doc_url', 'proof_of_address_url', 'rep_id_url'],
  HostType.lawyer: [
    'valid_practicing_cert_url',
    'govt_issued_id_url',
    'proof_of_address_url'
  ],
  HostType.architect: ['practice_license_url', 'govt_issued_id_url'],
  HostType.surveyor: ['practice_license_url', 'govt_issued_id_url'],
};

enum _ScreenState { inProgress, submitting, success, error, offline }

class DocumentSubmissionScreen extends StatefulWidget {
  const DocumentSubmissionScreen(
      {super.key, required this.repository, required this.hostType});

  final HostAccountRepository repository;
  final HostType hostType;

  @override
  State<DocumentSubmissionScreen> createState() =>
      _DocumentSubmissionScreenState();
}

class _DocumentSubmissionScreenState extends State<DocumentSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _nbaController = TextEditingController();
  final _arconController = TextEditingController();
  final _surconController = TextEditingController();
  final _refPhoneController = TextEditingController();

  String? _profilePhotoPath;
  final Map<String, String> _documentPaths = {};

  _ScreenState _state = _ScreenState.inProgress;
  String? _errorMessage;

  @override
  void dispose() {
    _bioController.dispose();
    _nbaController.dispose();
    _arconController.dispose();
    _surconController.dispose();
    _refPhoneController.dispose();
    super.dispose();
  }

  List<_DocSpec> get _docSpecs => _documentSpecs[widget.hostType] ?? const [];
  List<String> get _requiredDocs =>
      _requiredDocumentFields[widget.hostType] ?? const [];

  Future<void> _pickProfilePhoto() async {
    final path = await pickImageFromCameraOrGallery(context);
    if (path == null || !mounted) return;
    setState(() => _profilePhotoPath = path);
  }

  Future<void> _pickDocument(String field) async {
    final path = await pickImageFromCameraOrGallery(context);
    if (path == null || !mounted) return;
    setState(() => _documentPaths[field] = path);
  }

  String? _missingFieldError() {
    if (_profilePhotoPath == null) return 'Please add a profile photo.';
    for (final doc in _requiredDocs) {
      if (_documentPaths[doc] == null) {
        final label = _docSpecs.firstWhere((d) => d.field == doc).label;
        return 'Please upload your $label.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final missing = _missingFieldError();
    if (missing != null) {
      setState(() {
        _state = _ScreenState.error;
        _errorMessage = missing;
      });
      return;
    }

    setState(() {
      _state = _ScreenState.submitting;
      _errorMessage = null;
    });

    try {
      final documents = _docSpecs
          .where((spec) => _documentPaths.containsKey(spec.field))
          .map(
            (spec) => PendingDocument(
              field: spec.field,
              tempKey: spec.field,
              localPath: _documentPaths[spec.field]!,
            ),
          )
          .toList();

      await widget.repository.submit(
        hostType: widget.hostType,
        bio: _bioController.text.trim(),
        profilePhotoLocalPath: _profilePhotoPath!,
        documents: documents,
        nbaEnrolNo: widget.hostType == HostType.lawyer
            ? _nbaController.text.trim()
            : null,
        arconRegNo: widget.hostType == HostType.architect
            ? _arconController.text.trim()
            : null,
        surconRegNo: widget.hostType == HostType.surveyor
            ? _surconController.text.trim()
            : null,
        refPhoneNo: {HostType.lawyer, HostType.architect, HostType.surveyor}
                .contains(widget.hostType)
            ? _refPhoneController.text.trim()
            : null,
      );

      if (!mounted) return;
      setState(() => _state = _ScreenState.success);
    } catch (e) {
      final message = e is HostAccountException
          ? e.message
          : 'Could not submit your application.';
      if (!mounted) return;
      setState(() {
        if (message == 'offline') {
          _state = _ScreenState.offline;
          _errorMessage = "You're offline. Try again once connected.";
        } else {
          _state = _ScreenState.error;
          _errorMessage = message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _state == _ScreenState.submitting;

    if (_state == _ScreenState.success) {
      return Scaffold(
        appBar: AppBar(title: Text('Become a Host (${widget.hostType.label})')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 48),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Your application has been submitted for review.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(
                  // screens.md Screen 3b Exit Points: "Host Dashboard
                  // (submission successful, now In Review)" -- button
                  // label already said this, but it routed to Home Feed.
                  onPressed: () => context.go('/host'),
                  child: const Text('Go to Host Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Become a Host (${widget.hostType.label})')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (_state == _ScreenState.offline)
              _Banner(
                  message: _errorMessage ??
                      "You're offline. Try again once connected."),
            if (_state == _ScreenState.error && _errorMessage != null)
              _Banner(message: _errorMessage!),
            TextFormField(
              controller: _bioController,
              decoration: const InputDecoration(labelText: 'Bio'),
              maxLines: 3,
              enabled: !submitting,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter a short bio' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _PhotoPickerTile(
              label: 'Profile photo',
              picked: _profilePhotoPath != null,
              onTap: submitting ? null : _pickProfilePhoto,
            ),
            const SizedBox(height: AppSpacing.md),
            if (widget.hostType == HostType.lawyer)
              _RegistrationField(
                  controller: _nbaController,
                  label: 'NBA Enrollment Number',
                  enabled: !submitting),
            if (widget.hostType == HostType.architect)
              _RegistrationField(
                  controller: _arconController,
                  label: 'ARCON Registration Number',
                  enabled: !submitting),
            if (widget.hostType == HostType.surveyor)
              _RegistrationField(
                  controller: _surconController,
                  label: 'SURCON Registration Number',
                  enabled: !submitting),
            for (final spec in _docSpecs)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PhotoPickerTile(
                  label: spec.label,
                  picked: _documentPaths.containsKey(spec.field),
                  onTap: submitting ? null : () => _pickDocument(spec.field),
                ),
              ),
            if ({HostType.lawyer, HostType.architect, HostType.surveyor}
                .contains(widget.hostType))
              _RegistrationField(
                controller: _refPhoneController,
                label: 'Reference Phone Number',
                enabled: !submitting,
                keyboardType: TextInputType.phone,
              ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: submitting ? null : _submit,
              child: submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit for Verification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPickerTile extends StatelessWidget {
  const _PhotoPickerTile(
      {required this.label, required this.picked, required this.onTap});

  final String label;
  final bool picked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(picked ? Icons.check_circle : Icons.upload_file),
        title: Text(label),
        subtitle: Text(picked ? 'Selected' : 'Tap to select'),
        onTap: onTap,
      ),
    );
  }
}

class _RegistrationField extends StatelessWidget {
  const _RegistrationField({
    required this.controller,
    required this.label,
    required this.enabled,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        enabled: enabled,
        keyboardType: keyboardType,
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'This field is required' : null,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.error, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
