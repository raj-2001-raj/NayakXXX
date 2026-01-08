import 'package:flutter/material.dart';

class ManualReportDialog extends StatelessWidget {
  const ManualReportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const Text(
                  'Report Issue',
                  style: TextStyle(
                    color: Color(0xFF00FF00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'What obstacle is at your current location?',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 15,
              runSpacing: 15,
              children: [
                _buildOption(context, 'Pothole', Icons.radio_button_unchecked),
                _buildOption(context, 'Roadwork', Icons.construction),
                _buildOption(context, 'Glass', Icons.wine_bar),
                _buildOption(context, 'Blocked', Icons.block),
                _buildOption(context, 'No Light', Icons.lightbulb_outline),
                _buildOption(context, 'Other', Icons.warning_amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, String label, IconData icon) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, label),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
