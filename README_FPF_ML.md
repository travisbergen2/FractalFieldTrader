# FractalFieldTrader - FPF ML Edition

## Complete ML-Based Trading System with Phase Field Prediction

This version integrates:
- **FPF Coupling Matrix Engine** (S+A dynamics)
- **ML-Based Trade Gating** (70-80% probability threshold)
- **Rolling Accuracy Tracking** (auto-shutoff at <60%)
- **Consciousness Circle Indicator** (Z-Field confidence filtering)

---

## 🚀 Quick Start

### 1. Collect Training Data

Run the EA with FPF and ML features enabled:

```
UseFPFEngine = true
LogFPFData = true
UseMLGating = false  // Start with ML disabled to collect data
```

Let it run for at least **50-100 trades** to build a training dataset.

### 2. Train the ML Model

```bash
cd /path/to/FractalFieldTrader
python3 fpf_train_ml_model.py
```

This will:
- Load `TradeData.csv`
- Train a logistic regression model on FPF features
- Export weights to `fpf_model.txt`
- Generate analysis plots

### 3. Deploy the Model

Copy `fpf_model.txt` to your MT5 data folder:
```
<MT5>/MQL5/Files/fpf_model.txt
```

### 4. Enable ML Gating

Restart the EA with ML enabled:
```
UseMLGating = true
ML_EnterThreshold = 0.75  // 75% probability required
ML_StopThreshold = 0.60   // Stop trading if accuracy < 60%
ML_RollingWindow = 20     // Last 20 trades
```

---

## 📊 System Components

### **FPF_Engine.mqh**
Implements J(P) = S + A coupling matrix:

- **S (Symmetric)**: Resonance/coherence component
  ```
  S_ij = α · (P_i+P_j)/2 · cos(β(P_i-P_j)) · e^(-γd_ij) · ...
  ```

- **A (Antisymmetric)**: Orbital rotation component
  ```
  A_ij = δ · (P_i-P_j) · sin(ω(P_i+P_j) + φP_k) · e^(-ηd_ij)
  A_ji = -A_ij
  ```

**Key Metrics**:
- `S_norm`: Resonance intensity (stable market)
- `A_norm`: Orbital intensity (momentum/rotation)
- `Orbital Ratio`: A_norm / S_norm (regime indicator)
- `Spot (x,y)`: 2D phase space position
- `Angular Velocity`: Rotation speed (trend strength)

### **MLPredictor.mqh**
Logistic regression predictor with automatic quality control:

**Entry Logic**:
```
if (predicted_probability >= 0.75) {
    allow_trade();
}
```

**Auto-Shutoff**:
```
if (rolling_accuracy < 0.60) {
    disable_trading();
    alert_user_to_retrain();
}
```

**Outcome Tracking**:
- Stores last N trade results
- Calculates rolling accuracy
- Records prediction probabilities
- Flags model drift

### **ConsciousnessCircle Indicator**
Visual representation of market state with Z-field filtering:

**Z-Field Equation**:
```
Z = Ψ + α·(dΨ/dt) + β·N + γ·S + δ·Q + ε·η + ζ·E
```

Where:
- Ψ: Baseline trend (EMA21 - EMA55)
- dΨ/dt: Momentum
- N: Cognitive (volatility)
- S: Somatic (ATR)
- Q: Quantum (fractal dimension)
- η: Heart (emotion)
- E: Environment (volume ratio)

**Trading Signals**:
- Green dot: Bullish alignment + high Z
- Red dot: Bearish alignment + low Z
- Yellow dot: Low confidence (|Z| < threshold)

---

## 🎯 Trading Strategy

### Phase 1: Data Collection (No ML)
- Run EA with strict entry filters
- Collect 50-100 high-quality trades
- Log FPF states and outcomes

### Phase 2: Initial Training
- Train model on collected data
- Evaluate precision/recall curves
- Adjust probability thresholds if needed

### Phase 3: Live Gating
- Enable ML with 75% entry threshold
- Monitor rolling accuracy (should stay >70%)
- EA auto-disables if accuracy drops <60%

### Phase 4: Continuous Improvement
- Retrain weekly with new data
- Track regime changes (orbital ratio)
- Fine-tune FPF parameters

---

## 🔬 Understanding FPF Dynamics

### Run the Simulator

```bash
python3 fpf_simulate_and_visualize.py
```

This generates:
- **3D trajectory** showing state evolution
- **Norms plot** showing S/A/J intensity over time
- **Phase portrait** with quadrant analysis
- **Animation** of the rotating spot

### Key Insights

**High Resonance (S_norm >> A_norm)**:
- Market in stable equilibrium
- Mean-reversion opportunities
- Lower risk trades

**High Orbital (A_norm >> S_norm)**:
- Strong momentum/rotation
- Trend-following opportunities
- Higher risk/reward

**Balanced (A_norm ≈ S_norm)**:
- Transition regime
- Wait for clarity
- ML may block entries

---

## ⚙️ Parameter Tuning

### FPF Coupling Parameters

**Symmetric (Resonance)**:
```
alpha = 0.5   // Overall resonance strength
beta = 1.0    // Sensitivity to state differences
gamma = 0.6   // Spatial attenuation
kappa = 0.12  // Global field coupling
lambda = 0.8  // Amplitude normalization
```

**Antisymmetric (Orbital)**:
```
delta = 0.35  // Rotation strength
omega = 1.2   // Frequency multiplier
phi = 0.7     // Phase coupling
eta = 0.45    // Rotation attenuation
```

### ML Gating Parameters

