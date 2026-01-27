import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents a vote on an anomaly
enum VoteType {
  upvote, // Confirm the anomaly exists
  downvote, // Report as invalid/fixed
}

/// Result of a verification action
class VerificationResult {
  final bool success;
  final String message;
  final String? action; // 'added', 'changed', 'removed'
  final int newUpvotes;
  final int newDownvotes;
  final int verificationScore; // 0-100 percentage
  final bool isVerified;
  final VoteType? userVote;

  const VerificationResult({
    required this.success,
    required this.message,
    this.action,
    this.newUpvotes = 0,
    this.newDownvotes = 0,
    this.verificationScore = 50,
    this.isVerified = false,
    this.userVote,
  });

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    VoteType? userVote;
    final voteStr = json['user_vote']?.toString();
    if (voteStr == 'upvote') userVote = VoteType.upvote;
    if (voteStr == 'downvote') userVote = VoteType.downvote;

    return VerificationResult(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      action: json['action']?.toString(),
      newUpvotes: (json['upvotes'] as num?)?.toInt() ?? 0,
      newDownvotes: (json['downvotes'] as num?)?.toInt() ?? 0,
      verificationScore: (json['verification_score'] as num?)?.toInt() ?? 50,
      isVerified: json['verified'] == true,
      userVote: userVote,
    );
  }
}

/// Service for verifying/validating anomaly reports
class VerificationService {
  final _supabase = Supabase.instance.client;

