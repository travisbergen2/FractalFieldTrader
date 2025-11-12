#!/usr/bin/env python3
"""
FPF ML Training Pipeline
Trains a logistic regression model on FPF features to predict profitable trades.
Exports weights in format compatible with MLPredictor.mqh
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import classification_report, confusion_matrix, roc_auc_score, precision_recall_curve
import seaborn as sns
import os

# Configuration
DATA_FILE = "TradeData.csv"
MODEL_FILE = "fpf_model.txt"
MIN_TRADES = 50  # Minimum trades needed for training

def load_and_prepare_data(filepath):
    """Load TradeData.csv and prepare features/labels"""
    print(f"Loading data from {filepath}...")

    if not os.path.exists(filepath):
        print(f"❌ ERROR: {filepath} not found!")
        print("   Please run the EA first to collect training data.")
        return None, None, None

    df = pd.read_csv(filepath)
    print(f"✅ Loaded {len(df)} trades")

    if len(df) < MIN_TRADES:
        print(f"⚠️  WARNING: Need at least {MIN_TRADES} trades for training. Current: {len(df)}")
        print("   Run EA longer to collect more data.")
        return None, None, None

    # Extract features
    feature_cols = []

    # Standard features
    if 'Coh' in df.columns:
        feature_cols.extend(['Coh', 'Align', 'Conf', 'S', 'A'])

    # FPF features (if available)
    fpf_cols = ['FPF_S_norm', 'FPF_A_norm', 'FPF_J_norm', 'FPF_OrbRatio',
                'FPF_SpotX', 'FPF_SpotY', 'FPF_AngVel']
    available_fpf = [col for col in fpf_cols if col in df.columns]
    feature_cols.extend(available_fpf)

    # Fallback features if FPF not available
    if len(available_fpf) == 0:
        print("⚠️  FPF features not found, using traditional features")
        feature_cols.extend(['Buy', 'Sell', 'Greed', 'Fear'])

    # Pad to 11 features if needed
    while len(feature_cols) < 11:
        feature_cols.append(feature_cols[-1])  # Duplicate last feature

    feature_cols = feature_cols[:11]  # Ensure exactly 11

    print(f"   Features: {feature_cols}")

    # Create feature matrix
    X = df[feature_cols].values

    # Create labels (we'll need to compute this from trade outcomes)
    # For now, use a simple heuristic: trades with positive trend are labeled 1
    # In production, you'd track actual P&L
    y = np.zeros(len(df))
    if 'Direction' in df.columns and 'TrendPct' in df.columns:
        for i in range(len(df)):
            direction = 1 if df['Direction'].iloc[i] == 'LONG' else -1
            trend = df['TrendPct'].iloc[i]
            # Profitable if direction aligns with trend
            y[i] = 1 if (direction * trend > 0.5) else 0
    else:
        # Fallback: random labels for initial training
        y = (np.random.rand(len(df)) > 0.5).astype(int)
        print("⚠️  WARNING: Using random labels. Update with actual trade outcomes!")

    print(f"   Positive trades: {int(y.sum())} ({y.mean()*100:.1f}%)")

    return X, y, feature_cols

def train_model(X, y):
    """Train logistic regression model with time-series cross-validation"""
    print("\nTraining model...")

    # Normalize features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # Time-series split for validation
    tscv = TimeSeriesSplit(n_splits=5)

    # Train model
    model = LogisticRegression(
        C=0.1,  # Regularization
        max_iter=1000,
        random_state=42,
        class_weight='balanced'  # Handle imbalanced classes
    )

    # Cross-validation scores
    val_scores = []
    val_precisions = []

    for fold, (train_idx, val_idx) in enumerate(tscv.split(X_scaled)):
        X_train, X_val = X_scaled[train_idx], X_scaled[val_idx]
        y_train, y_val = y[train_idx], y[val_idx]

        model.fit(X_train, y_train)
        score = model.score(X_val, y_val)

        y_pred = model.predict(X_val)
        precision = (y_pred[y_pred == 1] == y_val[y_pred == 1]).mean() if y_pred.sum() > 0 else 0

        val_scores.append(score)
        val_precisions.append(precision)

        print(f"   Fold {fold+1}: Accuracy={score:.3f}, Precision={precision:.3f}")

    print(f"   Mean CV Accuracy: {np.mean(val_scores):.3f} ± {np.std(val_scores):.3f}")
    print(f"   Mean CV Precision: {np.mean(val_precisions):.3f} ± {np.std(val_precisions):.3f}")

    # Train final model on all data
    model.fit(X_scaled, y)

    # Evaluation
    y_pred = model.predict(X_scaled)
    y_prob = model.predict_proba(X_scaled)[:, 1]

    print("\n📊 Final Model Performance:")
    print(classification_report(y, y_pred))

    if len(np.unique(y)) > 1:
        auc = roc_auc_score(y, y_prob)
        print(f"   ROC-AUC: {auc:.3f}")

    return model, scaler

def export_model(model, scaler, filepath):
    """Export model weights in format compatible with MLPredictor.mqh"""
    print(f"\nExporting model to {filepath}...")

    # Combine scaling and weights
    # The EA will use raw features, so we need to incorporate scaling
    # For logistic regression: prediction = sigmoid(bias + sum(weight_i * feature_i))
    # With scaling: feature_scaled = (feature - mean) / std
    # Combined: sigmoid(bias + sum(weight_i * (feature_i - mean_i) / std_i))
    #         = sigmoid(bias - sum(weight_i * mean_i / std_i) + sum(weight_i / std_i * feature_i))
    # New bias = bias - sum(weight_i * mean_i / std_i)
    # New weights = weight_i / std_i

    weights = model.coef_[0]
    bias = model.intercept_[0]

    # Incorporate scaling into weights
    scaled_weights = weights / scaler.scale_
    scaled_bias = bias - np.sum(weights * scaler.mean_ / scaler.scale_)

    with open(filepath, 'w') as f:
        for w in scaled_weights:
            f.write(f"{w}\n")
        f.write(f"{scaled_bias}\n")

    print(f"✅ Model exported successfully")
    print(f"   Weights: {scaled_weights}")
    print(f"   Bias: {scaled_bias}")

def plot_analysis(X, y, model, scaler, feature_names):
    """Create analysis plots"""
    print("\nGenerating analysis plots...")

    X_scaled = scaler.transform(X)
    y_prob = model.predict_proba(X_scaled)[:, 1]
    y_pred = model.predict(X_scaled)

    fig, axes = plt.subplots(2, 2, figsize=(12, 10))

    # 1. Confusion Matrix
    cm = confusion_matrix(y, y_pred)
    sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', ax=axes[0, 0])
    axes[0, 0].set_title('Confusion Matrix')
    axes[0, 0].set_xlabel('Predicted')
    axes[0, 0].set_ylabel('Actual')

    # 2. Probability Distribution
    axes[0, 1].hist(y_prob[y == 0], bins=30, alpha=0.5, label='Losing Trades', color='red')
    axes[0, 1].hist(y_prob[y == 1], bins=30, alpha=0.5, label='Winning Trades', color='green')
    axes[0, 1].axvline(0.75, color='black', linestyle='--', label='Entry Threshold')
    axes[0, 1].set_xlabel('Predicted Probability')
    axes[0, 1].set_ylabel('Count')
    axes[0, 1].set_title('Probability Distribution')
    axes[0, 1].legend()

    # 3. Feature Importance
    importance = np.abs(model.coef_[0])
    sorted_idx = np.argsort(importance)[-10:]  # Top 10
    axes[1, 0].barh(range(len(sorted_idx)), importance[sorted_idx])
    axes[1, 0].set_yticks(range(len(sorted_idx)))
    axes[1, 0].set_yticklabels([feature_names[i] for i in sorted_idx])
    axes[1, 0].set_xlabel('Absolute Coefficient Value')
    axes[1, 0].set_title('Feature Importance (Top 10)')

    # 4. Precision-Recall Curve
    if len(np.unique(y)) > 1:
        precision, recall, thresholds = precision_recall_curve(y, y_prob)
        axes[1, 1].plot(recall, precision)
        axes[1, 1].axhline(0.75, color='red', linestyle='--', label='Target Precision')
        axes[1, 1].axhline(0.60, color='orange', linestyle='--', label='Stop Threshold')
        axes[1, 1].set_xlabel('Recall')
        axes[1, 1].set_ylabel('Precision')
        axes[1, 1].set_title('Precision-Recall Curve')
        axes[1, 1].legend()
        axes[1, 1].grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig('fpf_model_analysis.png', dpi=150)
    print("✅ Analysis plots saved to fpf_model_analysis.png")

def main():
    print("=" * 60)
    print("FPF ML TRAINING PIPELINE")
    print("=" * 60)

    # Load data
    X, y, feature_names = load_and_prepare_data(DATA_FILE)

    if X is None:
        return

    # Train model
    model, scaler = train_model(X, y)

    # Export for EA
    export_model(model, scaler, MODEL_FILE)

    # Generate plots
    plot_analysis(X, y, model, scaler, feature_names)

    print("\n" + "=" * 60)
    print("✅ TRAINING COMPLETE")
    print("=" * 60)
    print(f"\n📁 Model saved to: {MODEL_FILE}")
    print(f"📊 Analysis saved to: fpf_model_analysis.png")
    print("\nNext steps:")
    print("1. Copy fpf_model.txt to your MT5 Files folder")
    print("2. Restart the EA to load the new model")
    print("3. Monitor rolling accuracy and retrain as needed")
    print("\n⚠️  IMPORTANT: Update labels with actual trade outcomes for production!")

if __name__ == "__main__":
    main()
