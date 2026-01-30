#!/usr/bin/env python3
"""
Pothole Detection Model Trainer
Trains a RandomForest classifier and exports it to Dart code for mobile use.

This script:
1. Loads the mined dataset
2. Trains a RandomForest model
3. Evaluates accuracy
4. Exports the model as Dart code (if/else rules) for edge computing
"""

import os
import csv
import json
import random
from pathlib import Path

# Try to import sklearn, provide helpful message if not installed
try:
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import train_test_split, cross_val_score
    from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
    import numpy as np
except ImportError:
    print("Error: scikit-learn is required. Install it with:")
    print("  pip install scikit-learn numpy")
    exit(1)

# Try to import m2cgen for model export
try:
    import m2cgen as m2c
    HAS_M2CGEN = True
except ImportError:
    HAS_M2CGEN = False
    print("Warning: m2cgen not installed. Model export to Dart will use manual conversion.")
    print("  Install with: pip install m2cgen")

# Configuration
DATASET_PATH = "/Users/rahul/Desktop/NayakXXX/best_bike_paths/tools/ml/dataset"
OUTPUT_PATH = "/Users/rahul/Desktop/NayakXXX/best_bike_paths/tools/ml/model"

# Features to use for training
FEATURE_COLUMNS = [
    'z_mean', 'z_std', 'z_min', 'z_max', 'z_range',
    'x_mean', 'x_std', 'x_range',
    'y_mean', 'y_std', 'y_range'
]


def load_dataset(filepath):
    """Load dataset from CSV."""
    samples = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            samples.append(row)
    return samples


def prepare_data(samples):
    """Prepare features and labels for training."""
    X = []
    y = []
    
    for sample in samples:
        features = []
        valid = True
        
        for col in FEATURE_COLUMNS:
            try:
                val = float(sample[col]) if sample[col] else 0.0
                features.append(val)
            except (ValueError, KeyError):
                valid = False
                break
        
        if valid:
            X.append(features)
            y.append(1 if sample['label'] == 'pothole' else 0)
    
    return np.array(X), np.array(y)


def export_model_to_dart(model, feature_names, output_path):
    """Export the trained model to Dart code."""
    
    if HAS_M2CGEN:
        # Use m2cgen for automatic conversion
        dart_code = m2c.export_to_dart(model, function_name='predictPothole')
        
        # Wrap in a Dart class
        full_dart_code = f'''// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from SimRa Berlin pothole detection training data
// Model: RandomForestClassifier

/// Pothole detection model using Random Forest
/// Features: {feature_names}
class PotholeDetectionModel {{
  
  /// Predict if the sensor window indicates a pothole
  /// Returns probability of pothole (0.0 to 1.0)
  static double predictProbability(List<double> features) {{
    // features order: {feature_names}
    assert(features.length == {len(feature_names)}, 
        'Expected {len(feature_names)} features, got ${{features.length}}');
    
    final score = predictPothole(features);
    // Convert to probability (score is sum of tree votes)
    return score.clamp(0.0, 1.0);
  }}
  
  /// Returns true if pothole is detected (probability > 0.5)
  static bool isPothole(List<double> features) {{
    return predictProbability(features) > 0.5;
  }}
  
  /// Feature names in order
  static const List<String> featureNames = {feature_names};
  
{dart_code}
}}
'''
    else:
        # Manual conversion for simple model
        dart_code = generate_simple_dart_model(model, feature_names)
        full_dart_code = dart_code
    
    # Save to file
    os.makedirs(output_path, exist_ok=True)
    dart_file = os.path.join(output_path, 'pothole_detection_model.dart')
    
    with open(dart_file, 'w') as f:
        f.write(full_dart_code)
    
    print(f"Dart model saved to: {dart_file}")
    return dart_file


