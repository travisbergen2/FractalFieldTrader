//+------------------------------------------------------------------+
//| RotatingSpot_Phase1.mq5                                           |
//| Trades conservatively WHILE collecting rotating spot data         |
//| Phase 1: Survival + Learning                                      |
//+------------------------------------------------------------------+
#property copyright "Travis - Legacy Builder"
#property version   "1.00"
#property strict

//--- Input parameters
input group "=== Risk Management ==="
input double   InpRiskPercent = 0.5;
input double   InpMaxDailyLoss = 2.0;
input int      InpMaxTradesPerDay = 3;
input double   InpMaxDrawdown = 5.0;

input group "=== FPF State Calculation ==="
input int      InpBaseWindow = 20;
input int      InpHalfLife = 10;
input double   InpTrapThreshold = 1.0;      // ATR multiplier for traps (was 2.0 - too strict)

input group "=== Data Collection ==="
input bool     InpEnableDataCollection = true;
input string   InpDataFilePath = "RotatingSpot_Data.csv";
input bool     InpBacktestMode = false;        // Set true for backtesting, false for live/demo

input group "=== Conservative Trading ==="
input int      InpTrendPeriod = 50;
input int      InpEntryPeriod = 20;
input double   InpMinTrendStrength = 0.3;

//--- Global variables
int handleTrendEMA, handleEntryEMA, handleATR;

// FPF State Vector
double StateVector[5];        // [P, E, N, A, C]
double StateVector_Raw[5];
double StateVector_Prev[5];

// Smoothing parameters
double mu;                    // EMA smoothing factor
double lambda;                // Decay factor

// Rotation metrics
double SpotX, SpotY;          // 2D projection
double RotationVelocity;
double RotationAngle;
double OrbitalEnergy;
double ResonanceEnergy;

// Trade tracking
datetime lastTradeTime = 0;
double startingBalance = 0;
double dayStartBalance = 0;
datetime currentDay = 0;
int tradesThisDay = 0;
double maxBalanceToday = 0;

// File handle for data collection
int fileHandle = INVALID_HANDLE;

// Market regime classification
enum MarketRegime
{
   REGIME_NONE = 0,         // unclear / mixed signals
   REGIME_TREND_UP,         // strong uptrend
   REGIME_TREND_DOWN,       // strong downtrend
   REGIME_REVERSAL_UP,      // bottoming, potential pump
   REGIME_REVERSAL_DOWN,    // topping, potential dump
   REGIME_CHOP              // low energy / coil / noisy
};

MarketRegime currentRegime = REGIME_NONE;

