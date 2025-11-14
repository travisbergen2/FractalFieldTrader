# FractalFieldTrader v2.0 FPF Integration - Testing Guide

## ✅ Implementation Complete!

All requested components have been implemented and committed to your branch:
`claude/fractalfield-v2-fpf-integration-01WDY2UVrDnnazY1Vu5uwmX4`

---

## 📁 New Files Created

1. **FractalFieldTrader/Include/FPF_StateEngine.mqh**
   - 5-axis FPF state calculation (P, E, N, A, C)
   - Regime detection (6 regimes)
   - Rotation metrics (SpotX/Y, velocity, angle, orbital/resonance energy)

2. **FractalFieldTrader/Include/FPF_TradeLog.mqh**
   - Trade context logging with FPF state
   - R-multiple calculation
   - CSV output for offline analysis

3. **FractalFieldTrader/FractalFieldTrader_FPF.mq5**
   - Main EA with FPF integration
   - Toggleable regime and FPF filters
   - Original logic preserved when filters disabled

4. **FractalFieldTrader/FPF_INTEGRATION_README.md**
   - Comprehensive documentation
   - Detailed explanation of all features

5. **TESTING_GUIDE.md** (this file)

---

## 🚀 Quick Start: Run Your First Backtest

### Step 1: Open MetaTrader 5
1. Launch MT5
2. Press **F4** to open MetaEditor

### Step 2: Locate the EA
1. In MetaEditor, navigate to:
   ```
   Experts → FractalFieldTrader → FractalFieldTrader_FPF.mq5
   ```

### Step 3: Compile
1. Click **Compile** (F7) or press the Compile button
2. Check the **Errors** tab at the bottom
3. **Expected:** 0 errors, 0 warnings
4. If you get errors, check:
   - All `.mqh` files are in the `Include/` folder
   - No typos in file paths
   - MT5 is up to date

### Step 4: Open Strategy Tester
1. In MT5 (not MetaEditor), press **Ctrl+R**
2. This opens the Strategy Tester

### Step 5: Configure Test Settings

