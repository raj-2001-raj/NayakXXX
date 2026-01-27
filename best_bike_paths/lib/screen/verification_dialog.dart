import 'package:flutter/material.dart';
import '../services/verification_service.dart';

/// Dialog for viewing anomaly details and voting
class VerificationDialog extends StatefulWidget {
  final String anomalyId;
  final String category;
  final double? latitude;
  final double? longitude;

  const VerificationDialog({
    super.key,
    required this.anomalyId,
    required this.category,
    this.latitude,
    this.longitude,
  });

  @override
  State<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<VerificationDialog> {
  final VerificationService _verificationService = VerificationService();

  AnomalyDetails? _details;
  bool _loading = true;
  bool _voting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);

    final details = await _verificationService.getAnomalyDetails(
      widget.anomalyId,
    );

    if (mounted) {
      setState(() {
        _details = details;
        _loading = false;
      });
    }
  }

  Future<void> _vote(VoteType voteType) async {
    setState(() {
      _voting = true;
      _message = null;
    });

    final result = await _verificationService.vote(widget.anomalyId, voteType);

    if (mounted) {
      setState(() {
        _voting = false;
        _message = result.message;
        if (result.success && _details != null) {
          _details = AnomalyDetails(
            id: _details!.id,
            category: _details!.category,
            severity: _details!.severity,
            verified:
                result.newUpvotes >= 3 &&
                result.newUpvotes > result.newDownvotes,
            upvotes: result.newUpvotes,
            downvotes: result.newDownvotes,
            createdAt: _details!.createdAt,
            description: _details!.description,
            userVote: _details!.userVote == voteType ? null : voteType,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(widget.category).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getCategoryIcon(widget.category),
                    color: _getCategoryColor(widget.category),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.latitude != null && widget.longitude != null)
                        Text(
                          '${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_details != null) ...[
              // Verification status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _details!.verified
                      ? Colors.green.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _details!.verified ? Icons.verified : Icons.help_outline,
                      color: _details!.verified ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _details!.verificationStatus,
                        style: TextStyle(
                          color: _details!.verified
                              ? Colors.green
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${_details!.confidencePercent}%',
                      style: TextStyle(
                        color: _details!.verified ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Vote counts
              Row(
                children: [
                  Expanded(
                    child: _buildVoteCard(
                      icon: Icons.thumb_up,
                      count: _details!.upvotes,
                      label: 'Confirmed',
                      color: Colors.green,
                      isSelected: _details!.userVote == VoteType.upvote,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildVoteCard(
                      icon: Icons.thumb_down,
                      count: _details!.downvotes,
                      label: 'Fixed/Invalid',
                      color: Colors.orange,
                      isSelected: _details!.userVote == VoteType.downvote,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Voting buttons
              const Text(
                'Is this hazard still present?',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _voting ? null : () => _vote(VoteType.upvote),
                      icon: const Icon(Icons.check),
                      label: const Text('YES, IT\'S THERE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _details!.userVote == VoteType.upvote
                            ? Colors.green
                            : Colors.green.withOpacity(0.3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _voting
                          ? null
                          : () => _vote(VoteType.downvote),
                      icon: const Icon(Icons.close),
                      label: const Text('NO, IT\'S FIXED'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _details!.userVote == VoteType.downvote
                            ? Colors.orange
                            : Colors.orange.withOpacity(0.3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: const TextStyle(
                    color: Colors.lightGreenAccent,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 8),

              // Info text
              const Text(
                'Your vote helps improve route safety for all cyclists.',
                style: TextStyle(color: Colors.grey, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ] else
              const Center(
                child: Text(
                  'Could not load details',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteCard({
    required IconData icon,
    required int count,
    required String label,
    required Color color,
    required bool isSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.3) : const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: color, width: 2) : null,
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'pothole':
      case 'bump':
        return Colors.red;
      case 'crack':
        return Colors.orange;
      case 'debris':
      case 'broken glass':
        return Colors.amber;
      case 'construction':
        return Colors.yellow;
      case 'flooding':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'pothole':
        return Icons.warning;
      case 'bump':
        return Icons.trending_up;
      case 'crack':
        return Icons.grain;
      case 'debris':
      case 'broken glass':
        return Icons.broken_image;
      case 'construction':
        return Icons.construction;
      case 'flooding':
        return Icons.water;
      default:
        return Icons.report_problem;
    }
  }
}