// Regime tracking for diagnostics
int countTrendUp = 0;
int countTrendDown = 0;
int countRevUp = 0;
int countRevDown = 0;
int countChop = 0;
int countNone = 0;
int barCounter = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    // Calculate derived parameters
    mu = 1.0 - MathPow(0.5, 1.0 / InpHalfLife);
    lambda = MathPow(0.5, 1.0 / InpHalfLife);
    
    // Initialize indicators
    handleTrendEMA = iMA(_Symbol, _Period, InpTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handleEntryEMA = iMA(_Symbol, _Period, InpEntryPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handleATR = iATR(_Symbol, _Period, 14);
    
    if(handleTrendEMA == INVALID_HANDLE || handleEntryEMA == INVALID_HANDLE || 
       handleATR == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create indicators");
        return INIT_FAILED;
    }
    
    // Initialize state vectors
    ArrayInitialize(StateVector, 0.0);
    ArrayInitialize(StateVector_Raw, 0.0);
    ArrayInitialize(StateVector_Prev, 0.0);
    
    // Initialize tracking
    startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    dayStartBalance = startingBalance;
    maxBalanceToday = startingBalance;
    currentDay = iTime(_Symbol, PERIOD_D1, 0);
    
    // Open data file
    if(InpEnableDataCollection)
    {
        fileHandle = FileOpen(InpDataFilePath, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
        if(fileHandle == INVALID_HANDLE)
        {
            Print("ERROR: Could not open data file");
            return INIT_FAILED;
        }
        
        // Write header
        FileWrite(fileHandle, "Timestamp", "Symbol", "Timeframe",
                  "P", "E", "N", "A", "C",
                  "SpotX", "SpotY",
                  "RotVelocity", "RotAngle", "OrbitalEnergy", "ResonanceEnergy",
                  "Regime",
                  "Price", "ATR",
                  "InTrade", "TradeDirection", "TradeProfit",
                  "Price5", "Price10", "Price20");
    }
    
    Print("=== RotatingSpot Phase 1 EA Initialized ===");
    Print("Starting Balance: $", startingBalance);
    Print("Data Collection: ", InpEnableDataCollection ? "ENABLED" : "DISABLED");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(handleTrendEMA);
    IndicatorRelease(handleEntryEMA);
    IndicatorRelease(handleATR);
    
    if(fileHandle != INVALID_HANDLE)
    {
        FileClose(fileHandle);
        Print("Data file closed. Total records saved.");
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for new bar
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;
    
    // === 1. CALCULATE FPF STATE VECTOR ===
    CalculateStateVector();
    
    // === 2. DETECT CURRENT REGIME ===
    currentRegime = DetectRegime();
    
    // Track regime distribution for diagnostics
    switch(currentRegime)
    {
        case REGIME_TREND_UP:       countTrendUp++; break;
        case REGIME_TREND_DOWN:     countTrendDown++; break;
        case REGIME_REVERSAL_UP:    countRevUp++; break;
        case REGIME_REVERSAL_DOWN:  countRevDown++; break;
        case REGIME_CHOP:           countChop++; break;
        case REGIME_NONE:           countNone++; break;
    }
    
    // Report every 100 bars
    barCounter++;
    if(barCounter % 100 == 0)
    {
        Print("=== REGIME STATS (", barCounter, " bars) ===");
        Print("TREND_UP: ", countTrendUp, " (", (countTrendUp*100.0/barCounter), "%)");
        Print("TREND_DOWN: ", countTrendDown, " (", (countTrendDown*100.0/barCounter), "%)");
        Print("REVERSAL_UP: ", countRevUp, " (", (countRevUp*100.0/barCounter), "%)");
        Print("REVERSAL_DOWN: ", countRevDown, " (", (countRevDown*100.0/barCounter), "%)");
        Print("CHOP: ", countChop, " (", (countChop*100.0/barCounter), "%)");
        Print("NONE: ", countNone, " (", (countNone*100.0/barCounter), "%)");
    }
    
    // === 3. CALCULATE ROTATION METRICS ===
    CalculateRotationMetrics();
    
    // === 3. COLLECT DATA ===
    if(InpEnableDataCollection)
        CollectData();
    
    // === 4. SAFETY CHECKS ===
    if(!SafetyChecks())
        return;
    
    // === 5. MANAGE EXISTING POSITIONS ===
    ManagePositions();
    
    // === 6. LOOK FOR NEW ENTRIES ===
    if(PositionsTotal() == 0)
        CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Calculate 5-axis FPF state vector                                 |
//+------------------------------------------------------------------+
void CalculateStateVector()
{
    // Store previous state
    ArrayCopy(StateVector_Prev, StateVector);
    
    // Calculate raw values
    StateVector_Raw[0] = CalculateP();  // Perception (impulse)
    StateVector_Raw[1] = CalculateE();  // Emotion (bull/bear)
    StateVector_Raw[2] = CalculateN();  // Narrative (liquidity)
    StateVector_Raw[3] = CalculateA();  // Alignment (sweep)
    StateVector_Raw[4] = CalculateC();  // Coherence (traps)
    
    // Apply EMA smoothing
    for(int i = 0; i < 5; i++)
        StateVector[i] = (1.0 - mu) * StateVector[i] + mu * StateVector_Raw[i];
}

//+------------------------------------------------------------------+
//| P-Axis: Trend Efficiency (Impulse vs Corrective)                 |
//+------------------------------------------------------------------+
double CalculateP()
{
    double close[];
    ArraySetAsSeries(close, true);
    if(CopyClose(_Symbol, _Period, 0, InpBaseWindow + 1, close) <= 0)
        return 0.0;
    
    double net_move = close[0] - close[InpBaseWindow];
    double path_length = 0.0;
    
    for(int i = 0; i < InpBaseWindow; i++)
        path_length += MathAbs(close[i] - close[i+1]);
    
    if(path_length < 1e-8) return 0.0;
    
    double efficiency = net_move / path_length;
    return MathMax(-1.0, MathMin(1.0, efficiency));
}

//+------------------------------------------------------------------+
//| E-Axis: Bull vs Bear Pressure                                    |
//+------------------------------------------------------------------+
double CalculateE()
{
    double open[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, _Period, 0, InpBaseWindow, open) <= 0) return 0.0;
    if(CopyClose(_Symbol, _Period, 0, InpBaseWindow, close) <= 0) return 0.0;
    
    double bull_strength = 0.0;
    double bear_strength = 0.0;
    
    for(int i = 0; i < InpBaseWindow; i++)
    {
        double body = close[i] - open[i];
        if(body > 0) bull_strength += body;
        else bear_strength += MathAbs(body);
    }
    
    double total = bull_strength + bear_strength;
    if(total < 1e-8) return 0.0;
    
    return (bull_strength - bear_strength) / total;
}

//+------------------------------------------------------------------+
//| N-Axis: Liquidity Distribution (Simplified Swing-Based)          |
//+------------------------------------------------------------------+
double CalculateN()
{
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    int lookback = InpBaseWindow;
    if(CopyHigh(_Symbol, _Period, 0, lookback, high) <= 0) return 0.0;
    if(CopyLow(_Symbol, _Period, 0, lookback, low) <= 0) return 0.0;
    if(CopyClose(_Symbol, _Period, 0, 1, close) <= 0) return 0.0;
    
    double atr = GetATR();
    double current_price = close[0];
    
    // Count swing highs above and lows below
    double weight_above = 0.0;
    double weight_below = 0.0;
    
    for(int i = 2; i < lookback - 2; i++)
    {
        // Swing high
        if(high[i] > high[i-1] && high[i] > high[i-2] &&
           high[i] > high[i+1] && high[i] > high[i+2])
        {
            if(high[i] > current_price)
            {
                double distance = (high[i] - current_price) / atr;
                weight_above += 1.0 / (1.0 + distance);
            }
        }
        
        // Swing low
        if(low[i] < low[i-1] && low[i] < low[i-2] &&
           low[i] < low[i+1] && low[i] < low[i+2])
        {
            if(low[i] < current_price)
            {
                double distance = (current_price - low[i]) / atr;
                weight_below += 1.0 / (1.0 + distance);
            }
        }
    }
    
    double total = weight_above + weight_below;
    if(total < 1e-8) return 0.0;
    
    // More liquidity below = bullish narrative
    return (weight_below - weight_above) / total;
}

//+------------------------------------------------------------------+
//| A-Axis: Alignment (Last Sweep Direction)                         |
//+------------------------------------------------------------------+
double CalculateA()
{
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(_Symbol, _Period, 0, InpBaseWindow, high) <= 0)
        return StateVector[3] * lambda;
    if(CopyLow(_Symbol, _Period, 0, InpBaseWindow, low) <= 0)
        return StateVector[3] * lambda;
    
    double atr = GetATR();
    double recent_high = high[ArrayMaximum(high, 1, InpBaseWindow - 1)];
    double recent_low = low[ArrayMinimum(low, 1, InpBaseWindow - 1)];
    
    // Check for sweep UP
    if(high[0] > recent_high + InpTrapThreshold * atr)
    {
        double strength = (high[0] - recent_high) / atr;
        return -MathTanh(strength * 0.5);  // Sweep up = bearish alignment
    }
    
    // Check for sweep DOWN
    if(low[0] < recent_low - InpTrapThreshold * atr)
    {
        double strength = (recent_low - low[0]) / atr;
        return MathTanh(strength * 0.5);  // Sweep down = bullish alignment
    }
    
    // No sweep: decay previous value
    return StateVector[3] * lambda;
}

//+------------------------------------------------------------------+
//| C-Axis: Coherence (Trap Detection)                               |
//+------------------------------------------------------------------+
double CalculateC()
{
    double open[], high[], low[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyOpen(_Symbol, _Period, 0, 3, open) <= 0) return StateVector[4] * lambda;
    if(CopyHigh(_Symbol, _Period, 0, 3, high) <= 0) return StateVector[4] * lambda;
    if(CopyLow(_Symbol, _Period, 0, 3, low) <= 0) return StateVector[4] * lambda;
    if(CopyClose(_Symbol, _Period, 0, 3, close) <= 0) return StateVector[4] * lambda;
    
    double atr = GetATR();
    double recent_high = MathMax(high[1], high[2]);
    double recent_low = MathMin(low[1], low[2]);
    
    // Bull trap: wick above, close back down
    bool bull_trap = (high[0] > recent_high + InpTrapThreshold * atr) &&
                     (close[0] < close[1]) &&
                     (close[0] < (high[0] + low[0]) / 2);
    
    // Bear trap: wick below, close back up
    bool bear_trap = (low[0] < recent_low - InpTrapThreshold * atr) &&
                     (close[0] > close[1]) &&
                     (close[0] > (high[0] + low[0]) / 2);
    
    if(bear_trap)
    {
        double strength = (recent_low - low[0]) / atr;
        return MathTanh(strength * 0.5);  // Bears trapped = bullish
    }
    
    if(bull_trap)
    {
        double strength = (high[0] - recent_high) / atr;
        return -MathTanh(strength * 0.5);  // Bulls trapped = bearish
    }
    
    // No trap: decay
    return StateVector[4] * lambda;
}

//+------------------------------------------------------------------+
//| Calculate rotation metrics                                        |
//+------------------------------------------------------------------+
void CalculateRotationMetrics()
{
    // Project to 2D using first two principal components (simplified: P and E)
    SpotX = StateVector[0];  // P-axis
    SpotY = StateVector[1];  // E-axis
    
    // Calculate velocity
    double dx = StateVector[0] - StateVector_Prev[0];
    double dy = StateVector[1] - StateVector_Prev[1];
    RotationVelocity = MathSqrt(dx*dx + dy*dy);
    
    // Calculate angle of movement
    if(RotationVelocity > 1e-6)
        RotationAngle = MathArctan2(dy, dx) * 180.0 / M_PI;
    else
        RotationAngle = 0.0;
    
    // Orbital energy (antisymmetric component estimate)
    OrbitalEnergy = 0.0;
    for(int i = 0; i < 4; i++)
        OrbitalEnergy += MathAbs(StateVector[i] - StateVector[i+1]);
    OrbitalEnergy /= 4.0;
    
    // Resonance energy (symmetric component estimate)
    ResonanceEnergy = 0.0;
    for(int i = 0; i < 5; i++)
        ResonanceEnergy += StateVector[i] * StateVector[i];
    ResonanceEnergy = MathSqrt(ResonanceEnergy / 5.0);
}

//+------------------------------------------------------------------+
//| Detect market regime from FPF state vector                       |
//+------------------------------------------------------------------+
MarketRegime DetectRegime()
{
    double P = StateVector[0]; // Perception (direction & efficiency)
    double E = StateVector[1]; // Emotion (bull vs bear)
    double N = StateVector[2]; // Narrative (liq below vs above)
    double A = StateVector[3]; // Alignment (last sweep)
    double C = StateVector[4]; // Coherence (traps)

    // LOOSENED THRESHOLDS - easier to detect regimes
    
    // Strong uptrend: Just need P and E aligned bullish
    if(P > 0.3 && E > 0.1)
        return REGIME_TREND_UP;

    // Strong downtrend: Just need P and E aligned bearish
    if(P < -0.3 && E < -0.1)
        return REGIME_TREND_DOWN;

    // Bottoming: down perception but narrative/alignment flipped bullish
    if(P < -0.1 && N > 0.0 && A > 0.0)
        return REGIME_REVERSAL_UP;

    // Topping: up perception but narrative/alignment flipped bearish
    if(P > 0.1 && N < 0.0 && A < 0.0)
        return REGIME_REVERSAL_DOWN;

    // Choppy / low-energy / indecisive
    if(MathAbs(P) < 0.15 && MathAbs(E) < 0.15)
        return REGIME_CHOP;

    // Fallback: mixed signals
    return REGIME_NONE;
}

//+------------------------------------------------------------------+
//| Collect data to file                                              |
//+------------------------------------------------------------------+
void CollectData()
{
    if(fileHandle == INVALID_HANDLE) return;
    
    double close[];
    ArraySetAsSeries(close, true);
    
    // In backtest mode, we can look forward
    // In live mode, we only record current state (outcomes labeled later)
    int barsNeeded = InpBacktestMode ? 21 : 1;
    if(CopyClose(_Symbol, _Period, 0, barsNeeded, close) < barsNeeded) return;
    
    double current_price = close[0];
    double atr = GetATR();
    
    // Get current regime
    string regime_str = "";
    switch(currentRegime)
    {
        case REGIME_TREND_UP:       regime_str = "TREND_UP"; break;
        case REGIME_TREND_DOWN:     regime_str = "TREND_DOWN"; break;
        case REGIME_REVERSAL_UP:    regime_str = "REVERSAL_UP"; break;
        case REGIME_REVERSAL_DOWN:  regime_str = "REVERSAL_DOWN"; break;
        case REGIME_CHOP:           regime_str = "CHOP"; break;
        default:                    regime_str = "NONE"; break;
    }
    
    // Get trade info if in position
    bool in_trade = (PositionsTotal() > 0);
    string trade_dir = "";
    double trade_profit = 0.0;
    
    if(in_trade)
    {
        ulong ticket = PositionGetTicket(0);
        if(ticket > 0)
        {
            trade_dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "LONG" : "SHORT";
            trade_profit = PositionGetDouble(POSITION_PROFIT);
        }
    }
    
    // Future price movements for outcome labeling
    string price_5bar_str = "";
    string price_10bar_str = "";
    string price_20bar_str = "";
    
    if(InpBacktestMode)
    {
        // Backtest: can see future, so label outcomes now
        if(barsNeeded >= 21)
        {
            price_5bar_str = DoubleToString(close[5], 5);
            price_10bar_str = DoubleToString(close[10], 5);
            price_20bar_str = DoubleToString(close[20], 5);
        }
    }
    else
    {
        // Live/Demo: can't see future, leave blank (label later in post-processing)
        price_5bar_str = "PENDING";
        price_10bar_str = "PENDING";
        price_20bar_str = "PENDING";
    }
    
    // Write data row
    FileWrite(fileHandle,
              TimeToString(TimeCurrent()), _Symbol, EnumToString(_Period),
              DoubleToString(StateVector[0], 4),
              DoubleToString(StateVector[1], 4),
              DoubleToString(StateVector[2], 4),
              DoubleToString(StateVector[3], 4),
              DoubleToString(StateVector[4], 4),
              DoubleToString(SpotX, 4),
              DoubleToString(SpotY, 4),
              DoubleToString(RotationVelocity, 4),
              DoubleToString(RotationAngle, 2),
              DoubleToString(OrbitalEnergy, 4),
              DoubleToString(ResonanceEnergy, 4),
              regime_str,
              DoubleToString(current_price, 5),
              DoubleToString(atr, 5),
              in_trade ? "YES" : "NO",
              trade_dir,
              DoubleToString(trade_profit, 2),
              price_5bar_str,
              price_10bar_str,
              price_20bar_str);
}

//+------------------------------------------------------------------+
//| Safety checks (same as PropSurvival EA)                          |
//+------------------------------------------------------------------+
bool SafetyChecks()
{
    // Check for new day
    datetime newDay = iTime(_Symbol, PERIOD_D1, 0);
    if(newDay != currentDay)
    {
        currentDay = newDay;
        dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        tradesThisDay = 0;
        maxBalanceToday = dayStartBalance;
    }
    
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(currentBalance > maxBalanceToday)
        maxBalanceToday = currentBalance;
    
    // Check daily loss
    double dailyLoss = (maxBalanceToday - currentBalance) / dayStartBalance * 100.0;
    if(dailyLoss >= InpMaxDailyLoss)
    {
        CloseAllPositions();
        return false;
    }
    
    // Check total drawdown
    double totalDrawdown = (startingBalance - currentBalance) / startingBalance * 100.0;
    if(totalDrawdown >= InpMaxDrawdown)
    {
        CloseAllPositions();
        ExpertRemove();
        return false;
    }
    
    // Check max trades
    if(tradesThisDay >= InpMaxTradesPerDay)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check for entry signals (regime-aware, direction-agnostic)       |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    // Determine current regime from FPF state
    MarketRegime regime = currentRegime;

    // If market is choppy or completely unclear → do nothing
    if(regime == REGIME_CHOP || regime == REGIME_NONE)
        return;

    // Get EMAs & price once here
    double trendEMA[], entryEMA[], close[];
    ArraySetAsSeries(trendEMA, true);
    ArraySetAsSeries(entryEMA, true);
    ArraySetAsSeries(close, true);

    if(CopyBuffer(handleTrendEMA, 0, 0, 3, trendEMA) <= 0) return;
    if(CopyBuffer(handleEntryEMA, 0, 0, 3, entryEMA) <= 0) return;
    if(CopyClose(_Symbol, _Period, 0, 50, close) <= 0) return;

    // Now route by regime
    switch(regime)
    {
        case REGIME_TREND_UP:
            TryLongEntry(close, trendEMA, entryEMA, true);
            break;

        case REGIME_TREND_DOWN:
            TryShortEntry(close, trendEMA, entryEMA, true);
            break;

        case REGIME_REVERSAL_UP:
            TryLongEntry(close, trendEMA, entryEMA, false);  // cautious long
            break;

        case REGIME_REVERSAL_DOWN:
            TryShortEntry(close, trendEMA, entryEMA, false); // cautious short
            break;

        default:
            // REGIME_NONE / REGIME_CHOP or any fall-through: no trade
            break;
    }
}

//+------------------------------------------------------------------+
//| Try to enter long position                                        |
//+------------------------------------------------------------------+
void TryLongEntry(double &close[], double &trendEMA[], double &entryEMA[], bool strongTrend)
{
    // P-axis: trend efficiency should favor up (but looser if reversal)
    double P = StateVector[0];
    double E = StateVector[1];
    double N = StateVector[2];
    double A = StateVector[3];
    double C = StateVector[4];

    double minP = strongTrend ? InpMinTrendStrength : 0.1;
    if(P < minP)
        return;

    // EMA-based uptrend
    bool uptrend = (close[1] > trendEMA[1] && trendEMA[1] > trendEMA[2]);
    if(!uptrend && strongTrend)
        return;

    // Pullback + reclaim: price was below entry EMA, then closes back above
    bool pullback_reclaim =
        (close[2] < entryEMA[2] &&   // dipped below
         close[1] > entryEMA[1]);    // reclaimed

    if(!pullback_reclaim)
        return;

    // RELAXED FPF filters: only block if STRONGLY opposed
    if(E < -0.2)       return; // Only block if bears very strong (was 0.0)
    if(N < -0.3)       return; // Only block if liquidity very unfavorable (was 0.0)
    if(A < -0.4)       return; // Only block if strong bear sweep (was -0.2)
    if(C < -0.5)       return; // Only block if strong bear trap (was -0.3)

    double atr = GetATR();
    double sl = close[1] - atr * 2.0;
    double tp = close[1] + (close[1] - sl) * 2.0;

    OpenTrade(ORDER_TYPE_BUY, sl, tp);
}

//+------------------------------------------------------------------+
//| Try to enter short position                                       |
//+------------------------------------------------------------------+
void TryShortEntry(double &close[], double &trendEMA[], double &entryEMA[], bool strongTrend)
{
    double P = StateVector[0];
    double E = StateVector[1];
    double N = StateVector[2];
    double A = StateVector[3];
    double C = StateVector[4];

    double minP = strongTrend ? InpMinTrendStrength : 0.1;
    if(P > -minP)
        return;

    // EMA-based downtrend
    bool downtrend = (close[1] < trendEMA[1] && trendEMA[1] < trendEMA[2]);
    if(!downtrend && strongTrend)
        return;

    // Pullback + rejection: price was above entry EMA, then closes back below
    bool pullback_reject =
        (close[2] > entryEMA[2] &&   // poked above
         close[1] < entryEMA[1]);    // rejected

    if(!pullback_reject)
        return;

    // RELAXED FPF filters: only block if STRONGLY opposed
    if(E > 0.2)        return; // Only block if bulls very strong (was 0.0)
    if(N > 0.3)        return; // Only block if liquidity very unfavorable (was 0.0)
    if(A > 0.4)        return; // Only block if strong bull sweep (was 0.2)
    if(C > 0.5)        return; // Only block if strong bull trap (was 0.3)

    double atr = GetATR();
    double sl = close[1] + atr * 2.0;
    double tp = close[1] - (sl - close[1]) * 2.0;

    OpenTrade(ORDER_TYPE_SELL, sl, tp);
}

//+------------------------------------------------------------------+
//| Helper functions                                                  |
//+------------------------------------------------------------------+
double GetATR()
{
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handleATR, 0, 0, 1, atr) <= 0)
        return 0.001;
    return atr[0];
}