  /// Check if current user has already voted on an anomaly
  Future<VoteType?> getUserVote(String anomalyId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final result = await _supabase
          .from('anomaly_votes')
          .select('vote_type')
          .eq('anomaly_id', anomalyId)
          .eq('user_id', userId)
          .maybeSingle();

      if (result == null) return null;

      final voteStr = result['vote_type']?.toString();
      if (voteStr == 'upvote') return VoteType.upvote;
      if (voteStr == 'downvote') return VoteType.downvote;
      return null;
    } catch (e) {
      debugPrint('[VOTE] Error checking user vote: $e');
      return null;
    }
  }

  /// Check if current user is the reporter of an anomaly
  Future<bool> isReporter(String anomalyId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final result = await _supabase
          .from('anomalies')
          .select('user_id')
          .eq('id', anomalyId)
          .maybeSingle();

      return result?['user_id'] == userId;
    } catch (e) {
      debugPrint('[VOTE] Error checking reporter: $e');
      return false;
    }
  }

  /// Submit a vote on an anomaly
  /// Rules:
  /// 1. Reporter cannot vote on their own anomaly
  /// 2. Other users can vote once, then can only remove
  /// 3. After removing, they can vote again
  Future<VerificationResult> vote(String anomalyId, VoteType voteType) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const VerificationResult(
        success: false,
        message: 'You must be signed in to verify reports',
      );
    }

    debugPrint('[VOTE] Voting on anomaly $anomalyId: ${voteType.name}');

    try {
      // Use the database RPC function (handles all rules)
      final rpcResult = await _supabase.rpc(
        'upsert_anomaly_vote',
        params: {
          'p_anomaly_id': anomalyId,
          'p_vote_type': voteType.name,
          'p_proximity_meters': null,
          'p_comment': null,
        },
      );

      if (rpcResult is Map<String, dynamic>) {
        debugPrint('[VOTE] RPC result: $rpcResult');
        return VerificationResult.fromJson(rpcResult);
      }

      return const VerificationResult(
        success: false,
        message: 'Unexpected response from server',
      );
    } catch (e) {
      debugPrint('[VOTE] Error: $e');
      
      // Parse error message for user-friendly display
      final errorMsg = e.toString();
      if (errorMsg.contains('cannot vote on your own')) {
        return const VerificationResult(
          success: false,
          message: 'You cannot vote on your own report',
        );
      }
      if (errorMsg.contains('Remove your current vote')) {
        return const VerificationResult(
          success: false,
          message: 'Remove your current vote first',
        );
      }
      
      return const VerificationResult(
        success: false,
        message: 'Failed to vote. Please try again.',
      );
    }
  }

  /// Reporter updates their anomaly status (still there / resolved)
  Future<VerificationResult> updateReporterStatus(String anomalyId, String status) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const VerificationResult(
        success: false,
        message: 'You must be signed in',
      );
    }

    try {
      final rpcResult = await _supabase.rpc(
        'update_anomaly_status_by_reporter',
        params: {
          'p_anomaly_id': anomalyId,
          'p_status': status, // 'still_there' or 'resolved'
        },
      );

      if (rpcResult is Map<String, dynamic>) {
        return VerificationResult(
          success: rpcResult['success'] == true,
          message: rpcResult['message']?.toString() ?? '',
        );
      }

      return const VerificationResult(
        success: false,
        message: 'Unexpected response',
      );
    } catch (e) {
      debugPrint('[VOTE] Reporter status update error: $e');
      return const VerificationResult(
        success: false,
        message: 'Failed to update status',
      );
    }
  }

  /// Remove user's vote (for UI that shows explicit remove button)
  Future<VerificationResult> removeVote(String anomalyId) async {
    final existingVote = await getUserVote(anomalyId);
    if (existingVote == null) {
      return const VerificationResult(
        success: false,
        message: 'No vote to remove',
      );
    }
    // Clicking same vote type removes it
    return vote(anomalyId, existingVote);
  }

  /// Get vote count for an anomaly
  Future<int> _getVoteCount(String anomalyId, VoteType voteType) async {
    try {
      final result = await _supabase
          .from('anomaly_votes')
          .select('id')
          .eq('anomaly_id', anomalyId)
          .eq('vote_type', voteType.name);

      return (result as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Update the anomaly's verified status based on votes
  Future<void> _updateAnomalyVoteCounts(String anomalyId) async {
    try {
      final upvotes = await _getVoteCount(anomalyId, VoteType.upvote);
      final downvotes = await _getVoteCount(anomalyId, VoteType.downvote);

      // Mark as verified if more upvotes than downvotes and at least 3 upvotes
      final verified = upvotes >= 3 && upvotes > downvotes;

      // Mark as resolved (soft delete) if significantly more downvotes
      final resolved = downvotes >= 5 && downvotes > upvotes * 2;

      await _supabase
          .from('anomalies')
          .update({
            'verified': verified,
            'upvotes': upvotes,
            'downvotes': downvotes,
            if (resolved) 'expires_at': DateTime.now().toIso8601String(),
          })
          .eq('id', anomalyId);
    } catch (e) {
      debugPrint('Error updating anomaly votes: $e');
    }
  }

  /// Get anomaly details with vote counts
  Future<AnomalyDetails?> getAnomalyDetails(String anomalyId) async {
    try {
      final result = await _supabase
          .from('anomalies')
          .select('*')
          .eq('id', anomalyId)
          .maybeSingle();

      if (result == null) return null;

      final userVote = await getUserVote(anomalyId);

      return AnomalyDetails.fromJson(result, userVote);
    } catch (e) {
      debugPrint('Error fetching anomaly details: $e');
      return null;
    }
  }
}

/// Detailed anomaly information including votes
class AnomalyDetails {
  final String id;
  final String category;
  final double severity;
  final bool verified;
  final int upvotes;
  final int downvotes;
  final DateTime createdAt;
  final String? description;
  final VoteType? userVote;
  final int totalVoters;

  const AnomalyDetails({
    required this.id,
    required this.category,
    required this.severity,
    required this.verified,
    required this.upvotes,
    required this.downvotes,
    required this.createdAt,
    this.description,
    this.userVote,
    this.totalVoters = 0,
  });

  factory AnomalyDetails.fromJson(
    Map<String, dynamic> json,
    VoteType? userVote,
  ) {
    return AnomalyDetails(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Unknown',
      severity: (json['severity'] as num?)?.toDouble() ?? 0.5,
      verified: json['verified'] == true,
      upvotes: (json['upvotes'] as num?)?.toInt() ?? 0,
      downvotes: (json['downvotes'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      description: json['description']?.toString(),
      userVote: userVote,
      totalVoters: ((json['upvotes'] as num?)?.toInt() ?? 0) + 
                   ((json['downvotes'] as num?)?.toInt() ?? 0),
    );
  }

  /// Get verification status text
  String get verificationStatus {
    if (verified) return '✓ Verified by community';
    if (downvotes > upvotes) return '⚠️ Possibly fixed';
    if (upvotes >= 2) return '👥 $upvotes users confirmed';
    if (upvotes == 1) return '👤 1 user confirmed';
    return '❓ Awaiting verification';
  }

  /// Get confidence percentage (0-100)
  int get confidencePercent {
    final total = upvotes + downvotes;
    if (total == 0) return 50;
    return ((upvotes / total) * 100).round();
  }

  /// Get status color name
  String get statusColorName {
    if (verified) return 'green';
    if (downvotes > upvotes) return 'orange';
    if (upvotes > 0) return 'yellow';
    return 'grey';
  }
}
