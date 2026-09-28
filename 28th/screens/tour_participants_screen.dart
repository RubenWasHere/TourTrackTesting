// ============================================================
// tour_participants_screen.dart
// ============================================================
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // ✅ Correct// or your google maps import

const _kBrandBlue = Color(0xFF1F4E9E);
const _kBrandYellow = Color(0xFFFFDE59);

class TourParticipantsScreen extends StatefulWidget {
  const TourParticipantsScreen({
    super.key,
    required this.tourId,
    required this.tourName,
    required this.elapsedTime,
    required this.guidePosition,
    required this.greenRadius,
    required this.amberRadius,
  });

  final String tourId;
  final String tourName;
  final String elapsedTime;
  final LatLng? guidePosition;
  final double greenRadius;
  final double amberRadius;

  @override
  State<TourParticipantsScreen> createState() => _TourParticipantsScreenState();
}

class _TourParticipantsScreenState extends State<TourParticipantsScreen> {
  String _selectedFilter = 'all'; // 'all', 'zone', 'out', 'pacing'

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Custom Header matching mockup
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: _kBrandBlue),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    'TourTrack',
                    style: TextStyle(
                      color: _kBrandBlue,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Nunito',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.black87),
                    onPressed: () {
                      // Handle settings action if needed
                    },
                  ),
                ],
              ),
            ),
            Text(
              '${widget.tourName} • ${widget.elapsedTime}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 16),

            // Stream Builder to calculate counts and filter lists live
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('tours')
                    .doc(widget.tourId)
                    .collection('locations')
                    .snapshots(),
                builder: (context, locationSnapshot) {
                  final locDocs = locationSnapshot.hasData ? locationSnapshot.data!.docs : [];
                  
                  // Map locations by user ID
                  final Map<String, Map<String, dynamic>> locationMap = {};
                  for (var doc in locDocs) {
                    if (doc.data()['role'] != 'guide') {
                      locationMap[doc.id] = doc.data();
                    }
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tours')
                        .doc(widget.tourId)
                        .collection('participants')
                        .snapshots(),
                    builder: (context, participantSnapshot) {
                      if (!participantSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: _kBrandBlue));
                      }

                      final participantDocs = participantSnapshot.data!.docs;

                      int zoneCount = 0;
                      int outCount = 0;
                      int pacingCount = 0;

                      List<Map<String, dynamic>> processedParticipants = [];

                      for (var pDoc in participantDocs) {
                        final pData = pDoc.data() as Map<String, dynamic>? ?? {};
                        final uid = pDoc.id;
                        final name = pData['name'] ?? pData['displayName'] ?? 'Tourist';
                        final locData = locationMap[uid];

                        double distance = 9999;
                        if (locData != null && widget.guidePosition != null) {
                          final lat = (locData['latitude'] as num?)?.toDouble() ?? 0;
                          final lng = (locData['longitude'] as num?)?.toDouble() ?? 0;
                          distance = Geolocator.distanceBetween(
                            widget.guidePosition!.latitude,
                            widget.guidePosition!.longitude,
                            lat,
                            lng,
                          );
                        }

                        // Determine zone status
                        String status = 'In zone';
                        Color statusColor = Colors.green;
                        bool isOut = false;
                        bool isPacing = false;
                        bool hasSos = pData['sos'] == true;

                        if (hasSos) {
                          status = 'Sent A SOS signal';
                          statusColor = Colors.red;
                          outCount++;
                          isOut = true;
                        } else if (distance > widget.amberRadius) {
                          status = 'Out of Zone';
                          statusColor = Colors.red;
                          outCount++;
                          isOut = true;
                        } else if (distance > widget.greenRadius) {
                          status = 'Amber Zone (Pacing)';
                          statusColor = Colors.orange;
                          pacingCount++;
                          isPacing = true;
                        } else {
                          zoneCount++;
                        }

                        processedParticipants.add({
                          'id': uid,
                          'name': name,
                          'status': status,
                          'statusColor': statusColor,
                          'isOut': isOut,
                          'isPacing': isPacing,
                          'hasSos': hasSos,
                          'distance': distance,
                        });
                      }

                      // Apply filtering
                      final filteredList = processedParticipants.where((p) {
                        if (_selectedFilter == 'zone') return !p['isOut'] && !p['isPacing'];
                        if (_selectedFilter == 'out') return p['isOut'] || p['hasSos'];
                        if (_selectedFilter == 'pacing') return p['isPacing'];
                        return true;
                      }).toList();

                      return Column(
                        children: [
                          // Filter Chips Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Text('Filters: ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(width: 8),
                                _buildFilterChip('Zone: $zoneCount', 'zone', Colors.green),
                                const SizedBox(width: 8),
                                _buildFilterChip('Out: $outCount', 'out', Colors.red),
                                const SizedBox(width: 8),
                                _buildFilterChip('Pacing: $pacingCount', 'pacing', Colors.orange),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Participant List
                          Expanded(
                            child: filteredList.isEmpty
                                ? const Center(child: Text('No participants match this filter.', style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    itemCount: filteredList.length,
                                    itemBuilder: (context, index) {
                                      final p = filteredList[index];
                                      final bool isHighlighted = p['isOut'] || p['hasSos'];

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: isHighlighted
                                              ? Border.all(color: Colors.red.shade300, width: 2)
                                              : null,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.04),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            // Avatar with Status Dot
                                            Stack(
                                              children: [
                                                CircleAvatar(
                                                  radius: 24,
                                                  backgroundColor: _kBrandBlue.withOpacity(0.15),
                                                  child: Text(
                                                    _getInitials(p['name']),
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: _kBrandBlue,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  bottom: 0,
                                                  right: 0,
                                                  child: Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: p['statusColor'],
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white, width: 2),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 14),

                                            // Name & Status
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (p['hasSos'])
                                                    Row(
                                                      children: const [
                                                        Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                                                        SizedBox(width: 4),
                                                        Text('SOS Alert', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                                                      ],
                                                    ),
                                                  Text(
                                                    p['name'],
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                      color: Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    p['status'],
                                                    style: TextStyle(
                                                      color: p['statusColor'],
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Action Buttons (Ping, Call, Track)
                                            Column(
                                              children: [
                                                Row(
                                                  children: [
                                                    _actionButton('Ping', Colors.amber.shade200, Colors.black, Icons.wifi_tethering, () {
                                                      // Implement Ping notification action
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(content: Text('Pinged ${p['name']}!')),
                                                      );
                                                    }),
                                                    const SizedBox(width: 6),
                                                    _actionButton('Call', Colors.green.shade100, Colors.green.shade800, Icons.phone_outlined, () {
                                                      // Implement Call action
                                                    }),
                                                  ],
                                                ),
                                                if (p['isOut'] || p['hasSos']) ...[
                                                  const SizedBox(height: 6),
                                                  SizedBox(
                                                    width: 126,
                                                    child: _actionButton('Track', Colors.red.shade100, Colors.red.shade800, Icons.location_on_outlined, () {
                                                      // Pop back to map and focus on this tourist
                                                      Navigator.of(context).pop(p['id']);
                                                    }),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey, Color color) {
    final bool isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = isSelected ? 'all' : filterKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.grey.shade300, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color.withOpacity(0.9) : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color bgColor, Color textColor, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}