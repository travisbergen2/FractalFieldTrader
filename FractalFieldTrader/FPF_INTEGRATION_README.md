# FractalFieldTrader v2.0 - FPF Integration

## Overview

This upgrade integrates the **Fractal Pattern Field (FPF)** state engine from RotatingSpot_Phase1 into FractalFieldTrader, adding regime-aware filtering and comprehensive trade logging while preserving the original profitable logic.

---

## New Files Created

### 1. **FPF_StateEngine.mqh**
**Location:** `Include/FPF_StateEngine.mqh`

**Purpose:** Shared module for calculating the 5-axis FPF state vector and detecting market regimes.

**Key Features:**
- **5-Axis State Vector:**
  - **P (Perception):** Trend efficiency = net_move / path_length
  - **E (Emotion):** Bull vs bear candle body pressure
  - **N (Narrative):** Liquidity distribution via swing points
  - **A (Alignment):** Recent sweep direction using ATR
  - **C (Coherence):** Trap detection (bull/bear traps)

- **Regime Detection:**
  - `REGIME_TREND_UP`: P > 0.3 AND E > 0.1
  - `REGIME_TREND_DOWN`: P < -0.3 AND E < -0.1
  - `REGIME_REVERSAL_UP`: P < -0.1 AND N > 0 AND A > 0
  - `REGIME_REVERSAL_DOWN`: P > 0.1 AND N < 0 AND A < 0
  - `REGIME_CHOP`: |P| < 0.15 AND |E| < 0.15
  - `REGIME_NONE`: Mixed/unclear signals

- **Rotation Metrics:**
  - SpotX, SpotY (2D projection using P and E)
  - Rotation velocity, angle
  - Orbital and resonance energy

- **Smoothing:** Exponential moving average with configurable half-life

**Usage:**
```cpp
CFPFStateEngine* fpf = new CFPFStateEngine();
fpf.Init("EURUSD", PERIOD_M15, 20, 10, 1.0);
fpf.CalculateState();
fpf.UpdateRotationMetrics();

double P = fpf.GetP();
MarketRegime regime = fpf.GetRegime();
```

---

### 2. **FPF_TradeLog.mqh**
**Location:** `Include/FPF_TradeLog.mqh`

**Purpose:** Log each trade with full FPF context at entry and outcome at exit for offline "apprentice" analysis.

**CSV Output Columns:**
- Trade metadata: Ticket, OpenTime, CloseTime, Symbol, Timeframe, Direction, Volume
- Price data: EntryPrice, ExitPrice, SL, TP, Profit, **ProfitR** (R-multiple)
- FPF state at entry: P, E, N, A, C, Regime
- Rotation metrics: SpotX, SpotY, RotVel, RotAngle, OrbitalEnergy, ResonanceEnergy

**Key Features:**
- Caches FPF state at trade entry
- Calculates R-multiple (profit relative to risk)
- Writes to CSV for analysis in Excel/Python

**Usage:**
```cpp
CFPFTradeLogger* logger = new CFPFTradeLogger();
logger.Init("MyTrades.csv");

// On trade open:
logger.CacheEntryContext(ticket, time, symbol, tf, direction, lots,
                         entry, sl, tp, fpf_engine);

// On trade close:
logger.RecordTrade(ticket, close_time, exit_price, profit);
```

---

### 3. **FractalFieldTrader_FPF.mq5**
**Location:** `FractalFieldTrader_FPF.mq5`

**Purpose:** Enhanced version of FractalFieldTrader with FPF integration and toggleable filters.

**New Input Parameters:**

```cpp
// === FPF Filters ===
input bool InpUseRegimeFilter = false;      // Enable regime filtering
input bool InpUseFPFFilter = false;         // Enable FPF state filtering
input int InpBaseWindow = 20;               // FPF calculation window
input int InpHalfLife = 10;                 // Smoothing half-life
input double InpTrapThreshold = 1.0;        // ATR multiplier for traps

// === FPF Filter Thresholds ===
input double InpFPF_E_Threshold = 0.3;      // E-axis threshold
input double InpFPF_N_Threshold = 0.3;      // N-axis threshold

// === Trade Logging ===
input bool InpEnableTradeLog = true;
input string InpTradeLogPath = "FractalFieldTrader_FPF_Trades.csv";
```

**Filter Logic:**

**Regime Filter (`InpUseRegimeFilter = true`):**
- **Blocks all trades** in `REGIME_CHOP` or `REGIME_NONE`
- **Long trades** only allowed in:
  - `REGIME_TREND_UP`
  - `REGIME_REVERSAL_UP`
- **Short trades** only allowed in:
  - `REGIME_TREND_DOWN`
  - `REGIME_REVERSAL_DOWN`

**FPF State Filter (`InpUseFPFFilter = true`):**
- **Long trades blocked if:**
  - E < -0.3 (strong bear pressure)
  - N < -0.3 (liquidity strongly above / bearish narrative)
- **Short trades blocked if:**
  - E > 0.3 (strong bull pressure)
  - N > 0.3 (liquidity strongly below / bullish narrative)

**Key Behavior:**
- With **both filters OFF**: Behaves exactly like original FractalFieldTrader
- FPF state updated on each new bar
- FPF context logged for every trade (if `InpEnableTradeLog = true`)

---

## Testing Plan

### Phase 1: Baseline (Filters OFF)
**Settings:**
- `InpUseRegimeFilter = false`
- `InpUseFPFFilter = false`

**Period:** EURUSD M15, 2025-01-01 to 2025-11-12

**Expected Results:**
- Should match original FractalFieldTrader performance:
  - Net profit ≈ 23,800
  - Max DD ≈ 4.4%
  - Profit factor ≈ 1.58
  - Sharpe ≈ 3.29
  - Total trades ≈ 191