```
ML_EnterThreshold = 0.75  // Higher = fewer, better trades
ML_StopThreshold = 0.60   // Safety cutoff
ML_RollingWindow = 20     // Smoothing window
```

**Tuning Guide**:
- Too many small losses? → Increase `ML_EnterThreshold` to 0.80
- Too few trades? → Decrease to 0.70
- Frequent auto-shutoffs? → Increase `ML_StopThreshold` to 0.65

---

## 📈 Performance Monitoring

### Check Rolling Accuracy

The EA prints on every trade close:
```
📊 Trade outcome: ✅ CORRECT | PnL: +125.50 | Prob: 0.823 | Rolling Acc: 72.5%
```

### Model Stats (On EA Shutdown)

```
=== ML Predictor Statistics ===
  Model loaded: YES
  Trading enabled: YES
  Total predictions: 45
  Overall accuracy: 73.3%
  Rolling accuracy: 75.0%
  Enter threshold: 75.0%
  Stop threshold: 60.0%
```

### When to Retrain

Retrain if:
1. **Rolling accuracy < 70%** for sustained period
2. **Market regime changed** (check orbital ratio)
3. **Weekly schedule** (add new data)

---

## 🐛 Troubleshooting

### "ML Model file not found"
- Run `fpf_train_ml_model.py` first
- Copy `fpf_model.txt` to MT5 Files folder
- Restart EA

### "🚫 ML GATING BLOCKED" on all trades
- Model may be overtrained
- Lower `ML_EnterThreshold` temporarily
- Retrain with more diverse data

### "🛑 TRADING DISABLED - Rolling accuracy below threshold"
- Normal! Model detected poor performance
- Check market regime (orbital ratio)
- Retrain model with recent data
- Manually re-enable if confident

### EA not logging FPF metrics
- Ensure `UseFPFEngine = true`
- Ensure `LogFPFData = true`
- Check CSV headers include FPF columns

---

## 📚 Feature Vector (11 dimensions)

The ML model uses these features:

| Index | Feature | Description |
|-------|---------|-------------|
| 0 | State Mean | Average of 5D state |
| 1 | State Std | State variance |
| 2 | State Velocity | Rate of change |
| 3 | S_norm | Resonance intensity |
| 4 | A_norm | Orbital intensity |
| 5 | J_norm | Total field strength |
| 6 | Orbital Ratio | A/S regime indicator |
| 7 | Spot X | Phase position (horizontal) |
| 8 | Spot Y | Phase position (vertical) |
| 9 | Angular Velocity | Rotation speed |
| 10 | Spot Radius | Distance from origin |

---

## 🎓 Advanced: Custom Training

### Use Actual Trade Outcomes

Edit `fpf_train_ml_model.py` to use real P&L:

```python
# Load trade history from MT5
# Create labels based on actual profit/loss
y = (trade_pnl > profit_threshold).astype(int)
```

### Try Different Models

```python
from sklearn.ensemble import RandomForestClassifier

model = RandomForestClassifier(
    n_estimators=100,
    max_depth=10,
    class_weight='balanced'
)
```

### Feature Engineering

Add custom features:
```python
features['volatility_regime'] = df['ATR'] / df['Price']
features['momentum_strength'] = df['Buy'] - df['Sell']
features['trend_alignment'] = df['MA50'] > df['MA200']
```

---

## ⚠️ Risk Disclaimer

This system uses:
- Machine learning (not 100% accurate)
- Complex field dynamics (non-linear)
- Automated gating (can malfunction)

**Always**:
- Start with small position sizes
- Monitor rolling accuracy
- Keep stop losses tight
- Retrain regularly
- Test on demo first

---

## 🛠️ File Structure

```
FractalFieldTrader/
├── FractalFieldTrader/
│   ├── FractalFieldTraderV2.mq5           # Main EA
│   ├── Include/
│   │   ├── Matrix.mqh                     # Matrix utilities
│   │   ├── FPF_Engine.mqh                 # Coupling matrix (S+A)
│   │   ├── MLPredictor.mqh                # ML gating logic
│   │   ├── CoherenceMeasure.mqh           # 5D field calculation
│   │   └── ...                            # Other components
│   └── Indicators/
│       └── ConsciousnessCircle_v2_ZField.mq5  # Visualization
├── fpf_train_ml_model.py                  # Training pipeline
├── fpf_simulate_and_visualize.py          # FPF simulator
├── TradeData.csv                          # Logged trades (generated)
├── fpf_model.txt                          # Trained weights (generated)
└── README_FPF_ML.md                       # This file
```

---

## 📞 Support

For questions or issues:
1. Check this README
2. Review generated plots (`fpf_model_analysis.png`)
3. Examine rolling accuracy logs
4. Verify FPF parameters match simulator

---

## 🚀 Next Steps

1. **Collect Data**: Run EA for 50-100 trades
2. **Train Model**: `python3 fpf_train_ml_model.py`
3. **Visualize FPF**: `python3 fpf_simulate_and_visualize.py`
4. **Deploy Model**: Copy `fpf_model.txt` to MT5
5. **Enable Gating**: Set `UseMLGating = true`
6. **Monitor**: Watch rolling accuracy
7. **Retrain**: Weekly or when accuracy drops

---

## 🎉 You're Ready!

The system will now:
- ✅ Calculate FPF coupling matrices
- ✅ Extract 11D feature vectors
- ✅ Predict trade probability
- ✅ Gate entries at 75% threshold
- ✅ Auto-disable at 60% accuracy
- ✅ Learn and improve over time

**Good luck and trade wisely!** 📈
