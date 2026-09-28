// ============================================================
// tour_config_screen.dart
// ============================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tour.dart';
import '../repositories/tour_repository.dart';
import '../services/auth_service.dart';
import '../services/places_service.dart';
import '../services/calendar_sync_service.dart';
import 'tour_success_screen.dart';

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);
const _kFieldFill = Color(0xFFF3F3F3);
const _kBorderGrey = Color(0xFFE0E0E0);

class TourConfigScreen extends StatefulWidget {
  const TourConfigScreen({super.key, this.existingTour});

  final Tour? existingTour;
  bool get isEditing => existingTour != null;

  @override
  State<TourConfigScreen> createState() => _TourConfigScreenState();
}

class _TourConfigScreenState extends State<TourConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tourRepository = TourRepository();
  final _authService = AuthService();
  final _placesService = PlacesService();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _locationController;
  late final TextEditingController _headcountController;

  DateTime? _scheduledAt;
  File? _photoFile;
  String? _existingPhotoUrl;

  List<PlaceSuggestion> _locationSuggestions = [];
  PlaceLocation? _selectedLocation;
  Timer? _searchDebounce;
  bool _searchingLocation = false;
  String? _locationError;

  double? _currentLat;
  double? _currentLng;

  late RangeValues _radiusZones;
  static const double _maxRadius = 200;

  bool _saveAsPreset = false;
  bool _isSaving = false;
  String? _errorMessage;
  bool _isDraggingPreset = false;

  @override
  void initState() {
    super.initState();
    final tour = widget.existingTour;

    _nameController = TextEditingController(text: tour?.name ?? '');
    _descriptionController = TextEditingController(text: tour?.description ?? '');
    _locationController = TextEditingController(
      text: tour?.startLocationName ?? '',
    );
    _headcountController = TextEditingController(
      text: tour?.expectedHeadcount?.toString() ?? '',
    );

    _scheduledAt = tour?.scheduledAt;
    _existingPhotoUrl = tour?.photoUrl;
    _saveAsPreset = tour?.isPreset ?? false;

    if (tour?.hasStartLocation ?? false) {
      _selectedLocation = PlaceLocation(
        name: tour!.startLocationName!,
        latitude: tour.startLocationLat!,
        longitude: tour.startLocationLng!,
      );
    }

    _radiusZones = RangeValues(
      tour?.greenRadiusMeters ?? 20,
      tour?.amberRadiusMeters ?? 60,
    );

    _fetchDeviceLocation();
  }

  Future<void> _fetchDeviceLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _headcountController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onLocationTextChanged(String value) {
    final coordRegExp = RegExp(r'^\s*(-?\d+(\.\d+)?),\s*(-?\d+(\.\d+)?)\s*$');
    final match = coordRegExp.firstMatch(value);
    if (match != null) {
      final lat = double.parse(match.group(1)!);
      final lng = double.parse(match.group(3)!);
      setState(() {
        _selectedLocation = PlaceLocation(
          name: 'Meeting Point (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
          latitude: lat,
          longitude: lng,
        );
        _locationSuggestions = [];
        _locationError = null;
      });
      return;
    }

    if (_selectedLocation != null && value != _selectedLocation!.name) {
      setState(() => _selectedLocation = null);
    }

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runLocationSearch(value);
    });
  }

  Future<void> _runLocationSearch(String value) async {
    if (value.trim().length < 3) {
      setState(() => _locationSuggestions = []);
      return;
    }

    setState(() {
      _searchingLocation = true;
      _locationError = null;
    });

    try {
      final suggestions = await _placesService.autocomplete(
        value,
        guideLatitude: _currentLat,
        guideLongitude: _currentLng,
      );
      if (!mounted) return;
      setState(() => _locationSuggestions = suggestions);
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationError = 'Location search failed: $error');
    } finally {
      if (mounted) setState(() => _searchingLocation = false);
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() {
      _searchingLocation = true;
      _locationSuggestions = [];
    });

    try {
      final location = await _placesService.getLocation(suggestion);
      if (!mounted) return;
      setState(() {
        _selectedLocation = location;
        _locationController.text = location.name;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _locationError = 'Could not use that location: $error');
    } finally {
      if (mounted) setState(() => _searchingLocation = false);
    }
  }

  Future<void> _openFineTuneMap() async {
    final initialLat = _selectedLocation?.latitude ?? _currentLat ?? -36.8485;
    final initialLng = _selectedLocation?.longitude ?? _currentLng ?? 174.7633;

    final result = await Navigator.of(context).push<PlaceLocation>(
      MaterialPageRoute(
        builder: (context) => _FineTuneMapScreen(
          initialPosition: LatLng(initialLat, initialLng),
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedLocation = result;
        _locationController.text = result.name;
      });
    }
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kBrandBlue,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _scheduledAt != null
          ? TimeOfDay.fromDateTime(_scheduledAt!)
          : TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _kBrandBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;

    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (_errorMessage == 'Please pick a date and time for this tour.') {
        _errorMessage = null;
      }
    });
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add Tour Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: _kBrandBlue),
                title: const Text('Take a picture'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: _kBrandBlue),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;
    final pickedFile = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    setState(() => _photoFile = File(pickedFile.path));
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tour'),
        content: const Text('Are you sure you want to delete this tour? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted && widget.existingTour != null) {
      setState(() => _isSaving = true);
      try {
        await CalendarSyncService().deleteTourFromDevice(widget.existingTour!);
        await _tourRepository.deleteTour(widget.existingTour!.id);
        
        if (!mounted) return;
        Navigator.of(context).pop();
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage = 'Could not delete tour: $error';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a tour name.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_scheduledAt == null) {
      setState(() => _errorMessage = 'Please pick a date and time for this tour.');
      return;
    }

    final guideUid = _authService.currentUser?.uid;
    if (guideUid == null) {
      setState(() => _errorMessage = 'You must be signed in to save a tour.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
      final headcountText = _headcountController.text.trim();
      final headcount = headcountText.isEmpty ? null : int.tryParse(headcountText);

      String? tourId;
      String? photoUrlToSave = _existingPhotoUrl;

      if (_photoFile != null) {
        tourId = widget.isEditing ? widget.existingTour!.id : null;
        tourId ??= DateTime.now().millisecondsSinceEpoch.toString();

        final storageRef = FirebaseStorage.instance.ref().child(
          'tour_photos/$tourId.jpg',
        );
        await storageRef.putFile(_photoFile!);
        photoUrlToSave = await storageRef.getDownloadURL();
      }

      if (widget.isEditing) {
        tourId = widget.existingTour!.id;
        await _tourRepository.updateTour(
          tourId,
          name: name,
          description: description,
          scheduledAt: _scheduledAt,
          startLocationName: _selectedLocation?.name,
          startLocationLat: _selectedLocation?.latitude,
          startLocationLng: _selectedLocation?.longitude,
          expectedHeadcount: headcount,
          greenRadiusMeters: _radiusZones.start,
          amberRadiusMeters: _radiusZones.end,
          photoUrl: photoUrlToSave,
        );
      } else {
        // 1. Create the live scheduled tour and keep its ID in `tourId`
        tourId = await _tourRepository.createTour(
          name: name,
          description: description,
          guideUid: guideUid,
          scheduledAt: _scheduledAt,
          startLocationName: _selectedLocation?.name,
          startLocationLat: _selectedLocation?.latitude,
          startLocationLng: _selectedLocation?.longitude,
          expectedHeadcount: headcount,
          greenRadiusMeters: _radiusZones.start,
          amberRadiusMeters: _radiusZones.end,
          isPreset: false,
          photoUrl: photoUrlToSave,
        );

        // 2. If checked, quietly save a preset template copy in the background
        if (_saveAsPreset) {
          await _tourRepository.createTour(
            name: name,
            description: description,
            guideUid: guideUid,
            scheduledAt: null,
            startLocationName: _selectedLocation?.name,
            startLocationLat: _selectedLocation?.latitude,
            startLocationLng: _selectedLocation?.longitude,
            expectedHeadcount: headcount,
            greenRadiusMeters: _radiusZones.start,
            amberRadiusMeters: _radiusZones.end,
            isPreset: true,
            photoUrl: photoUrlToSave,
          );
        }
      }

      // Check if auto-sync calendar is enabled and sync event using `tourId`
      final prefs = await SharedPreferences.getInstance();
      final autoSyncEnabled = prefs.getBool('guide_auto_sync_calendar') ?? false;

      if (autoSyncEnabled && _scheduledAt != null) {
        final savedTour = await _tourRepository.getTour(tourId);
        if (savedTour != null) {
          final eventId = await CalendarSyncService().syncTour(savedTour);
          if (eventId != null) {
            await _tourRepository.updateTour(tourId, calendarEventId: eventId);
          }
        }
      }

      if (!mounted) return;

      if (widget.isEditing) {
        Navigator.of(context).pop(tourId);
      } else {
        final createdTour = await _tourRepository.getTour(tourId);
        if (!mounted) return;

        if (createdTour != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => TourSuccessScreen(tour: createdTour),
            ),
          );
        } else {
          Navigator.of(context).pop(tourId);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not save this tour: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0.0,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          widget.isEditing ? 'Edit Tour' : 'Create Tour',
          style: const TextStyle(
            color: _kBrandBlue,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (widget.isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete Tour',
              onPressed: _isSaving ? null : _confirmAndDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  if (!widget.isEditing)
                    _PresetPicker(
                      onSelected: _applyPreset,
                      onDragStarted: () => setState(() => _isDraggingPreset = true),
                      onDragEnded: () => setState(() => _isDraggingPreset = false),
                    ),
                  if (!widget.isEditing) const SizedBox(height: 20),

                  const _FieldLabel('Tour Name *'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: _fieldDecoration(hintText: 'e.g. Auckland Museum'),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Please enter a tour name'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  const _FieldLabel('Tour Description (optional)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: _fieldDecoration(hintText: 'Add notes or instructions for tourists...'),
                  ),
                  const SizedBox(height: 20),

                  const _FieldLabel('Date & Time *'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDateTime,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: _fieldDecoration(
                        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
                      ),
                      child: Text(
                        _scheduledAt == null
                            ? 'Tap to pick a date and time'
                            : _formatDateTime(_scheduledAt!),
                        style: TextStyle(
                          color: _scheduledAt == null ? Colors.grey[600] : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const _FieldLabel('Starting Location (optional)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _locationController,
                    onChanged: _onLocationTextChanged,
                    decoration: _fieldDecoration(
                      hintText: 'Search place or type coordinates (lat,lng)',
                      suffixIcon: _searchingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : (_selectedLocation != null
                                ? const Icon(Icons.check_circle, color: _kBrandBlue)
                                : null),
                    ),
                  ),
                  if (_locationSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorderGrey),
                      ),
                      child: Column(
                        children: _locationSuggestions
                            .map(
                              (s) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined, size: 20),
                                title: Text(s.description, style: const TextStyle(fontSize: 14)),
                                onTap: () => _selectSuggestion(s),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (_locationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _locationError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),

                  if (_selectedLocation != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      height: 150,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kBorderGrey),
                      ),
                      child: Stack(
                        children: [
                          GoogleMap(
                            key: ValueKey('${_selectedLocation!.latitude}_${_selectedLocation!.longitude}'),
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
                              zoom: 15,
                            ),
                            markers: {
                              Marker(
                                markerId: const MarkerId('start_location'),
                                position: LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
                              ),
                            },
                            zoomControlsEnabled: false,
                            scrollGesturesEnabled: false,
                            rotateGesturesEnabled: false,
                            tiltGesturesEnabled: false,
                            myLocationButtonEnabled: false,
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: ElevatedButton.icon(
                              onPressed: _openFineTuneMap,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kBrandYellow,
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.edit_location, size: 16),
                              label: const Text('Fine-Tune', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 4),
                  Text(
                    'Tourists who join before the tour starts will see a '
                    '"Get Directions" button that opens this location in their '
                    'own maps app.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 20),

                  const _FieldLabel('Expected Headcount (optional)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _headcountController,
                    keyboardType: TextInputType.number,
                    decoration: _fieldDecoration(hintText: 'e.g. 10'),
                  ),
                  const SizedBox(height: 20),

                  const _FieldLabel('Tour Photo (optional)'),
                  const SizedBox(height: 8),
                  _PhotoPicker(
                    photoFile: _photoFile,
                    existingPhotoUrl: _existingPhotoUrl,
                    onTap: _pickPhoto,
                  ),
                  const SizedBox(height: 24),

                  const _FieldLabel('Tracking Radius'),
                  const SizedBox(height: 4),
                  Text(
                    'How far tourists can wander from you before they show as '
                    'amber, then red, on the live map.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _RadiusScenarioChip(
                          icon: Icons.location_city,
                          label: 'City / Walking',
                          subtitle: '15m / 40m',
                          isSelected: _radiusZones.start == 15 && _radiusZones.end == 40,
                          onTap: () => setState(() => _radiusZones = const RangeValues(15, 40)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RadiusScenarioChip(
                          icon: Icons.groups,
                          label: 'Large Group',
                          subtitle: '30m / 80m',
                          isSelected: _radiusZones.start == 30 && _radiusZones.end == 80,
                          onTap: () => setState(() => _radiusZones = const RangeValues(30, 80)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RadiusScenarioChip(
                          icon: Icons.park,
                          label: 'Open Nature',
                          subtitle: '50m / 120m',
                          isSelected: _radiusZones.start == 50 && _radiusZones.end == 120,
                          onTap: () => setState(() => _radiusZones = const RangeValues(50, 120)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _RadiusZoneSlider(
                    values: _radiusZones,
                    max: _maxRadius,
                    onChanged: (values) {
                      if ((values.end - values.start) >= 15) {
                        setState(() => _radiusZones = values);
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  if (!widget.isEditing)
                    CheckboxListTile(
                      value: _saveAsPreset,
                      onChanged: (value) => setState(() => _saveAsPreset = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: _kBrandBlue,
                      title: const Text(
                        'Save as a preset',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Keep these settings for next time to reuse.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandYellow,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Text(
                              widget.isEditing
                                  ? 'Save Changes'
                                  : (_saveAsPreset ? 'Save Tour & Preset' : 'Create Tour'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Image.asset(
                      'assets/images/bird_logo.png',
                      width: 64,
                      height: 64,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),

            if (_isDraggingPreset)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DragTarget<Tour>(
                  onAccept: (preset) async {
                    setState(() => _isDraggingPreset = false);
                    await _tourRepository.deleteTour(preset.id);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isHovering = candidateData.isNotEmpty;
                    return Container(
                      height: 90,
                      color: isHovering ? Colors.red[700] : Colors.red[500],
                      alignment: Alignment.center,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_sweep, color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Text(
                            'Drag here to delete preset',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
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
    );
  }

  void _applyPreset(Tour preset) {
    setState(() {
      _nameController.text = preset.name;
      _descriptionController.text = preset.description ?? '';
      _locationController.text = preset.startLocationName ?? '';
      _headcountController.text = preset.expectedHeadcount?.toString() ?? '';
      _existingPhotoUrl = preset.photoUrl;
      _photoFile = null;
      
      if (preset.hasStartLocation) {
        _selectedLocation = PlaceLocation(
          name: preset.startLocationName!,
          latitude: preset.startLocationLat!,
          longitude: preset.startLocationLng!,
        );
      } else {
        _selectedLocation = null;
      }

      _radiusZones = RangeValues(
        preset.greenRadiusMeters ?? 20,
        preset.amberRadiusMeters ?? 60,
      );
    });
  }
}

// ============================================================
// Full-Screen Fine-Tune Map Screen
// ============================================================
class _FineTuneMapScreen extends StatefulWidget {
  const _FineTuneMapScreen({
    required this.initialPosition,
  });

  final LatLng initialPosition;

  @override
  State<_FineTuneMapScreen> createState() => _FineTuneMapScreenState();
}

class _FineTuneMapScreenState extends State<_FineTuneMapScreen> {
  late LatLng _currentCenter;

  @override
  void initState() {
    super.initState();
    _currentCenter = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fine-Tune', style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0.0,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          TextButton(
            onPressed: () {
              final lat = _currentCenter.latitude;
              final lng = _currentCenter.longitude;
              final coordinateName = 'Meeting Point (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';

              Navigator.of(context).pop(
                PlaceLocation(
                  name: coordinateName,
                  latitude: lat,
                  longitude: lng,
                ),
              );
            },
            child: const Text('Done', style: TextStyle(color: _kBrandBlue, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition,
              zoom: 16,
            ),
            onCameraMove: (position) {
              _currentCenter = position.target;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            padding: const EdgeInsets.only(top: 80, right: 16),
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36),
              child: Icon(Icons.location_pin, size: 48, color: Colors.red),
            ),
          ),
          Positioned(
            top: 16,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/bird_logo.png',
                    width: 28,
                    height: 28,
                    errorBuilder: (_, __, ___) => const Icon(Icons.near_me, size: 20, color: _kBrandBlue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Move the map to position the pin.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
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

// ---------------- Helper widgets below ----------------
class _RadiusScenarioChip extends StatelessWidget {
  const _RadiusScenarioChip({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? _kBrandBlue.withOpacity(0.1) : _kFieldFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _kBrandBlue : _kBorderGrey,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: isSelected ? _kBrandBlue : Colors.grey[700]),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? _kBrandBlue : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ), 
          ],
        ),
      ),
    );
  }
}

class _PresetPicker extends StatelessWidget {
  const _PresetPicker({
    required this.onSelected,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final ValueChanged<Tour> onSelected;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final guideUid = AuthService().currentUser?.uid;
    if (guideUid == null) return const SizedBox.shrink();

    return StreamBuilder<List<Tour>>(
      stream: TourRepository().getPresetsForGuide(guideUid),
      builder: (context, snapshot) {
        final presets = snapshot.data ?? [];
        if (presets.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: presets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final preset = presets[index];
              return LongPressDraggable<Tour>(
                data: preset,
                onDragStarted: onDragStarted,
                onDraggableCanceled: (_, __) => onDragEnded(),
                onDragEnd: (_) => onDragEnded(),
                feedback: Material(
                  color: Colors.transparent,
                  child: ActionChip(
                    backgroundColor: _kBrandYellow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    avatar: const Icon(Icons.delete, size: 16, color: Colors.red),
                    label: Text(preset.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                child: ActionChip(
                  backgroundColor: _kFieldFill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: const BorderSide(color: _kBorderGrey),
                  ),
                  avatar: const Icon(Icons.bookmark, size: 16, color: _kBrandBlue),
                  label: Text(preset.name),
                  onPressed: () => onSelected(preset),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

String _formatDateTime(DateTime dt) {
  final date = '${dt.day}/${dt.month}/${dt.year % 100}';
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'pm' : 'am';
  return '$date · $hour:$minute$period';
}

InputDecoration _fieldDecoration({String? hintText, Widget? suffixIcon}) {
  return InputDecoration(
    hintText: hintText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: _kFieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kBrandBlue, width: 1.4),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photoFile,
    required this.existingPhotoUrl,
    required this.onTap,
  });

  final File? photoFile;
  final String? existingPhotoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget preview;
    if (photoFile != null) {
      preview = Image.file(photoFile!, fit: BoxFit.cover);
    } else if (existingPhotoUrl != null && existingPhotoUrl!.trim().isNotEmpty) {
      preview = Image.network(existingPhotoUrl!.trim(), fit: BoxFit.cover);
    } else {
      preview = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, color: Colors.grey[500], size: 28),
          const SizedBox(height: 6),
          Text('Add a photo', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _kFieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorderGrey),
        ),
        child: preview,
      ),
    );
  }
}

class _RadiusZoneSlider extends StatelessWidget {
  const _RadiusZoneSlider({
    required this.values,
    required this.max,
    required this.onChanged,
  });

  final RangeValues values;
  final double max;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: CustomPaint(
                size: const Size(double.infinity, 4),
                painter: _ThreeZoneTrackPainter(
                  greenFraction: values.start / max,
                  amberFraction: values.end / max,
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                disabledActiveTrackColor: Colors.transparent,
                disabledInactiveTrackColor: Colors.transparent,
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: RangeSlider(
                values: values,
                min: 0,
                max: max,
                divisions: max.round(),
                activeColor: _kBrandYellow,
                labels: RangeLabels(
                  '${values.start.round()}m',
                  '${values.end.round()}m',
                ),
                onChanged: onChanged,
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _ZoneLegend(color: Colors.green, label: 'Green: ${values.start.round()}m'),
            _ZoneLegend(color: Colors.amber, label: 'Amber: ${values.end.round()}m'),
            const _ZoneLegend(color: Colors.red, label: 'Red: beyond'),
          ],
        ),
      ],
    );
  }
}

class _ThreeZoneTrackPainter extends CustomPainter {
  final double greenFraction;
  final double amberFraction;

  _ThreeZoneTrackPainter({
    required this.greenFraction,
    required this.amberFraction,
  });

  @override
  bool shouldRepaint(covariant _ThreeZoneTrackPainter oldDelegate) {
    return oldDelegate.greenFraction != greenFraction ||
        oldDelegate.amberFraction != amberFraction;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final y = size.height / 2;
    final totalWidth = size.width;

    final greenEnd = totalWidth * greenFraction.clamp(0.0, 1.0);
    final amberEnd = totalWidth * amberFraction.clamp(0.0, 1.0);

    paint.color = Colors.green;
    canvas.drawLine(Offset(0, y), Offset(greenEnd, y), paint);

    paint.color = Colors.amber;
    canvas.drawLine(Offset(greenEnd, y), Offset(amberEnd, y), paint);

    paint.color = Colors.red;
    canvas.drawLine(Offset(amberEnd, y), Offset(totalWidth, y), paint);
  }
}

class _ZoneLegend extends StatelessWidget {
  const _ZoneLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}