**Purpose:** Confirm no regression from FPF integration.

---

### Phase 2: Regime Filter Only
**Settings:**
- `InpUseRegimeFilter = true`
- `InpUseFPFFilter = false`

**Expected Changes:**
- Fewer trades (filtering out CHOP/NONE regimes)
- Potentially higher win rate
- Lower or similar drawdown
- Higher profit factor (if successful)

**Analysis:** Check if regime filtering improves risk-adjusted returns.

---

### Phase 3: Both Filters ON
**Settings:**
- `InpUseRegimeFilter = true`
- `InpUseFPFFilter = true`

**Expected Changes:**
- Further reduction in trade count
- More selective entries
- Aim: Higher quality trades, lower DD, equal/better Sharpe

**Analysis:** Determine if combined filtering provides additional edge.

---

### Phase 4: Offline Analysis
**Using:** `FractalFieldTrader_FPF_Trades.csv`

**Questions to Answer:**
1. Which regimes produce the highest R-multiples?
2. Do specific P/E/N/A/C ranges correlate with winning trades?
3. What rotation metrics (velocity, angle, orbital energy) predict success?
4. Can we identify "apprentice" patterns for future optimization?

**Tools:** Excel, Python (pandas), or your preferred analysis software.

---

## Compilation & Usage

### Step 1: Compile in MetaEditor
1. Open MetaTrader 5
2. Press **F4** to open MetaEditor
3. Navigate to `Experts/FractalFieldTrader/`
4. Open `FractalFieldTrader_FPF.mq5`
5. Click **Compile** (F7)
6. Check for errors in the **Errors** tab

### Step 2: Run Backtest
1. Open Strategy Tester (Ctrl+R)
2. Select `FractalFieldTrader_FPF`
3. Set:
   - Symbol: EURUSD
   - Period: M15
   - Date: 2025.01.01 - 2025.11.12
   - Initial deposit: 100,000
4. Configure inputs (see testing phases above)
5. Click **Start**

### Step 3: Review Results
- Check **Results** tab for profit, DD, trades
- Open **Graph** for equity curve
- Locate CSV files in `MQL5/Files/`:
  - `TradeData.csv` (original journal-style log)
  - `FractalFieldTrader_FPF_Trades.csv` (FPF context log)

---

## Code Structure

### OnInit()
- Initializes original modules (CoherenceMeasure, ChronoceptiveFilter, ObserverState)
- **NEW:** Initializes FPF_StateEngine and FPF_TradeLogger

### OnTick()
- Checks for new bar → calls `UpdateFPFState()`
- Scans markets at interval
- Manages positions
- **NEW:** Logs completed trades with FPF context

### ScanAndTrade()
- Scores all markets/timeframes
- Selects best opportunity
- **NEW:** Applies `PassesFPFFilters()` before trading
- Opens position if all checks pass

### OpenLong() / OpenShort()
- Calculates position size (unchanged)
- Opens trade (unchanged)
- **NEW:** Caches FPF context via `TradeLogger.CacheEntryContext()`

### ManagePosition()
- Applies emergency stop loss
- **NEW:** Logs completed trade via `TradeLogger.RecordTrade()`

---

## Safety & Fallback

**If FPF Engine fails to initialize:**
- EA prints warning but continues running
- Filters are bypassed (all trades pass `PassesFPFFilters()`)
- Original FractalFieldTrader logic remains intact

**If Trade Logger fails:**
- EA prints warning but continues trading
- Only FPF logging is disabled; original CSV still works

**Configuration Checks:**
- Symbol compatibility handled via `SymbolInfoDouble()`
- Indicator handles validated before use
- Array bounds checked in all FPF calculations

---

## Performance Expectations

### Conservative Scenario (Regime Filter Only)
- Trade reduction: 20-30%
- Profit factor increase: 10-20%
- Drawdown reduction: 5-15%
- Win rate increase: 2-5%

### Optimistic Scenario (Both Filters)
- Trade reduction: 40-50%
- Profit factor increase: 25-40%
- Drawdown reduction: 15-25%
- Sharpe ratio increase: 20-30%

### Reality Check
- Initial tests may show **mixed results**
- Filter thresholds (E, N) may need tuning
- Regime detection rules may need adjustment
- **Apprentice analysis** from CSV will guide refinement

---

## Next Steps

1. **Compile & Test:** Run all three backtest phases
2. **Compare Results:** Document differences in metrics
3. **Analyze Logs:** Open CSV and explore FPF patterns
4. **Iterate:** Adjust thresholds based on findings
5. **Forward Test:** Deploy on demo account with filters enabled

---

## Files Summary

| File | Purpose | Status |
|------|---------|--------|
| `Include/FPF_StateEngine.mqh` | 5-axis FPF calculation & regime detection | ✅ Complete |
| `Include/FPF_TradeLog.mqh` | Trade context logging with FPF state | ✅ Complete |
| `FractalFieldTrader_FPF.mq5` | Main EA with FPF integration | ✅ Complete |
| `FPF_INTEGRATION_README.md` | Documentation (this file) | ✅ Complete |

---

## Questions or Issues?

If you encounter compilation errors or unexpected behavior:

1. Check that all `.mqh` files are in `MQL5/Include/` or the EA's `Include/` folder
2. Verify indicator handles are valid (check journal for errors)
3. Ensure sufficient historical data for FPF calculation (min 20 bars)
4. Review filter thresholds (may need relaxing for initial tests)

---

**Good luck with testing! The FPF apprentice analysis should reveal powerful insights into which market states have true edge.** 🚀
