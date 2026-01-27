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
  final int newUpvotes;
  final int newDownvotes;

  const VerificationResult({
    required this.success,
    required this.message,
    this.newUpvotes = 0,
    this.newDownvotes = 0,
  });
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
      debugPrint('Error checking user vote: $e');
      return null;
    }
  }

  /// Submit a vote on an anomaly
  Future<VerificationResult> vote(String anomalyId, VoteType voteType) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return const VerificationResult(
        success: false,
        message: 'You must be signed in to verify reports',
      );
    }

    try {
      // Check if user has already voted
      final existingVote = await getUserVote(anomalyId);

      if (existingVote != null) {
        if (existingVote == voteType) {
          // Same vote - remove it (toggle off)
          await _supabase
              .from('anomaly_votes')
              .delete()
              .eq('anomaly_id', anomalyId)
              .eq('user_id', userId);

          // Update anomaly vote counts
          await _updateAnomalyVoteCounts(anomalyId);

          return VerificationResult(
            success: true,
            message: 'Vote removed',
            newUpvotes: await _getVoteCount(anomalyId, VoteType.upvote),
            newDownvotes: await _getVoteCount(anomalyId, VoteType.downvote),
          );
        } else {
          // Different vote - update it
          await _supabase
              .from('anomaly_votes')
              .update({'vote_type': voteType.name})
              .eq('anomaly_id', anomalyId)
              .eq('user_id', userId);

          await _updateAnomalyVoteCounts(anomalyId);

          return VerificationResult(
            success: true,
            message: voteType == VoteType.upvote
                ? 'Thanks for confirming this hazard!'
                : 'Thanks for reporting this may be fixed',
            newUpvotes: await _getVoteCount(anomalyId, VoteType.upvote),
            newDownvotes: await _getVoteCount(anomalyId, VoteType.downvote),
          );
        }
      } else {
        // New vote
        await _supabase.from('anomaly_votes').insert({
          'anomaly_id': anomalyId,
          'user_id': userId,
          'vote_type': voteType.name,
          'created_at': DateTime.now().toIso8601String(),
        });

        await _updateAnomalyVoteCounts(anomalyId);

        return VerificationResult(
          success: true,
          message: voteType == VoteType.upvote
              ? 'Thanks for confirming this hazard!'
              : 'Thanks for reporting this may be fixed',
          newUpvotes: await _getVoteCount(anomalyId, VoteType.upvote),
          newDownvotes: await _getVoteCount(anomalyId, VoteType.downvote),
        );
      }
    } catch (e) {
      debugPrint('Error voting: $e');
      return VerificationResult(
        success: false,
        message: 'Failed to submit vote: $e',
      );
    }
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
    );
  }

  /// Get verification status text
  String get verificationStatus {
    if (verified) return 'Verified by community';
    if (upvotes > 0) return '$upvotes user${upvotes > 1 ? 's' : ''} confirmed';
    return 'Not yet verified';
  }

  /// Get confidence percentage
  int get confidencePercent {
    final total = upvotes + downvotes;
    if (total == 0) return 50;
    return ((upvotes / total) * 100).round();
  }
}
