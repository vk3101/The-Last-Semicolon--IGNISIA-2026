import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../theme/aegis_brand.dart';
import '../widgets/aegis_backdrop.dart';

class DoctorWorkspaceScreen extends StatefulWidget {
  const DoctorWorkspaceScreen({
    super.key,
    required this.clinicianName,
    required this.apiService,
  });

  final String clinicianName;
  final ApiService apiService;

  @override
  State<DoctorWorkspaceScreen> createState() => _DoctorWorkspaceScreenState();
}

class _DoctorWorkspaceScreenState extends State<DoctorWorkspaceScreen> {
  final _patientIdController = TextEditingController();
  final _patientNameController = TextEditingController();
  final _patientAgeController = TextEditingController(text: '62');
  final _bedLabelController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _doctorSpecialtyController = TextEditingController(
    text: 'Critical Care',
  );

  final _documentTitleController = TextEditingController();
  final _documentTimestampController = TextEditingController();
  final _documentContentController = TextEditingController();

  bool _loadingCases = true;
  bool _creatingCase = false;
  bool _uploadingDocument = false;
  bool _analyzingCase = false;
  String? _deletingCaseId;
  bool _analyzeAfterUpload = true;
  String _patientSex = 'Female';
  String _documentType = 'prescription';
  String? _error;
  PlatformFile? _selectedDocumentFile;
  String? _uploadingSourceDocumentId;

  List<DoctorPatientCaseSummary> _cases = const [];
  DoctorPatientCase? _selectedCase;

  bool get _doctorBackendAvailable => widget.apiService.doctorBackendAvailable;

  @override
  void initState() {
    super.initState();
    _bedLabelController.text = 'Bed 01';
    _diagnosisController.text = 'Post-operative ICU review';
    _loadCases();
  }

  @override
  void dispose() {
    _patientIdController.dispose();
    _patientNameController.dispose();
    _patientAgeController.dispose();
    _bedLabelController.dispose();
    _diagnosisController.dispose();
    _doctorSpecialtyController.dispose();
    _documentTitleController.dispose();
    _documentTimestampController.dispose();
    _documentContentController.dispose();
    super.dispose();
  }