bool OpenTrade(ENUM_ORDER_TYPE type, double sl, double tp)
{
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) 
                                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
    double slDistance = MathAbs(price - sl);
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double lots = riskAmount / (slDistance / tickSize * tickValue);
    lots = MathFloor(lots / lotStep) * lotStep;
    lots = MathMax(minLot, MathMin(maxLot, lots));
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lots;
    request.type = type;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 789012;
    request.comment = "RotatingSpot_P1";
    
    if(OrderSend(request, result) && result.retcode == TRADE_RETCODE_DONE)
    {
        lastTradeTime = TimeCurrent();
        tradesThisDay++;
        return true;
    }
    
    return false;
}

void ManagePositions()
{
    // Breakeven management (same as before)
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        
        double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double posSL = PositionGetDouble(POSITION_SL);
        double posTP = PositionGetDouble(POSITION_TP);
        double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                              ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                              : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        double riskDistance = MathAbs(posOpenPrice - posSL);
        
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if(currentPrice >= posOpenPrice + riskDistance && posSL < posOpenPrice)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                request.action = TRADE_ACTION_SLTP;
                request.position = ticket;
                request.sl = posOpenPrice + 10 * _Point;
                request.tp = posTP;
                OrderSend(request, result);
            }
        }
        else
        {
            if(currentPrice <= posOpenPrice - riskDistance && posSL > posOpenPrice)
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                request.action = TRADE_ACTION_SLTP;
                request.position = ticket;
                request.sl = posOpenPrice - 10 * _Point;
                request.tp = posTP;
                OrderSend(request, result);
            }
        }
    }
}

void CloseAllPositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.position = ticket;
        request.symbol = _Symbol;
        request.volume = PositionGetDouble(POSITION_VOLUME);
        request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
                       ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
        request.price = (request.type == ORDER_TYPE_SELL) 
                        ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        OrderSend(request, result);
    }
}