**Basic Settings:**
- Expert Advisor: `FractalFieldTrader_FPF`
- Symbol: `EURUSD`
- Period: `M15`
- Date: `2025.01.01` to `2025.11.12`
- Deposit: `100000`
- Leverage: `1:100` (or your broker's default)
- Optimization: None (single test)

### Step 6: Configure EA Inputs

Click **Expert properties** → **Inputs** tab

---

## 📊 Test Configuration: 3 Phases

### **Phase 1: Baseline (Filters OFF)**

**Purpose:** Verify no regression vs original FractalFieldTrader

**Settings:**
```
=== Risk Management ===
RiskPercent = 0.03  (same as your winning test)
MagicNumber = 77777
TradeEnabled = true

=== Market Selection ===
Scan_EURUSD = true
Scan_GBPUSD = false
Scan_USDJPY = false
Scan_XAUUSD = false

=== Timeframe Selection ===
Scan_M15 = true
Scan_H1 = false
Scan_H4 = false

=== Field Thresholds ===
InputCoherence = 55.0
InputAlignment = 53.0

=== FPF FILTERS (CRITICAL!) ===
InpUseRegimeFilter = false  ← DISABLED
InpUseFPFFilter = false     ← DISABLED
InpBaseWindow = 20
InpHalfLife = 10
InpTrapThreshold = 1.0

=== Trade Logging ===
InpEnableTradeLog = true
InpTradeLogPath = "FPF_Trades_Baseline.csv"
```

**Expected Results (from your original test):**
- Net Profit: ~23,800
- Max DD: ~4.4%
- Profit Factor: ~1.58
- Sharpe: ~3.29
- Total Trades: ~191
- Win Rate: ~35%

**If results differ significantly:** There may be a bug in the integration. Report back!

---

### **Phase 2: Regime Filter Only**

**Purpose:** Test regime filtering impact

**Change only these settings:**
```
InpUseRegimeFilter = true   ← ENABLED
InpUseFPFFilter = false     ← STILL DISABLED
InpTradeLogPath = "FPF_Trades_RegimeOnly.csv"
```

**Keep all other settings the same!**

**What to look for:**
- **Trade count:** Should decrease (filtering out CHOP/NONE regimes)
- **Profit factor:** Aim for increase (better quality trades)
- **Max DD:** Aim for decrease (avoiding choppy conditions)
- **Sharpe ratio:** Aim for increase (better risk-adjusted returns)

**Acceptable outcomes:**
- ✅ Fewer trades, higher PF, lower DD = **Success!**
- ⚠️ Fewer trades, similar PF, similar DD = **Neutral** (regime filter not helping)
- ❌ Fewer trades, lower PF, higher DD = **Regime thresholds need tuning**

---

### **Phase 3: Both Filters ON**

**Purpose:** Test combined regime + FPF filtering

**Change only these settings:**
```
InpUseRegimeFilter = true   ← ENABLED
InpUseFPFFilter = true      ← ENABLED
InpFPF_E_Threshold = 0.3
InpFPF_N_Threshold = 0.3
InpTradeLogPath = "FPF_Trades_BothFilters.csv"
```

**What to look for:**
- **Trade count:** Further decrease
- **Win rate:** Should increase (more selective)
- **R-multiple distribution:** Check CSV for positive skew

**Acceptable outcomes:**
- ✅ Significantly fewer trades, much higher PF/Sharpe = **Big win!**
- ⚠️ Too few trades (< 50) = **Filters too restrictive, relax thresholds**
- ❌ Lower returns = **FPF filters cutting winners, need adjustment**

---

## 📈 Reading the Results

### In Strategy Tester Results Tab

**Key Metrics to Compare:**

| Metric | Baseline | Regime Only | Both Filters |
|--------|----------|-------------|--------------|
| **Total Net Profit** | ~23,800 | ? | ? |
| **Max Drawdown %** | ~4.4% | ? | ? |
| **Profit Factor** | ~1.58 | ? | ? |
| **Sharpe Ratio** | ~3.29 | ? | ? |
| **Total Trades** | ~191 | ? | ? |
| **Win Rate %** | ~35% | ? | ? |

**Goal:** Improve Sharpe and PF while maintaining or reducing DD

---

## 📁 CSV Output Files

After each test, find these files in:
```
MT5 Data Folder → MQL5 → Files
```

**Files created:**
1. `TradeData.csv` - Original journal-style log
2. `FPF_Trades_Baseline.csv` - Phase 1 FPF context log
3. `FPF_Trades_RegimeOnly.csv` - Phase 2 FPF context log
4. `FPF_Trades_BothFilters.csv` - Phase 3 FPF context log

**To find MT5 Data Folder:**
1. In MT5, go to **File** → **Open Data Folder**
2. Navigate to `MQL5/Files`

---

## 🔍 CSV Analysis: "Apprentice Mode"

Open any `FPF_Trades_*.csv` file in Excel or Python

**Columns you'll see:**
- Ticket, OpenTime, CloseTime, Symbol, Timeframe, Direction
- EntryPrice, ExitPrice, SL, TP, Profit, **ProfitR** (R-multiple!)
- **P, E, N, A, C** (FPF state at entry)
- **Regime** (market regime at entry)
- SpotX, SpotY, RotVel, RotAngle, OrbitalEnergy, ResonanceEnergy

### Questions to Answer:

**1. Which regimes are profitable?**
```excel
=AVERAGEIF(Regime, "TREND_UP", ProfitR)
=AVERAGEIF(Regime, "REVERSAL_UP", ProfitR)
```

**2. What P/E/N/A/C ranges win?**
Create pivot table:
- Rows: Regime
- Columns: Direction (LONG/SHORT)
- Values: Average of ProfitR

**3. Do high rotation metrics predict success?**
Scatter plot: RotVel vs ProfitR

**4. Are there "apprentice" patterns?**
Filter for trades with ProfitR > 2.0:
- What were the P, E, N values?
- Which regime?
- Spot position (SpotX, SpotY)?

### Example Analysis (Python):
```python
import pandas as pd

df = pd.read_csv('FPF_Trades_BothFilters.csv')

# Average R by regime
regime_performance = df.groupby('Regime')['ProfitR'].agg(['mean', 'count', 'std'])
print(regime_performance)

# Winning patterns
winners = df[df['ProfitR'] > 1.0]
print(f"Winning trades: {len(winners)}")
print(f"Average P: {winners['P'].mean():.3f}")
print(f"Average E: {winners['E'].mean():.3f}")

# Best regimes
best_regime = df.groupby('Regime')['ProfitR'].mean().sort_values(ascending=False)
print(f"\nBest regimes:\n{best_regime}")
```

---

## 🐛 Troubleshooting

### Compilation Errors

**Error: "FPF_StateEngine.mqh not found"**
- Check file is in `FractalFieldTrader/Include/FPF_StateEngine.mqh`
- Not in `MQL5/Include/` (wrong location)

**Error: "Undeclared identifier"**
- Make sure all `.mqh` files are present
- Check spelling in `#include` statements

### Runtime Errors

**"FPF Engine initialization failed"**
- Check symbol exists and has data
- Verify ATR/EMA indicators work on that symbol
- Try on EURUSD first (most reliable)

**"No cached context for ticket"**
- Trade might have been opened before logger initialized
- Check `InpEnableTradeLog = true`
- Verify TradeLogger pointer is valid

### Performance Issues

**Test runs very slow**
- FPF calculations add overhead
- Use "Every tick" mode for most accurate results
- Consider testing shorter periods first (1 month)

**No trades being placed**
- Check if filters are too restrictive
- Print FPF state to journal (uncomment debug lines in `UpdateFPFState()`)
- Verify regime is not always CHOP/NONE

---

## 📝 Reporting Results

When you run tests, please share:

1. **Screenshot of Strategy Tester Results** (for each phase)
2. **Key metrics comparison table** (see template above)
3. **Any unexpected behavior** (errors, warnings, odd patterns)
4. **CSV analysis findings** (if you run offline analysis)

This will help identify:
- Whether integration preserved baseline performance
- Which filters provide edge
- What thresholds need tuning

---

## 🎯 Success Criteria

**Integration is successful if:**
- ✅ Baseline test matches original performance (±5%)
- ✅ At least one filter configuration improves Sharpe ratio
- ✅ CSV logs contain complete FPF context for all trades
- ✅ No runtime errors during backtests

**Red flags:**
- ❌ Baseline test significantly underperforms original
- ❌ All filter configurations reduce profitability
- ❌ Frequent "FPF initialization failed" errors

---

## 📞 Next Steps

1. Run **Phase 1** (Baseline) first
2. Verify results match your original test
3. If baseline is good, run **Phase 2** (Regime only)
4. If Phase 2 is promising, run **Phase 3** (Both filters)
5. Download CSV files and analyze patterns
6. Report findings back

**If baseline doesn't match:**
- Something broke in integration
- Let me know the exact metrics difference
- I can debug and fix

**If filters improve performance:**
- Great! Document the optimal settings
- Consider forward testing on demo
- Analyze CSV to refine thresholds further

**If filters hurt performance:**
- Thresholds may need adjustment
- Some regimes might be mis-classified
- CSV analysis will reveal the issue

---

## 🔧 Fine-Tuning (After Initial Tests)

If initial tests show promise but need optimization:

**Regime Filter Adjustments:**
- Modify regime detection thresholds in `FPF_StateEngine.mqh`
- Example: Change `P > 0.3` to `P > 0.2` for TREND_UP

**FPF Filter Adjustments:**
- Adjust `InpFPF_E_Threshold` and `InpFPF_N_Threshold`
- Try: 0.2, 0.3, 0.4, 0.5
- More restrictive (higher threshold) = fewer trades

**Smoothing Adjustments:**
- Modify `InpHalfLife` (default: 10)
- Lower = more responsive (5)
- Higher = smoother (15)

---

**Ready to test? Fire up MetaTrader and let's see how the FPF filters perform!** 🚀

Good luck with the backtests!