  Future<void> _loadCases({String? focusPatientId}) async {
    setState(() {
      _loadingCases = true;
      _error = null;
    });

    try {
      final cases = await widget.apiService.fetchDoctorPatientCases();
      DoctorPatientCase? selectedCase = _selectedCase;

      final targetId =
          focusPatientId ??
          selectedCase?.patientId ??
          (cases.isNotEmpty ? cases.first.patientId : null);
      if (targetId != null) {
        selectedCase = await widget.apiService.fetchDoctorPatientCase(targetId);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _cases = cases;
        _selectedCase = selectedCase;
        _loadingCases = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCases = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _selectCase(String patientId) async {
    setState(() {
      _loadingCases = true;
      _error = null;
    });

    try {
      final detail = await widget.apiService.fetchDoctorPatientCase(patientId);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCase = detail;
        _loadingCases = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCases = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _deleteCase(DoctorPatientCaseSummary caseSummary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete patient case?'),
          content: Text(
            'This will permanently remove ${caseSummary.patient.name} from the frontend list and backend storage.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC54452),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    String? nextFocusId;
    for (final item in _cases) {
      if (item.patientId != caseSummary.patientId) {
        nextFocusId = item.patientId;
        break;
      }
    }

    setState(() {
      _deletingCaseId = caseSummary.patientId;
      _error = null;
      if (_selectedCase?.patientId == caseSummary.patientId) {
        _selectedCase = null;
      }
    });

    try {
      await widget.apiService.deleteDoctorPatientCase(caseSummary.patientId);
      if (!mounted) {
        return;
      }
      _showMessage('${caseSummary.patient.name} was removed.');
      await _loadCases(focusPatientId: nextFocusId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      _showMessage(_error ?? 'Unable to delete patient case.');
    } finally {
      if (mounted) {
        setState(() => _deletingCaseId = null);
      }
    }
  }

  Future<void> _createCase() async {
    final patientId = _patientIdController.text.trim();
    final patientName = _patientNameController.text.trim();
    final diagnosis = _diagnosisController.text.trim();
    final bedLabel = _bedLabelController.text.trim();
    final age = int.tryParse(_patientAgeController.text.trim()) ?? 0;

    if (patientId.isEmpty ||
        patientName.isEmpty ||
        diagnosis.isEmpty ||
        age <= 0) {
      _showMessage('Enter patient id, name, diagnosis, and a valid age.');
      return;
    }

    setState(() {
      _creatingCase = true;
      _error = null;
    });

    try {
      final created = await widget.apiService.createDoctorPatientCase(
        clinicianName: widget.clinicianName,
        doctorSpecialty: _doctorSpecialtyController.text.trim().isEmpty
            ? 'Critical Care'
            : _doctorSpecialtyController.text.trim(),
        patientId: patientId,
        patientName: patientName,
        age: age,
        sex: _patientSex,
        bedLabel: bedLabel,
        diagnosis: diagnosis,
      );

      if (!mounted) {
        return;
      }

      _patientIdController.clear();
      _patientNameController.clear();
      _bedLabelController.text = 'Bed 01';
      _diagnosisController.text = 'Post-operative ICU review';

      setState(() {
        _selectedCase = created;
        _creatingCase = false;
      });
      _showMessage('Doctor patient case created.');
      await _loadCases(focusPatientId: created.patientId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creatingCase = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      _showMessage(_error ?? 'Unable to create patient case.');
    }
  }

  Future<void> _uploadDocument() async {
    final selectedCase = _selectedCase;
    if (selectedCase == null) {
      _showMessage('Create or select a patient case first.');
      return;
    }

    final title = _documentTitleController.text.trim();
    final content = _documentContentController.text.trim();
    final selectedFile = _selectedDocumentFile;
    if (title.isEmpty || (content.isEmpty && selectedFile == null)) {
      _showMessage('Enter a document title and add document text or an image.');
      return;
    }

    setState(() {
      _uploadingDocument = true;
      _error = null;
    });

    try {
      final updated = selectedFile != null
          ? await widget.apiService.uploadDoctorDocumentFile(
              selectedCase.patientId,
              fileBytes: selectedFile.bytes!,
              fileName: selectedFile.name,
              mimeType: _mimeTypeForFileName(selectedFile.name),
              documentType: _documentType,
              title: title,
              timestamp: _documentTimestampController.text.trim(),
              author: widget.clinicianName,
              specialty: _doctorSpecialtyController.text.trim(),
              content: content,
              analyzeNow: _analyzeAfterUpload,
            )
          : await widget.apiService
                .uploadDoctorDocuments(selectedCase.patientId, [
                  DoctorDocumentDraft(
                    documentType: _documentType,
                    title: title,
                    content: content,
                    timestamp: _documentTimestampController.text.trim(),
                    author: widget.clinicianName,
                    specialty: _doctorSpecialtyController.text.trim(),
                  ),
                ], analyzeNow: _analyzeAfterUpload);

      if (!mounted) {
        return;
      }

      _documentTitleController.clear();
      _documentTimestampController.clear();
      _documentContentController.clear();
      setState(() {
        _selectedCase = updated;
        _selectedDocumentFile = null;
        _uploadingDocument = false;
      });
      _showMessage('Document uploaded and routed to the correct agents.');
      await _loadCases(focusPatientId: updated.patientId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _uploadingDocument = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      _showMessage(_error ?? 'Unable to upload document.');
    }
  }

  Future<PlatformFile?> _pickImageFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'bmp',
          'gif',
          'heic',
          'heif',
        ],
      );
      final picked = result == null || result.files.isEmpty
          ? null
          : result.files.first;
      if (picked == null) {
        return null;
      }
      if (picked.bytes == null || picked.bytes!.isEmpty) {
        _showMessage('Unable to read the selected image file.');
        return null;
      }
      return picked;
    } catch (error) {
      _showMessage('Unable to pick the image file.');
      return null;
    }
  }

  Future<void> _pickDocumentImage() async {
    final picked = await _pickImageFile();
    if (picked == null) {
      return;
    }

    if (_documentTitleController.text.trim().isEmpty) {
      final normalizedName = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      _documentTitleController.text = normalizedName;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedDocumentFile = picked;
    });
    _showMessage(
      'Image attached. The backend will preprocess it before routing.',
    );
  }

  Future<void> _uploadImageFromDocumentTag(
    DoctorDocumentRecord document,
  ) async {
    final selectedCase = _selectedCase;
    if (selectedCase == null) {
      _showMessage('Select a patient case first.');
      return;
    }
    if (_uploadingDocument || _uploadingSourceDocumentId != null) {
      _showMessage('Please wait for the current upload to finish.');
      return;
    }

    final picked = await _pickImageFile();
    if (picked == null) {
      return;
    }

    final uploadKey = _documentUploadKey(document);
    final normalizedName = picked.name
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .trim();
    final specialty = _doctorSpecialtyController.text.trim().isEmpty
        ? (document.specialty.isEmpty ? 'Critical Care' : document.specialty)
        : _doctorSpecialtyController.text.trim();

    setState(() {
      _uploadingSourceDocumentId = uploadKey;
      _error = null;
    });

    try {
      final updated = await widget.apiService.uploadDoctorDocumentFile(
        selectedCase.patientId,
        fileBytes: picked.bytes!,
        fileName: picked.name,
        mimeType: _mimeTypeForFileName(picked.name),
        documentType: document.documentType,
        title: normalizedName.isEmpty ? document.title : normalizedName,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        author: widget.clinicianName,
        specialty: specialty,
        analyzeNow: _analyzeAfterUpload,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedCase = updated;
        _uploadingSourceDocumentId = null;
      });
      _showMessage('New image uploaded for ${document.title}.');
      await _loadCases(focusPatientId: updated.patientId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _uploadingSourceDocumentId = null;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      _showMessage(_error ?? 'Unable to upload the new image.');
    }
  }

  void _clearSelectedDocumentFile() {
    setState(() {
      _selectedDocumentFile = null;
    });
  }

  Future<void> _analyzeSelectedCase() async {
    final selectedCase = _selectedCase;
    if (selectedCase == null) {
      _showMessage('Select a patient case first.');
      return;
    }

    setState(() {
      _analyzingCase = true;
      _error = null;
    });

    try {
      final updated = await widget.apiService.analyzeDoctorPatientCase(
        selectedCase.patientId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedCase = updated;
        _analyzingCase = false;
      });
      _showMessage('Chief synthesis report refreshed.');
      await _loadCases(focusPatientId: updated.patientId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _analyzingCase = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      _showMessage(_error ?? 'Unable to analyze case.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final selectedCase = _selectedCase;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AEGIS AI Intake Studio'),
        actions: [
          IconButton(
            tooltip: 'Refresh cases',
            onPressed: _loadingCases ? null : () => _loadCases(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: AegisBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1120;
              final caseRail = _DoctorCaseRail(
                loading: _loadingCases,
                cases: _cases,
                selectedCaseId: selectedCase?.patientId,
                onSelect: _selectCase,
                deletingCaseId: _deletingCaseId,
                onDelete: _deleteCase,
              );
              final workspace = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null) ...[
                    _BannerMessage(message: _error!, color: AegisBrand.danger),
                    const SizedBox(height: 14),
                  ],
                  _DoctorWorkspaceHero(
                    clinicianName: widget.clinicianName,
                    selectedCase: selectedCase,
                  ),
                  const SizedBox(height: 16),
                  _DoctorCaseForm(
                    patientIdController: _patientIdController,
                    patientNameController: _patientNameController,
                    patientAgeController: _patientAgeController,
                    bedLabelController: _bedLabelController,
                    diagnosisController: _diagnosisController,
                    doctorSpecialtyController: _doctorSpecialtyController,
                    patientSex: _patientSex,
                    creatingCase: _creatingCase,
                    onPatientSexChanged: (value) =>
                        setState(() => _patientSex = value),
                    onCreate: _createCase,
                  ),
                  const SizedBox(height: 16),
                  _DocumentComposerPanel(
                    selectedCase: selectedCase,
                    backendAvailable: _doctorBackendAvailable,
                    documentTitleController: _documentTitleController,
                    documentTimestampController: _documentTimestampController,
                    documentContentController: _documentContentController,
                    selectedDocumentFile: _selectedDocumentFile,
                    documentType: _documentType,
                    analyzeAfterUpload: _analyzeAfterUpload,
                    uploadingDocument: _uploadingDocument,
                    analyzingCase: _analyzingCase,
                    onDocumentTypeChanged: (value) =>
                        setState(() => _documentType = value),
                    onAnalyzeAfterUploadChanged: (value) =>
                        setState(() => _analyzeAfterUpload = value),
                    onPickImage: _pickDocumentImage,
                    onClearImage: _clearSelectedDocumentFile,
                    onUpload: _uploadDocument,
                    onAnalyze: _analyzeSelectedCase,
                  ),
                  if (selectedCase != null) ...[
                    const SizedBox(height: 16),
                    _DoctorReportPanel(selectedCase: selectedCase),
                    const SizedBox(height: 16),
                    _PatientSnapshotPanel(selectedCase: selectedCase),
                    const SizedBox(height: 16),
                    _DoctorDocumentsPanel(
                      selectedCase: selectedCase,
                      uploadingDocumentId: _uploadingSourceDocumentId,
                      onUploadImage: _uploadImageFromDocumentTag,
                    ),
                    const SizedBox(height: 16),
                    _ParsedNotesPanel(selectedCase: selectedCase),
                    const SizedBox(height: 16),
                    _ParsedLabsPanel(selectedCase: selectedCase),
                    const SizedBox(height: 16),
                    _ParsedVitalsPanel(selectedCase: selectedCase),
                  ],
                ],
              );

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 330, child: caseRail),
                          const SizedBox(width: 20),
                          Expanded(child: workspace),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          caseRail,
                          const SizedBox(height: 16),
                          workspace,
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DoctorWorkspaceHero extends StatelessWidget {
  const _DoctorWorkspaceHero({
    required this.clinicianName,
    required this.selectedCase,
  });

  final String clinicianName;
  final DoctorPatientCase? selectedCase;

  @override
  Widget build(BuildContext context) {
    final selectedPatientName =
        selectedCase?.patient.name ?? 'No patient selected';
    final primaryConcern =
        selectedCase?.primaryConcern ??
        'Upload documents to route note, lab, RAG, and chief synthesis work.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AegisBrand.cardInkElevated.withValues(alpha: 0.98),
            AegisBrand.cardInk.withValues(alpha: 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AegisBrand.cardStroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              const _HeroBadge(
                label: AegisBrand.appName,
                color: AegisBrand.secondary,
              ),
              _HeroBadge(label: clinicianName, color: AegisBrand.primary),
              const _HeroBadge(
                label: 'Physician Case Studio',
                color: AegisBrand.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Professional intake, routing, and synthesis for bedside cases.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Selected patient: $selectedPatientName',
            style: const TextStyle(
              color: Color(0xFFD3DDF1),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            primaryConcern,
            style: const TextStyle(color: Color(0xFFAFC0DF), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _DoctorCaseRail extends StatelessWidget {
  const _DoctorCaseRail({
    required this.loading,
    required this.cases,
    required this.selectedCaseId,
    required this.onSelect,
    required this.deletingCaseId,
    required this.onDelete,
  });

  final bool loading;
  final List<DoctorPatientCaseSummary> cases;
  final String? selectedCaseId;
  final ValueChanged<String> onSelect;
  final String? deletingCaseId;
  final Future<void> Function(DoctorPatientCaseSummary caseSummary) onDelete;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Case Registry',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Clinician-created cases ready for routing, upload, and chief synthesis.',
            style: TextStyle(color: AegisBrand.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (cases.isEmpty)
            const Text(
              'No clinician-created cases yet. Start a new AEGIS AI case to begin.',
              style: TextStyle(color: Color(0xFFADC0E0)),
            )
          else
            ...cases.map((item) {
              final selected = item.patientId == selectedCaseId;
              final deleting = item.patientId == deletingCaseId;
              final accent = _riskColor(item.overallRiskLevel);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => onSelect(item.patientId),
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF1B2C55)
                          : const Color(0xFF17253D),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF4A7EFF)
                            : accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.patient.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            deleting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Delete patient case',
                                    onPressed: () => onDelete(item),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Color(0xFFFF7D87),
                                    ),
                                    splashRadius: 20,
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                  ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.patientId} • ${item.patient.bedLabel.isEmpty ? 'No bed' : item.patient.bedLabel}',
                          style: const TextStyle(
                            color: Color(0xFF98ACCF),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.patient.diagnosis,
                          style: const TextStyle(
                            color: Color(0xFFD5DEEF),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MiniTag(
                              label: '${item.counts.documents} docs',
                              color: const Color(0xFF2E6BFF),
                            ),
                            _MiniTag(
                              label: item.overallRiskLevel ?? 'UNSCANNED',
                              color: accent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _DoctorCaseForm extends StatelessWidget {
  const _DoctorCaseForm({
    required this.patientIdController,
    required this.patientNameController,
    required this.patientAgeController,
    required this.bedLabelController,
    required this.diagnosisController,
    required this.doctorSpecialtyController,
    required this.patientSex,
    required this.creatingCase,
    required this.onPatientSexChanged,
    required this.onCreate,
  });

  final TextEditingController patientIdController;
  final TextEditingController patientNameController;
  final TextEditingController patientAgeController;
  final TextEditingController bedLabelController;
  final TextEditingController diagnosisController;
  final TextEditingController doctorSpecialtyController;
  final String patientSex;
  final bool creatingCase;
  final ValueChanged<String> onPatientSexChanged;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create Clinician Case',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FieldBox(
                width: 220,
                child: TextField(
                  controller: patientIdController,
                  decoration: _inputDecoration('Patient ID', 'ICU-501'),
                ),
              ),
              _FieldBox(
                width: 280,
                child: TextField(
                  controller: patientNameController,
                  decoration: _inputDecoration('Patient name', 'Anita Rao'),
                ),
              ),
              _FieldBox(
                width: 120,
                child: TextField(
                  controller: patientAgeController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecoration('Age', '67'),
                ),
              ),
              _FieldBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: patientSex,
                  dropdownColor: AegisBrand.panel,
                  decoration: _inputDecoration('Sex', ''),
                  items: const [
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onPatientSexChanged(value);
                    }
                  },
                ),
              ),
              _FieldBox(
                width: 180,
                child: TextField(
                  controller: bedLabelController,
                  decoration: _inputDecoration('Bed label', 'Bed 05'),
                ),
              ),
              _FieldBox(
                width: 220,
                child: TextField(
                  controller: doctorSpecialtyController,
                  decoration: _inputDecoration(
                    'Doctor specialty',
                    'Critical Care',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: diagnosisController,
            decoration: _inputDecoration(
              'Current diagnosis / reason for case',
              'Post-operative sepsis surveillance',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: creatingCase
                ? null
                : () {
                    onCreate();
                  },
            icon: creatingCase
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: Text(
              creatingCase ? 'Creating Case...' : 'Create AEGIS Case',
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentComposerPanel extends StatelessWidget {
  const _DocumentComposerPanel({
    required this.selectedCase,
    required this.backendAvailable,
    required this.documentTitleController,
    required this.documentTimestampController,
    required this.documentContentController,
    required this.selectedDocumentFile,
    required this.documentType,
    required this.analyzeAfterUpload,
    required this.uploadingDocument,
    required this.analyzingCase,
    required this.onDocumentTypeChanged,
    required this.onAnalyzeAfterUploadChanged,
    required this.onPickImage,
    required this.onClearImage,
    required this.onUpload,
    required this.onAnalyze,
  });

  final DoctorPatientCase? selectedCase;
  final bool backendAvailable;
  final TextEditingController documentTitleController;
  final TextEditingController documentTimestampController;
  final TextEditingController documentContentController;
  final PlatformFile? selectedDocumentFile;
  final String documentType;
  final bool analyzeAfterUpload;
  final bool uploadingDocument;
  final bool analyzingCase;
  final ValueChanged<String> onDocumentTypeChanged;
  final ValueChanged<bool> onAnalyzeAfterUploadChanged;
  final Future<void> Function() onPickImage;
  final VoidCallback onClearImage;
  final Future<void> Function() onUpload;
  final Future<void> Function() onAnalyze;

  @override
  Widget build(BuildContext context) {
    final routingSummary = selectedCase?.documentIntake?.routingSummary;
    final selectedCaseRecord = selectedCase;
    final panelEnabled = backendAvailable && selectedCaseRecord != null;
    final lockMessage = selectedCaseRecord == null
        ? 'Create a new patient case or select one from the registry to unlock image upload and analysis.'
        : 'Image upload and automated analysis are temporarily unavailable.';

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload Notes Or Report Images',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedCaseRecord == null
                          ? 'Selected case: No live patient selected yet'
                          : 'Selected case: ${selectedCaseRecord.patient.name} (${selectedCaseRecord.patientId})',
                      style: const TextStyle(
                        color: Color(0xFFAFC0DE),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (routingSummary != null)
                _MiniTag(
                  label:
                      '${routingSummary.noteCount} notes • ${routingSummary.labCount} labs • ${routingSummary.vitalSnapshotCount} vitals',
                  color: const Color(0xFF2E6BFF),
                ),
            ],
          ),
          if (!panelEnabled) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF121F37),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF3A5789)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFFF2C56F),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lockMessage,
                      style: const TextStyle(
                        color: Color(0xFFD6E0F3),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Opacity(
            opacity: panelEnabled ? 1 : 0.58,
            child: AbsorbPointer(
              absorbing: !panelEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _FieldBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: documentType,
                          dropdownColor: AegisBrand.panel,
                          decoration: _inputDecoration('Document type', ''),
                          items: const [
                            DropdownMenuItem(
                              value: 'prescription',
                              child: Text('Prescription'),
                            ),
                            DropdownMenuItem(
                              value: 'clinical_note',
                              child: Text('Clinical Note'),
                            ),
                            DropdownMenuItem(
                              value: 'lab_report',
                              child: Text('Lab Report'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              onDocumentTypeChanged(value);
                            }
                          },
                        ),
                      ),
                      _FieldBox(
                        width: 280,
                        child: TextField(
                          controller: documentTitleController,
                          enabled: panelEnabled,
                          decoration: _inputDecoration(
                            'Document title',
                            'Morning prescription or lab panel',
                          ),
                        ),
                      ),
                      _FieldBox(
                        width: 240,
                        child: TextField(
                          controller: documentTimestampController,
                          enabled: panelEnabled,
                          decoration: _inputDecoration(
                            'Timestamp (optional)',
                            '2026-04-03T08:30:00Z',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploadingDocument ? null : onPickImage,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(
                          selectedDocumentFile == null
                              ? 'Attach Report Image'
                              : 'Replace Image',
                        ),
                      ),
                      if (selectedDocumentFile != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1A2F),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFF22375A)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.image_rounded,
                                size: 18,
                                color: Color(0xFF72A4FF),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: Text(
                                  '${selectedDocumentFile!.name} • ${_prettyFileSize(selectedDocumentFile!.size)}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFD9E3F5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: uploadingDocument ? null : onClearImage,
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Color(0xFF9CB0D1),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    selectedDocumentFile == null
                        ? 'Attach a prescription photo or lab report image, or keep using pasted text.'
                        : 'The backend will normalize this image, attempt OCR extraction, and send the extracted evidence into the diagnostic pipeline.',
                    style: const TextStyle(
                      color: Color(0xFF94A6C8),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: documentContentController,
                    minLines: 7,
                    maxLines: 12,
                    enabled: panelEnabled,
                    decoration: _inputDecoration(
                      selectedDocumentFile == null
                          ? documentType == 'lab_report'
                                ? 'Paste lab report text'
                                : 'Paste prescription / clinical document text'
                          : 'Optional clinician context to combine with the image',
                      selectedDocumentFile == null
                          ? documentType == 'lab_report'
                                ? 'WBC 16.8 K/uL\nLactate 3.8 mmol/L\nCreatinine 1.9 mg/dL'
                                : 'Meropenem started. Patient febrile overnight with abdominal tenderness and BP 92/58.'
                          : 'Add key findings, suspected diagnosis, unreadable lines, or anything OCR should not miss.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: analyzeAfterUpload,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Analyze after upload',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Run RAG and chief synthesis immediately after routing the document.',
                      style: TextStyle(color: Color(0xFF94A6C8)),
                    ),
                    onChanged: onAnalyzeAfterUploadChanged,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: uploadingDocument
                            ? null
                            : () {
                                onUpload();
                              },
                        icon: uploadingDocument
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_rounded),
                        label: Text(
                          uploadingDocument
                              ? 'Uploading...'
                              : 'Upload to Agent Pipeline',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: analyzingCase
                            ? null
                            : () {
                                onAnalyze();
                              },
                        icon: analyzingCase
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.psychology_alt_outlined),
                        label: Text(
                          analyzingCase ? 'Analyzing...' : 'Run Chief Analysis',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorReportPanel extends StatelessWidget {
  const _DoctorReportPanel({required this.selectedCase});

  final DoctorPatientCase selectedCase;

  @override
  Widget build(BuildContext context) {
    final report = selectedCase.latestReport;
    final accent = _riskColor(selectedCase.overallRiskLevel);

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chief Synthesis Report',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedCase.primaryConcern ??
                          'Upload documents and run analysis to populate the report.',
                      style: const TextStyle(
                        color: Color(0xFFD1DBEF),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              _MiniTag(
                label: selectedCase.overallRiskLevel ?? 'PENDING',
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniTag(
                label: '${selectedCase.counts.documents} documents',
                color: const Color(0xFF2E6BFF),
              ),
              _MiniTag(
                label: '${selectedCase.counts.notes} note entries',
                color: const Color(0xFF17C783),
              ),
              _MiniTag(
                label: '${selectedCase.counts.labs} lab entries',
                color: const Color(0xFFF2B84B),
              ),
              _MiniTag(
                label: '${selectedCase.counts.vitals} vital snapshots',
                color: const Color(0xFF9A8CFF),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (report == null)
            const Text(
              'No report is stored yet for this case.',
              style: TextStyle(color: Color(0xFFB1C2E0)),
            )
          else ...[
            _SectionTitle(
              title: 'Chief Summary',
              child: Text(
                report.chiefSummary,
                style: const TextStyle(color: Color(0xFFD7E0F2), height: 1.55),
              ),
            ),
            const SizedBox(height: 14),
            _SectionTitle(
              title: 'Recommended Actions',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: report.recommendedActions.isEmpty
                    ? const [
                        Text(
                          'No recommended actions yet.',
                          style: TextStyle(color: Color(0xFFB1C2E0)),
                        ),
                      ]
                    : report.recommendedActions
                          .map(
                            (action) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: Color(0xFF72A4FF),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      action,
                                      style: const TextStyle(
                                        color: Color(0xFFD6DEF0),
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
              ),
            ),
            const SizedBox(height: 14),
            _SectionTitle(
              title: 'Guideline Evidence',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: report.guidelineCitations.isEmpty
                    ? const [
                        Text(
                          'No citations retrieved yet.',
                          style: TextStyle(color: Color(0xFFB1C2E0)),
                        ),
                      ]
                    : report.guidelineCitations
                          .map(
                            (citation) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF15233A),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF243A61),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${citation.title} (${citation.organization}, ${citation.year})',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      citation.summary,
                                      style: const TextStyle(
                                        color: Color(0xFFCDDAF0),
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
              ),
            ),
            const SizedBox(height: 14),
            _SectionTitle(
              title: 'Uploaded Documents',
              child: Column(
                children: selectedCase.documents.isEmpty
                    ? const [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'No uploaded documents yet.',
                            style: TextStyle(color: Color(0xFFB1C2E0)),
                          ),
                        ),
                      ]
                    : selectedCase.documents
                          .map(
                            (doc) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF101B31),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF22375C),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${doc.documentType} • ${doc.author} • ${_shortTimestamp(doc.timestamp)}',
                                      style: const TextStyle(
                                        color: Color(0xFF90A5CB),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      doc.preview,
                                      style: const TextStyle(
                                        color: Color(0xFFD3DCEF),
                                        height: 1.45,
                                      ),
                                    ),
                                    if (doc
                                        .preprocessingSummary
                                        .isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        doc.preprocessingSummary,
                                        style: const TextStyle(
                                          color: Color(0xFF90A5CB),
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PatientSnapshotPanel extends StatelessWidget {
  const _PatientSnapshotPanel({required this.selectedCase});

  final DoctorPatientCase selectedCase;

  @override
  Widget build(BuildContext context) {
    final counts = selectedCase.counts;
    final doctor = selectedCase.doctor;
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patient Snapshot',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MiniTag(
                label:
                    '${selectedCase.patient.name} • ${selectedCase.patient.sex} • Age ${selectedCase.patient.age}',
                color: const Color(0xFF72A4FF),
              ),
              _MiniTag(
                label: 'Doctor: ${doctor.name} (${doctor.specialty})',
                color: const Color(0xFF17C783),
              ),
              _MiniTag(
                label:
                    'Updated: ${_shortTimestamp(selectedCase.updatedAt.isEmpty ? selectedCase.createdAt : selectedCase.updatedAt)}',
                color: const Color(0xFFF2B84B),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniTag(
                label: '${counts.documents} documents',
                color: const Color(0xFF2E6BFF),
              ),
              _MiniTag(
                label: '${counts.notes} notes',
                color: const Color(0xFF17C783),
              ),
              _MiniTag(
                label: '${counts.labs} labs',
                color: const Color(0xFFF2B84B),
              ),
              _MiniTag(
                label: '${counts.vitals} vitals',
                color: const Color(0xFF9A8CFF),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoctorDocumentsPanel extends StatelessWidget {
  const _DoctorDocumentsPanel({
    required this.selectedCase,
    required this.uploadingDocumentId,
    required this.onUploadImage,
  });

  final DoctorPatientCase selectedCase;
  final String? uploadingDocumentId;
  final Future<void> Function(DoctorDocumentRecord document) onUploadImage;

  @override
  Widget build(BuildContext context) {
    if (selectedCase.documents.isEmpty) {
      return const _SurfacePanel(
        child: Text(
          'No documents uploaded yet.',
          style: TextStyle(color: Color(0xFFB7C6E1)),
        ),
      );
    }

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Uploaded Documents',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...selectedCase.documents.map((doc) {
            final accent = _riskColor(doc.documentType);
            final uploadKey = _documentUploadKey(doc);
            final uploadingThisDocument = uploadingDocumentId == uploadKey;
            final imageUploadActionEnabled =
                doc.sourceKind == 'image_upload' && uploadingDocumentId == null;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1D34),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${doc.documentType} • ${doc.author} • ${_shortTimestamp(doc.timestamp)}',
                    style: const TextStyle(
                      color: Color(0xFF90A5CB),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    doc.preview,
                    style: const TextStyle(
                      color: Color(0xFFD3DCEF),
                      height: 1.45,
                    ),
                  ),
                  if (doc.preprocessingSummary.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      doc.preprocessingSummary,
                      style: const TextStyle(
                        color: Color(0xFF90A5CB),
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _MiniTag(
                        label: uploadingThisDocument
                            ? 'uploading image...'
                            : doc.sourceKind.replaceAll('_', ' '),
                        color: const Color(0xFF72A4FF),
                        onTap: imageUploadActionEnabled
                            ? () => onUploadImage(doc)
                            : null,
                      ),
                      if (doc.ocrStatus != 'not_applicable')
                        _MiniTag(
                          label: 'OCR ${doc.ocrStatus.replaceAll('_', ' ')}',
                          color: doc.ocrStatus.startsWith('extracted')
                              ? const Color(0xFF17C783)
                              : const Color(0xFFF2B84B),
                        ),
                      _MiniTag(
                        label: doc.mimeType,
                        color: const Color(0xFF465B7D),
                      ),
                    ],
                  ),
                  if (doc.externalUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      doc.externalUrl,
                      style: const TextStyle(
                        color: Color(0xFF7EA8FF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (doc.routedAgents.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: doc.routedAgents
                          .map(
                            (agent) => _MiniTag(
                              label: agent,
                              color: const Color(0xFF2E6BFF),
                              onTap: () => _showDoctorAgentSuggestionSheet(
                                context,
                                selectedCase: selectedCase,
                                document: doc,
                                agentKey: agent,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ParsedNotesPanel extends StatelessWidget {
  const _ParsedNotesPanel({required this.selectedCase});

  final DoctorPatientCase selectedCase;

  @override
  Widget build(BuildContext context) {
    if (selectedCase.notes.isEmpty) {
      return const _SurfacePanel(
        child: Text(
          'No parsed notes yet.',
          style: TextStyle(color: Color(0xFFB7C6E1)),
        ),
      );
    }
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note Parser Output',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...selectedCase.notes.map((note) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1D34),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF2E6BFF).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${note.author} (${note.specialty}) • ${_shortTimestamp(note.timestamp)}',
                    style: const TextStyle(
                      color: Color(0xFF90A5CB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    note.text,
                    style: const TextStyle(
                      color: Color(0xFFD3DCEF),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ParsedLabsPanel extends StatelessWidget {
  const _ParsedLabsPanel({required this.selectedCase});

  final DoctorPatientCase selectedCase;

  @override
  Widget build(BuildContext context) {
    if (selectedCase.labs.isEmpty) {
      return const _SurfacePanel(
        child: Text(
          'No parsed labs yet.',
          style: TextStyle(color: Color(0xFFB7C6E1)),
        ),
      );
    }
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lab Mapper Output',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: selectedCase.labs.map((lab) {
              return Container(
                width: 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1D34),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF2B84B).withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lab.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lab.value.toStringAsFixed(2)} ${lab.unit}',
                      style: const TextStyle(
                        color: Color(0xFFE7EEFF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _shortTimestamp(lab.timestamp),
                      style: const TextStyle(
                        color: Color(0xFF95A5C1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ParsedVitalsPanel extends StatelessWidget {
  const _ParsedVitalsPanel({required this.selectedCase});

  final DoctorPatientCase selectedCase;

  @override
  Widget build(BuildContext context) {
    if (selectedCase.vitals.isEmpty) {
      return const _SurfacePanel(
        child: Text(
          'No parsed vitals yet.',
          style: TextStyle(color: Color(0xFFB7C6E1)),
        ),
      );
    }

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vital Snapshots',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...selectedCase.vitals.map((snapshot) {
            final keys = snapshot.values.keys.toList()..sort();
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1D34),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF9A8CFF).withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shortTimestamp(snapshot.timestamp),
                    style: const TextStyle(
                      color: Color(0xFF90A5CB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: keys
                        .map(
                          (key) => _MiniTag(
                            label:
                                '$key ${snapshot.values[key]!.toStringAsFixed(1)}',
                            color: const Color(0xFF9A8CFF),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AegisBrand.cardInkElevated.withValues(alpha: 0.96),
            AegisBrand.cardInk.withValues(alpha: 0.98),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AegisBrand.cardStroke),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AegisBrand.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _BannerMessage extends StatelessWidget {
  const _BannerMessage({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );

    if (onTap == null) {
      return child;
    }

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: child,
        ),
      ),
    );
  }
}

class _DoctorAgentDefinition {
  const _DoctorAgentDefinition({
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final Color accent;
}

void _showDoctorAgentSuggestionSheet(
  BuildContext context, {
  required DoctorPatientCase selectedCase,
  required DoctorDocumentRecord document,
  required String agentKey,
}) {
  final definition = _doctorAgentDefinition(agentKey);
  final report = selectedCase.latestReport;
  final raw = report?.agents[agentKey] ?? const <String, dynamic>{};
  final suggestions = _doctorAgentSuggestionLines(
    agentKey,
    raw,
    report: report,
  );

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.84,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A1427),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 54,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF32486F),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _MiniTag(
                        label: definition.title,
                        color: definition.accent,
                      ),
                      _MiniTag(
                        label: document.title,
                        color: const Color(0xFF72A4FF),
                      ),
                      _MiniTag(
                        label: document.documentType,
                        color: const Color(0xFF465B7D),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Agent Suggestions',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    definition.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFB7C6E1),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1D34),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: definition.accent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Document Context',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          document.preview,
                          style: const TextStyle(
                            color: Color(0xFFD9E3F5),
                            height: 1.45,
                          ),
                        ),
                        if (document.preprocessingSummary.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            document.preprocessingSummary,
                            style: const TextStyle(
                              color: Color(0xFF94A6C8),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: suggestions.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111E36),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFF314A73),
                              ),
                            ),
                            child: const Text(
                              'No suggestion is available for this agent yet. Upload the document with analysis enabled or run Chief Analysis for this case.',
                              style: TextStyle(
                                color: Color(0xFFD6E0F3),
                                height: 1.45,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: suggestions.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final suggestion = suggestions[index];
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111E36),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF314A73),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Icon(
                                        Icons.tips_and_updates_outlined,
                                        size: 18,
                                        color: definition.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        suggestion,
                                        style: const TextStyle(
                                          color: Color(0xFFD9E3F5),
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

_DoctorAgentDefinition _doctorAgentDefinition(String agentKey) {
  switch (agentKey) {
    case 'note_parser_agent':
      return const _DoctorAgentDefinition(
        title: 'Note Parser Agent',
        subtitle:
            'Finds important symptoms, note signals, and bedside narrative clues from uploaded text.',
        accent: Color(0xFF437CFF),
      );
    case 'guideline_rag_agent':
      return const _DoctorAgentDefinition(
        title: 'Guideline RAG Agent',
        subtitle:
            'Matches the current case against relevant ICU and sepsis guidance to suggest evidence-backed next steps.',
        accent: Color(0xFF1FCB84),
      );
    case 'chief_synthesis_agent':
      return const _DoctorAgentDefinition(
        title: 'Chief Synthesis Agent',
        subtitle:
            'Combines note, lab, and risk signals into a concise clinical summary with suggested actions.',
        accent: Color(0xFFFF8C43),
      );
    case 'temporal_lab_mapper_agent':
      return const _DoctorAgentDefinition(
        title: 'Temporal Lab Mapper Agent',
        subtitle:
            'Organizes lab changes over time to surface worsening or improving trends.',
        accent: Color(0xFFB262FF),
      );
    default:
      return const _DoctorAgentDefinition(
        title: 'Agent Suggestion',
        subtitle: 'This agent generated output for the current case.',
        accent: Color(0xFF72A4FF),
      );
  }
}

List<String> _doctorAgentSuggestionLines(
  String agentKey,
  Map<String, dynamic> raw, {
  required DiagnosticReport? report,
}) {
  switch (agentKey) {
    case 'note_parser_agent':
      final matchedSignals =
          (raw['matched_signals'] as List<dynamic>? ?? const [])
              .map(
                (item) => item is Map
                    ? Map<String, dynamic>.from(item)
                    : const <String, dynamic>{},
              )
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
      final evidence = (raw['evidence'] as List<dynamic>? ?? const [])
          .cast<String>();
      return [
        for (final item in matchedSignals.take(4))
          '${item['signal'] ?? 'Signal'}: ${item['summary'] ?? 'Clinical note signal detected.'}',
        ...evidence.take(3),
        if ((raw['summary'] as String?)?.isNotEmpty ?? false)
          raw['summary'].toString(),
      ];
    case 'guideline_rag_agent':
      final citations =
          (raw['retrieved_citations'] as List<dynamic>? ?? const [])
              .map(
                (item) => item is Map
                    ? Map<String, dynamic>.from(item)
                    : const <String, dynamic>{},
              )
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
      return [
        for (final citation in citations.take(2)) ...[
          '${citation['title'] ?? 'Guideline match'}: ${citation['summary'] ?? 'Relevant guidance found.'}',
          ...((citation['support_points'] as List<dynamic>? ?? const [])
              .take(2)
              .map((point) => point.toString())),
        ],
        if ((raw['summary'] as String?)?.isNotEmpty ?? false)
          raw['summary'].toString(),
      ];
    case 'chief_synthesis_agent':
      return [
        if ((raw['primary_concern'] as String?)?.isNotEmpty ?? false)
          'Primary concern: ${raw['primary_concern']}',
        if ((raw['chief_summary'] as String?)?.isNotEmpty ?? false)
          raw['chief_summary'].toString(),
        if ((raw['shift_handoff_summary'] as String?)?.isNotEmpty ?? false)
          raw['shift_handoff_summary'].toString(),
        ...(report?.recommendedActions.take(4) ?? const <String>[]).map(
          (action) => 'Suggested action: $action',
        ),
        if (raw['diagnosis_update_blocked'] == true)
          'Diagnosis update is blocked until probable lab redraw issues are resolved.',
      ];
    case 'temporal_lab_mapper_agent':
      final trends =
          raw['trend_summaries'] as Map<String, dynamic>? ?? const {};
      return [
        for (final entry in trends.entries)
          () {
            final details = entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : const <String, dynamic>{};
            return '${entry.key.toUpperCase()}: ${details['trend'] ?? 'stable'} at ${details['latest_value'] ?? '--'} ${details['unit'] ?? ''}'
                .trim();
          }(),
        if ((raw['summary'] as String?)?.isNotEmpty ?? false)
          raw['summary'].toString(),
      ];
    default:
      return [
        if ((raw['summary'] as String?)?.isNotEmpty ?? false)
          raw['summary'].toString(),
      ];
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

InputDecoration _inputDecoration(String label, String hint) {
  return InputDecoration(
    labelText: label,
    hintText: hint.isEmpty ? null : hint,
    filled: true,
    fillColor: const Color(0xFF0F1A2F),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFF22375A)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFF22375A)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFF4A7EFF)),
    ),
  );
}

Color _riskColor(String? label) {
  switch ((label ?? '').toUpperCase()) {
    case 'CRITICAL':
      return const Color(0xFFFF5A6B);
    case 'HIGH':
    case 'WARNING':
      return const Color(0xFFF2B84B);
    case 'MODERATE':
      return const Color(0xFF72A4FF);
    case 'SAFE':
    case 'LOW':
      return const Color(0xFF17C783);
    default:
      return const Color(0xFF8EA4CA);
  }
}

String _documentUploadKey(DoctorDocumentRecord document) {
  if (document.documentId.isNotEmpty) {
    return document.documentId;
  }
  return '${document.title}-${document.timestamp}-${document.documentType}';
}

String _mimeTypeForFileName(String fileName) {
  final normalized = fileName.toLowerCase();
  if (normalized.endsWith('.png')) {
    return 'image/png';
  }
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (normalized.endsWith('.webp')) {
    return 'image/webp';
  }
  if (normalized.endsWith('.bmp')) {
    return 'image/bmp';
  }
  if (normalized.endsWith('.gif')) {
    return 'image/gif';
  }
  if (normalized.endsWith('.heic')) {
    return 'image/heic';
  }
  if (normalized.endsWith('.heif')) {
    return 'image/heif';
  }
  return 'application/octet-stream';
}

String _prettyFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _shortTimestamp(String timestamp) {
  final parsed = DateTime.tryParse(timestamp);
  if (parsed == null) {
    return timestamp.isEmpty ? 'Unknown time' : timestamp;
  }

  final local = parsed.toLocal();
  final month = _monthName(local.month);
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$month ${local.day}, ${hour.toString().padLeft(2, '0')}:$minute $suffix';
}

String _monthName(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (month < 1 || month > 12) {
    return 'Date';
  }
  return months[month - 1];
}
