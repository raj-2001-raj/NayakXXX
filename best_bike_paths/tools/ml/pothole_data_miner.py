#!/usr/bin/env python3
"""
SimRa Dataset Pothole Data Miner
Extracts pothole and normal riding samples from SimRa Berlin bike ride data.

The dataset contains accelerometer readings with Z-axis values that indicate:
- Normal riding: Z around 9.8 m/s² (gravity)
- Pothole impact: Z spikes significantly higher or lower

This script extracts 2-second windows (based on timestamps) and labels them.
"""

import os
import sys
import csv
import random
from pathlib import Path
from collections import defaultdict
import json

# Configuration
DATASET_PATH = "/Users/rahul/Desktop/Dataset/Berlin_04_2024_02_2025/Berlin/Rides"
OUTPUT_PATH = "/Users/rahul/Desktop/NayakXXX/best_bike_paths/tools/ml/dataset"
WINDOW_SIZE_MS = 2000  # 2 seconds in milliseconds
MIN_SAMPLES_PER_WINDOW = 20  # Minimum sensor readings per window

# Thresholds for detection (Z-axis in m/s²)
# Normal gravity is ~9.8, so we look for significant deviations
POTHOLE_HIGH_THRESHOLD = 14.0  # Strong upward acceleration (hitting pothole)
POTHOLE_LOW_THRESHOLD = 5.5    # Strong downward (falling into pothole)
NORMAL_MIN = 7.5   # More lenient for normal classification
NORMAL_MAX = 12.5  # More lenient for normal classification

# Targets
TARGET_POTHOLE_SAMPLES = 500
TARGET_NORMAL_SAMPLES = 500


