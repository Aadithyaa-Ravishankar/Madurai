import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/supabase_config.dart';
import 'package:video_player/video_player.dart';

class ComplaintDetailsPage extends StatefulWidget {
  final Map<String, dynamic> complaint;

  const ComplaintDetailsPage({
    Key? key,
    required this.complaint,
  }) : super(key: key);

  @override
  State<ComplaintDetailsPage> createState() => _ComplaintDetailsPageState();
}

class _ComplaintDetailsPageState extends State<ComplaintDetailsPage> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  void _showImagePreview() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.network(
                  _getStorageUrl(widget.complaint['image_url']),
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVideoPreview() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: _videoController?.value.aspectRatio ?? 16/9,
                child: VideoPlayer(_videoController!),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    _videoController?.pause();
                    Navigator.of(context).pop();
                  },
                ),
              ),
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        _videoController?.value.isPlaying ?? false
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          if (_videoController?.value.isPlaying ?? false) {
                            _videoController?.pause();
                          } else {
                            _videoController?.play();
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStorageUrl(String path) {
    // If the path is already a full URL, return it as is
    if (path.startsWith('http')) {
      // Remove duplicate complaint-attachments if present
      if (path.contains('/complaint-attachments/complaint-attachments/')) {
        path = path.replaceFirst('/complaint-attachments/complaint-attachments/', '/complaint-attachments/');
      }
      return path;
    }
    
    // If the path is a relative path (e.g., "user-id/images/filename.jpg")
    String filePath = path;
    
    // Get the public URL from Supabase
    final url = SupabaseConfig.client.storage
        .from('complaint-attachments')
        .getPublicUrl(filePath);
    
    print('Original path: $path');
    print('Extracted file path: $filePath');
    print('Generated URL: $url');
    return url;
  }

  @override
  void initState() {
    super.initState();
    if (widget.complaint['video_url'] != null) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    try {
      final videoUrl = widget.complaint['video_url'];
      if (videoUrl != null) {
        final formattedUrl = _getStorageUrl(videoUrl);
        print('Loading video from URL: $formattedUrl');
        _videoController = VideoPlayerController.network(formattedUrl);
        await _videoController!.initialize();
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
          });
        }
      }
    } catch (e) {
      print('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'in progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'road damage':
        return Icons.alt_route;
      case 'street light not working':
        return Icons.lightbulb_outline;
      case 'garbage collection':
        return Icons.delete_outline;
      case 'water supply issues':
        return Icons.opacity;
      case 'power outage':
        return Icons.power_settings_new;
      case 'noise complaint':
        return Icons.volume_up_outlined;
      case 'public transport issues':
        return Icons.directions_bus;
      case 'stray animals':
        return Icons.pets;
      default:
        return Icons.report_problem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(widget.complaint['created_at']);
    final formattedDate = DateFormat('MMM d, y').format(date);
    final dateOccurred = DateTime.parse(widget.complaint['date_occurred']);
    final formattedDateOccurred = DateFormat('MMM d, y').format(dateOccurred);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Complaint Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getCategoryIcon(widget.complaint['complaint_type']),
                      color: const Color(0xFFDC2626),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.complaint['complaint_type'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Filed on $formattedDate',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(widget.complaint['status']).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.complaint['status'].toString().toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(widget.complaint['status']),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Description Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.complaint['description'],
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Details Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.calendar_today, 'Date Occurred', formattedDateOccurred),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.email, 'Email', widget.complaint['email_id']),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.phone, 'Phone', widget.complaint['phone_no']),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.location_on, 'Address', widget.complaint['address'] ?? 'No address'),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.numbers, 'Ward Number', widget.complaint['ward_no'].toString()),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Attachments Card
            if (widget.complaint['image_url'] != null || widget.complaint['video_url'] != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Attachments',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (widget.complaint['image_url'] != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Image',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _showImagePreview,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _getStorageUrl(widget.complaint['image_url']),
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  print('Error loading image: $error');
                                  print('Attempted URL: ${_getStorageUrl(widget.complaint['image_url'])}');
                                  return Container(
                                    width: double.infinity,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.error_outline,
                                        size: 48,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: double.infinity,
                                    height: 200,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[200],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                        color: const Color(0xFFDC2626),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (widget.complaint['video_url'] != null) ...[
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Video',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _isVideoInitialized ? _showVideoPreview : null,
                            child: Container(
                              width: double.infinity,
                              height: 200,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isVideoInitialized
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        AspectRatio(
                                          aspectRatio: _videoController!.value.aspectRatio,
                                          child: VideoPlayer(_videoController!),
                                        ),
                                        Icon(
                                          Icons.play_circle_outline,
                                          size: 48,
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ],
                                    )
                                  : const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
} 