def generate_simple_dart_model(model, feature_names):
    """Generate a simple Dart model using feature importance thresholds."""
    
    # Get feature importances
    importances = model.feature_importances_
    
    # Get the most important features
    important_indices = np.argsort(importances)[::-1][:5]
    
    dart_code = f'''// AUTO-GENERATED FILE - DO NOT EDIT MANUALLY
// Generated from SimRa Berlin pothole detection training data
// Simplified threshold-based model

/// Pothole detection model using feature thresholds
/// Features: {feature_names}
class PotholeDetectionModel {{
  
  // Feature indices
'''
    
    for i, name in enumerate(feature_names):
        dart_code += f"  static const int _{name.upper()} = {i};\n"
    
    dart_code += f'''
  
  /// Feature importance (from training)
  static const List<double> featureImportance = {list(importances)};
  
  /// Predict probability of pothole
  static double predictProbability(List<double> features) {{
    assert(features.length == {len(feature_names)}, 
        'Expected {len(feature_names)} features, got ${{features.length}}');
    
    double score = 0.0;
    
    // Z-axis range (most important - high range = pothole)
    final zRange = features[_Z_RANGE];
    if (zRange > 10.0) score += 0.4;
    else if (zRange > 7.0) score += 0.25;
    else if (zRange > 5.0) score += 0.1;
    
    // Z-axis standard deviation (high variance = pothole)
    final zStd = features[_Z_STD];
    if (zStd > 3.0) score += 0.3;
    else if (zStd > 2.0) score += 0.15;
    else if (zStd > 1.5) score += 0.05;
    
    // Z-axis max (spike detection)
    final zMax = features[_Z_MAX];
    if (zMax > 15.0) score += 0.2;
    else if (zMax > 13.0) score += 0.1;
    
    // Z-axis min (drop detection)
    final zMin = features[_Z_MIN];
    if (zMin < 5.0) score += 0.2;
    else if (zMin < 7.0) score += 0.1;
    
    // X/Y axis instability (lateral movement)
    final xRange = features[_X_RANGE];
    final yRange = features[_Y_RANGE];
    if (xRange > 5.0 || yRange > 5.0) score += 0.1;
    
    return score.clamp(0.0, 1.0);
  }}
  
  /// Returns true if pothole is detected (probability > threshold)
  static bool isPothole(List<double> features, {{double threshold = 0.5}}) {{
    return predictProbability(features) > threshold;
  }}
  
  /// Feature names in order
  static const List<String> featureNames = {feature_names};
}}
'''
    
    return dart_code


def export_model_metadata(model, accuracy, report, output_path):
    """Export model metadata and performance metrics."""
    
    metadata = {
        'model_type': 'RandomForestClassifier',
        'n_estimators': model.n_estimators,
        'max_depth': model.max_depth,
        'features': FEATURE_COLUMNS,
        'n_features': len(FEATURE_COLUMNS),
        'accuracy': accuracy,
        'feature_importances': dict(zip(FEATURE_COLUMNS, model.feature_importances_.tolist())),
        'classification_report': report
    }
    
    os.makedirs(output_path, exist_ok=True)
    meta_file = os.path.join(output_path, 'model_metadata.json')
    
    with open(meta_file, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"Model metadata saved to: {meta_file}")


def main():
    print("=" * 60)
    print("Pothole Detection Model Trainer")
    print("=" * 60)
    
    # Load dataset
    dataset_file = os.path.join(DATASET_PATH, "training_data_samples.csv")
    if not os.path.exists(dataset_file):
        print(f"Error: Dataset not found at {dataset_file}")
        print("Please run pothole_data_miner.py first.")
        return
    
    print(f"\nLoading dataset from: {dataset_file}")
    samples = load_dataset(dataset_file)
    print(f"Loaded {len(samples)} samples")
    
    # Prepare data
    X, y = prepare_data(samples)
    print(f"Prepared {len(X)} valid samples")
    print(f"  Potholes: {sum(y)}")
    print(f"  Normal: {len(y) - sum(y)}")
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    print(f"\nTraining set: {len(X_train)} samples")
    print(f"Test set: {len(X_test)} samples")
    
    # Train model
    print("\nTraining RandomForest model...")
    model = RandomForestClassifier(
        n_estimators=50,  # Keep small for mobile
        max_depth=10,     # Limit depth for simplicity
        min_samples_split=5,
        min_samples_leaf=2,
        random_state=42,
        n_jobs=-1
    )
    
    model.fit(X_train, y_train)
    
    # Evaluate
    print("\n" + "=" * 60)
    print("Model Evaluation")
    print("=" * 60)
    
    # Cross-validation
    cv_scores = cross_val_score(model, X, y, cv=5)
    print(f"\nCross-validation accuracy: {cv_scores.mean():.3f} (+/- {cv_scores.std() * 2:.3f})")
    
    # Test set evaluation
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"\nTest set accuracy: {accuracy:.3f}")
    print("\nClassification Report:")
    report = classification_report(y_test, y_pred, target_names=['Normal', 'Pothole'])
    print(report)
    
    print("\nConfusion Matrix:")
    cm = confusion_matrix(y_test, y_pred)
    print(f"  TN={cm[0][0]}, FP={cm[0][1]}")
    print(f"  FN={cm[1][0]}, TP={cm[1][1]}")
    
    print("\nFeature Importances:")
    for name, importance in sorted(zip(FEATURE_COLUMNS, model.feature_importances_), 
                                    key=lambda x: x[1], reverse=True):
        print(f"  {name}: {importance:.3f}")
    
    # Export model
    print("\n" + "=" * 60)
    print("Exporting Model")
    print("=" * 60)
    
    dart_file = export_model_to_dart(model, FEATURE_COLUMNS, OUTPUT_PATH)
    export_model_metadata(model, accuracy, report, OUTPUT_PATH)
    
    print("\n" + "=" * 60)
    print("Training Complete!")
    print("=" * 60)
    print(f"\nNext steps:")
    print(f"1. Copy {dart_file}")
    print(f"   to your Flutter app's lib/services/ folder")
    print(f"2. Integrate with your sensor service")


if __name__ == "__main__":
    main()
