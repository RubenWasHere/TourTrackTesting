// ============================================================
// services/calendar_sync_service.dart
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/tour.dart';

class CalendarSyncService {
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  /// Requests read/write calendar permissions from the OS.
  Future<bool> requestPermissions() async {
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (permissionsGranted.isSuccess && !(permissionsGranted.data ?? false)) {
      permissionsGranted = await _deviceCalendarPlugin.requestPermissions();
    }
    final granted = permissionsGranted.isSuccess && (permissionsGranted.data ?? false);
    debugPrint('Calendar permission granted: $granted');
    return granted;
  }

  /// Syncs a single tour to the device calendar. 
  Future<String?> syncTour(Tour tour) async {
    if (tour.scheduledAt == null) return null;

    tz.initializeTimeZones();
    final hasPermission = await requestPermissions();
    if (!hasPermission) return null;

    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    final calendars = calendarsResult.data;
    if (calendars == null || calendars.isEmpty) return null;

    final defaultCalendar = calendars.firstWhere(
      (cal) => cal.isDefault ?? false,
      orElse: () => calendars.first,
    );

    if (defaultCalendar.id == null) return null;

    final startTime = tz.TZDateTime.from(tour.scheduledAt!, tz.local);
    // Set duration to 5 minutes for a check-in reminder
    final endTime = startTime.add(const Duration(minutes: 5));

    final tourDescription = (tour.description != null && tour.description!.trim().isNotEmpty)
        ? tour.description!.trim()
        : 'Your tour is starting!';
    
    final fullDescription = '$tourDescription\n\nJoin Code: ${tour.joinCode}';

    final event = Event(
      defaultCalendar.id,
      eventId: tour.calendarEventId,
      title: 'TourTrack: ${tour.name}',
      description: fullDescription,
      location: tour.startLocationName ?? 'Scheduled Tour Location',
      start: startTime,
      end: endTime,
      reminders: [Reminder(minutes: 60)],
    );

    final result = await _deviceCalendarPlugin.createOrUpdateEvent(event);
    if (result?.isSuccess ?? false) {
      debugPrint('Successfully synced tour event: ${tour.name} (Event ID: ${result?.data})');
      return result?.data;
    } else {
      debugPrint('Failed to sync tour ${tour.name}');
      return null;
    }
  }

  /// Deletes an event from the device calendar when a tour is deleted.
  Future<void> deleteTourFromDevice(Tour tour) async {
    if (tour.calendarEventId == null) return;

    final hasPermission = await requestPermissions();
    if (!hasPermission) return;

    final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    final calendars = calendarsResult.data;
    if (calendars == null || calendars.isEmpty) return;

    final defaultCalendar = calendars.firstWhere(
      (cal) => cal.isDefault ?? false,
      orElse: () => calendars.first,
    );

    if (defaultCalendar.id != null) {
      await _deviceCalendarPlugin.deleteEvent(defaultCalendar.id!, tour.calendarEventId!);
      debugPrint('Removed tour ${tour.name} from device calendar.');
    }
  }

  /// Backfills all upcoming tours.
  Future<void> syncAllUpcomingTours(
    List<Tour> tours, {
    required Future<void> Function(String tourId, String calendarEventId) onEventSynced,
  }) async {
    final now = DateTime.now();

    for (final tour in tours) {
      if (tour.scheduledAt == null || tour.scheduledAt!.isBefore(now)) continue;

      final eventId = await syncTour(tour);
      if (eventId != null) {
        await onEventSynced(tour.id, eventId);
      }
    }
  }
}