def parse_ride_file(filepath):
    """Parse a SimRa ride file and extract sensor data."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Split by the separator
        parts = content.split('=========================')
        if len(parts) < 2:
            return None, None
        
        # Parse incidents (before separator)
        incident_section = parts[0].strip()
        incidents = []
        incident_lines = incident_section.split('\n')
        for line in incident_lines[2:]:  # Skip version and header
            if line.strip() and not line.startswith('key'):
                parts_line = line.split(',')
                if len(parts_line) > 8:
                    try:
                        incident_type = int(parts_line[8]) if parts_line[8] else 0
                        lat = float(parts_line[1]) if parts_line[1] else None
                        lon = float(parts_line[2]) if parts_line[2] else None
                        ts = int(parts_line[3]) if parts_line[3] else None
                        if incident_type > 0:  # Real incident (not dummy)
                            incidents.append({
                                'type': incident_type,
                                'lat': lat,
                                'lon': lon,
                                'ts': ts
                            })
                    except (ValueError, IndexError):
                        pass
        
        # Parse ride data (after separator)
        ride_section = parts[1].strip()
        ride_lines = ride_section.split('\n')
        
        sensor_data = []
        for line in ride_lines[2:]:  # Skip version and header
            if line.strip():
                cols = line.split(',')
                if len(cols) >= 6:
                    try:
                        # Extract relevant columns
                        lat = float(cols[0]) if cols[0] else None
                        lon = float(cols[1]) if cols[1] else None
                        x = float(cols[2]) if cols[2] else None
                        y = float(cols[3]) if cols[3] else None
                        z = float(cols[4]) if cols[4] else None
                        ts = int(cols[5]) if cols[5] else None
                        
                        # Also get linear acceleration if available (XL, YL, ZL at indices 15, 16, 17)
                        xl = float(cols[15]) if len(cols) > 15 and cols[15] else None
                        yl = float(cols[16]) if len(cols) > 16 and cols[16] else None
                        zl = float(cols[17]) if len(cols) > 17 and cols[17] else None
                        
                        if z is not None and ts is not None:
                            sensor_data.append({
                                'lat': lat,
                                'lon': lon,
                                'x': x,
                                'y': y,
                                'z': z,
                                'ts': ts,
                                'xl': xl,
                                'yl': yl,
                                'zl': zl
                            })
                    except (ValueError, IndexError):
                        pass
        
        return incidents, sensor_data
    
    except Exception as e:
        return None, None


def extract_windows(sensor_data):
    """Extract 2-second windows from sensor data."""
    if not sensor_data or len(sensor_data) < MIN_SAMPLES_PER_WINDOW:
        return []
    
    windows = []
    i = 0
    
    while i < len(sensor_data):
        start_ts = sensor_data[i]['ts']
        window = []
        j = i
        
        # Collect samples within the window
        while j < len(sensor_data) and (sensor_data[j]['ts'] - start_ts) < WINDOW_SIZE_MS:
            window.append(sensor_data[j])
            j += 1
        
        if len(window) >= MIN_SAMPLES_PER_WINDOW:
            windows.append(window)
        
        # Move to next window (50% overlap)
        i += max(1, len(window) // 2)
    
    return windows


def classify_window(window):
    """
    Classify a window as pothole or normal based on Z-axis values.
    Returns: 'pothole', 'normal', or None (ambiguous)
    """
    z_values = [s['z'] for s in window if s['z'] is not None]
    
    if not z_values:
        return None
    
    max_z = max(z_values)
    min_z = min(z_values)
    std_z = (sum((z - sum(z_values)/len(z_values))**2 for z in z_values) / len(z_values)) ** 0.5
    
    # Pothole detection: significant spike or drop
    if max_z > POTHOLE_HIGH_THRESHOLD or min_z < POTHOLE_LOW_THRESHOLD:
        return 'pothole'
    
    # Normal: stable readings around gravity
    if NORMAL_MIN <= min_z and max_z <= NORMAL_MAX and std_z < 2.5:
        return 'normal'
    
    return None  # Ambiguous


def compute_features(window):
    """Compute features for a window."""
    z_values = [s['z'] for s in window if s['z'] is not None]
    x_values = [s['x'] for s in window if s['x'] is not None]
    y_values = [s['y'] for s in window if s['y'] is not None]
    
    if not z_values:
        return None
    
    def stats(values):
        if not values:
            return {'mean': 0, 'std': 0, 'min': 0, 'max': 0, 'range': 0}
        mean = sum(values) / len(values)
        std = (sum((v - mean)**2 for v in values) / len(values)) ** 0.5
        return {
            'mean': mean,
            'std': std,
            'min': min(values),
            'max': max(values),
            'range': max(values) - min(values)
        }
    
    z_stats = stats(z_values)
    x_stats = stats(x_values)
    y_stats = stats(y_values)
    
    # Get location from first sample with GPS
    lat, lon = None, None
    for s in window:
        if s['lat'] and s['lon']:
            lat, lon = s['lat'], s['lon']
            break
    
    return {
        'z_mean': z_stats['mean'],
        'z_std': z_stats['std'],
        'z_min': z_stats['min'],
        'z_max': z_stats['max'],
        'z_range': z_stats['range'],
        'x_mean': x_stats['mean'],
        'x_std': x_stats['std'],
        'x_range': x_stats['range'],
        'y_mean': y_stats['mean'],
        'y_std': y_stats['std'],
        'y_range': y_stats['range'],
        'sample_count': len(z_values),
        'lat': lat,
        'lon': lon,
        'timestamp': window[0]['ts'] if window else None
    }


def save_samples(samples, label, output_dir):
    """Save samples to CSV file."""
    os.makedirs(output_dir, exist_ok=True)
    filepath = os.path.join(output_dir, f"{label}_samples.csv")
    
    if not samples:
        return
    
    fieldnames = list(samples[0].keys())
    
    with open(filepath, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(samples)
    
    print(f"Saved {len(samples)} {label} samples to {filepath}")


def main():
    print("=" * 60)
    print("SimRa Pothole Data Miner")
    print("=" * 60)
    
    # Create output directory
    os.makedirs(OUTPUT_PATH, exist_ok=True)
    
    pothole_samples = []
    normal_samples = []
    
    files_processed = 0
    total_windows = 0
    
    # Walk through all ride files
    for year_dir in ['2024', '2025']:
        year_path = os.path.join(DATASET_PATH, year_dir)
        if not os.path.exists(year_path):
            continue
        
        for month in os.listdir(year_path):
            month_path = os.path.join(year_path, month)
            if not os.path.isdir(month_path):
                continue
            
            print(f"\nProcessing {year_dir}/{month}...")
            
            for ride_file in os.listdir(month_path):
                if len(pothole_samples) >= TARGET_POTHOLE_SAMPLES and len(normal_samples) >= TARGET_NORMAL_SAMPLES:
                    break
                
                ride_path = os.path.join(month_path, ride_file)
                if not os.path.isfile(ride_path):
                    continue
                
                incidents, sensor_data = parse_ride_file(ride_path)
                if not sensor_data:
                    continue
                
                files_processed += 1
                windows = extract_windows(sensor_data)
                total_windows += len(windows)
                
                for window in windows:
                    label = classify_window(window)
                    features = compute_features(window)
                    
                    if features is None:
                        continue
                    
                    if label == 'pothole' and len(pothole_samples) < TARGET_POTHOLE_SAMPLES:
                        features['label'] = 'pothole'
                        pothole_samples.append(features)
                    elif label == 'normal' and len(normal_samples) < TARGET_NORMAL_SAMPLES:
                        features['label'] = 'normal'
                        normal_samples.append(features)
                
                if files_processed % 100 == 0:
                    print(f"  Processed {files_processed} files, {len(pothole_samples)} potholes, {len(normal_samples)} normal")
            
            if len(pothole_samples) >= TARGET_POTHOLE_SAMPLES and len(normal_samples) >= TARGET_NORMAL_SAMPLES:
                break
        
        if len(pothole_samples) >= TARGET_POTHOLE_SAMPLES and len(normal_samples) >= TARGET_NORMAL_SAMPLES:
            break
    
    print("\n" + "=" * 60)
    print("Mining Complete!")
    print("=" * 60)
    print(f"Files processed: {files_processed}")
    print(f"Total windows analyzed: {total_windows}")
    print(f"Pothole samples: {len(pothole_samples)}")
    print(f"Normal samples: {len(normal_samples)}")
    
    # Combine and save
    all_samples = pothole_samples + normal_samples
    random.shuffle(all_samples)
    
    save_samples(all_samples, "training_data", OUTPUT_PATH)
    save_samples(pothole_samples, "pothole", OUTPUT_PATH)
    save_samples(normal_samples, "normal", OUTPUT_PATH)
    
    # Save summary
    summary = {
        'files_processed': files_processed,
        'total_windows': total_windows,
        'pothole_samples': len(pothole_samples),
        'normal_samples': len(normal_samples),
        'features': ['z_mean', 'z_std', 'z_min', 'z_max', 'z_range', 
                     'x_mean', 'x_std', 'x_range', 
                     'y_mean', 'y_std', 'y_range', 'sample_count'],
        'thresholds': {
            'pothole_high': POTHOLE_HIGH_THRESHOLD,
            'pothole_low': POTHOLE_LOW_THRESHOLD,
            'normal_min': NORMAL_MIN,
            'normal_max': NORMAL_MAX
        }
    }
    
    with open(os.path.join(OUTPUT_PATH, 'mining_summary.json'), 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\nDataset saved to: {OUTPUT_PATH}")
    print("Next step: Run train_pothole_model.py to train the ML model")


if __name__ == "__main__":
    main()
